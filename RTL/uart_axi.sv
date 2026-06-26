// UART AXI — AXI-Lite 8N1 UART peripheral, Standard SFR Register Map
//
// Register layout (AWADDR/ARADDR [7:2] index):
//   0x00  CTRL        RW   [0]=uart_en
//   0x04  STATUS      RO   [1]=rx_done (INTR_STATE[1] mirror) [0]=tx_busy
//   0x08  INTR_ENABLE RW   [1]=rx_done IRQ en  [0]=tx_done IRQ en
//   0x0C  INTR_STATE  RW1C [1]=rx_complete  [0]=tx_done  (W1C)
//   0x10  INTR_TEST   WO   force-set INTR_STATE bits
//   0x14  DATA0       RW   baud_div: bit period = (baud_div+1) clocks
//   0x18  DATA1       RW   TX: writing triggers 8N1 transmission (if uart_en && !tx_busy)
//   0x1C  DATA2       RO   RX: last received byte (hardware-written on RX complete)
//   0xFC  PERIPH_ID   RO   0x55415254 ("UART")
//
// TX: start → 8 data bits (LSB first) → stop; triggered by AXI write to DATA1
// RX: 2-FF sync → falling edge start → sample at bit mid-point (baud_div/2 offset)
// IRQ: irq = |(INTR_STATE & INTR_ENABLE)
// PERIPH_ID: 0x55415254 (ASCII "UART")

`timescale 1ns/1ps

module uart_axi #(
    parameter logic [31:0] PERIPH_ID_VAL = 32'h5541_5254
)(
    input  logic        clk,
    input  logic        rst_n,

    // AXI4-Lite Slave
    input  logic [31:0] AWADDR,
    input  logic [2:0]  AWPROT,
    input  logic        AWVALID,
    output logic        AWREADY,

    input  logic [31:0] WDATA,
    input  logic [3:0]  WSTRB,
    input  logic        WVALID,
    output logic        WREADY,

    output logic [1:0]  BRESP,
    output logic        BVALID,
    input  logic        BREADY,

    input  logic [31:0] ARADDR,
    input  logic [2:0]  ARPROT,
    input  logic        ARVALID,
    output logic        ARREADY,

    output logic [31:0] RDATA,
    output logic [1:0]  RRESP,
    output logic        RVALID,
    input  logic        RREADY,

    input  logic        uart_rx,
    output logic        uart_tx,
    output logic        irq
);
    localparam IDX_CTRL       = 6'h00;
    localparam IDX_STATUS     = 6'h01;
    localparam IDX_INTR_EN    = 6'h02;
    localparam IDX_INTR_STATE = 6'h03;
    localparam IDX_INTR_TEST  = 6'h04;
    localparam IDX_DATA0      = 6'h05;  // baud_div
    localparam IDX_DATA1      = 6'h06;  // TX trigger
    localparam IDX_DATA2      = 6'h07;  // RX data (HW-written)
    localparam IDX_PERIPH_ID  = 6'h3F;

    localparam IDLE    = 2'd0;
    localparam WR_RESP = 2'd1;
    localparam RD_RESP = 2'd2;

    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    // ── AXI handshake ────────────────────────────────────────────────
    logic [1:0]  state;
    logic        aw_got, w_got;
    logic [5:0]  aw_idx_r;
    logic [31:0] w_data_r;
    logic [3:0]  w_strb_r;
    logic [5:0]  rd_idx_r;

    logic [5:0] awaddr_idx, araddr_idx;
    assign awaddr_idx = AWADDR[7:2];
    assign araddr_idx = ARADDR[7:2];

    assign AWREADY = (state == IDLE) && !aw_got;
    assign WREADY  = (state == IDLE) && !w_got;
    assign ARREADY = (state == IDLE) && !aw_got && !w_got;

    logic aw_now, w_now;
    assign aw_now = AWVALID && AWREADY;
    assign w_now  = WVALID  && WREADY;

    logic aw_pending_next, w_pending_next, both_pending;
    assign aw_pending_next = aw_got || aw_now;
    assign w_pending_next  = w_got  || w_now;
    assign both_pending    = aw_pending_next && w_pending_next;

    logic [5:0]  wr_idx;
    logic [31:0] wr_data;
    logic [3:0]  wr_strb;
    assign wr_idx  = aw_now ? awaddr_idx : aw_idx_r;
    assign wr_data = w_now  ? WDATA      : w_data_r;
    assign wr_strb = w_now  ? WSTRB      : w_strb_r;

    logic [31:0] be_mask;
    assign be_mask = {{8{wr_strb[3]}}, {8{wr_strb[2]}}, {8{wr_strb[1]}}, {8{wr_strb[0]}}};

    // ── SFR registers ────────────────────────────────────────────────
    logic [31:0] reg_ctrl;
    logic [31:0] reg_intr_enable;
    logic [31:0] reg_intr_state;
    logic [31:0] reg_data0;   // baud_div
    logic [31:0] reg_data1;   // TX hold (last written; not used by TX logic itself)
    logic [31:0] reg_data2;   // RX hold (HW written)

    logic uart_en;
    assign uart_en = reg_ctrl[0];

    // ── 2-FF synchronizer for uart_rx ───────────────────────────────
    logic rx_s1, rx_s2, rx_s2_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1      <= 1'b1;
            rx_s2      <= 1'b1;
            rx_s2_prev <= 1'b1;
        end else begin
            rx_s1      <= uart_rx;
            rx_s2      <= rx_s1;
            rx_s2_prev <= rx_s2;
        end
    end

    // Falling edge on synchronized RX (start bit detect)
    logic rx_fall;
    assign rx_fall = (~rx_s2) & rx_s2_prev;

    // ── TX FSM ───────────────────────────────────────────────────────
    logic [1:0]  tx_state;
    logic [31:0] tx_baud_cnt;
    logic [7:0]  tx_shift;
    logic [2:0]  tx_bit_cnt;
    logic        tx_done_pulse;

    // Bit extractions (outside always per Icarus rule)
    logic        tx_baud_tick;
    logic        tx_busy_w;
    logic        tx_load_w;
    logic        tx_shift_lsb;
    logic [7:0]  tx_shift_shr;
    logic [7:0]  tx_load_byte;

    assign tx_baud_tick = (tx_baud_cnt == reg_data0);
    assign tx_busy_w    = (tx_state != TX_IDLE);
    assign tx_load_w    = (state == IDLE) && both_pending &&
                          (wr_idx == IDX_DATA1) && !tx_busy_w && uart_en;
    assign tx_shift_lsb = tx_shift[0];
    assign tx_shift_shr = {1'b0, tx_shift[7:1]};
    assign tx_load_byte = wr_data[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state      <= TX_IDLE;
            tx_baud_cnt   <= 32'd0;
            tx_shift      <= 8'd0;
            tx_bit_cnt    <= 3'd0;
            uart_tx       <= 1'b1;
            tx_done_pulse <= 1'b0;
        end else begin
            tx_done_pulse <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    if (tx_load_w) begin
                        tx_shift    <= tx_load_byte;
                        tx_baud_cnt <= 32'd0;
                        tx_bit_cnt  <= 3'd0;
                        tx_state    <= TX_START;
                    end
                end
                TX_START: begin
                    uart_tx <= 1'b0;
                    if (tx_baud_tick) begin
                        tx_baud_cnt <= 32'd0;
                        tx_state    <= TX_DATA;
                    end else
                        tx_baud_cnt <= tx_baud_cnt + 32'd1;
                end
                TX_DATA: begin
                    uart_tx <= tx_shift_lsb;
                    if (tx_baud_tick) begin
                        tx_baud_cnt <= 32'd0;
                        tx_shift    <= tx_shift_shr;
                        if (tx_bit_cnt == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_cnt <= tx_bit_cnt + 3'd1;
                    end else
                        tx_baud_cnt <= tx_baud_cnt + 32'd1;
                end
                TX_STOP: begin
                    uart_tx <= 1'b1;
                    if (tx_baud_tick) begin
                        tx_done_pulse <= 1'b1;
                        tx_baud_cnt   <= 32'd0;
                        tx_state      <= TX_IDLE;
                    end else
                        tx_baud_cnt <= tx_baud_cnt + 32'd1;
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // ── RX FSM ───────────────────────────────────────────────────────
    logic [1:0]  rx_state;
    logic [31:0] rx_baud_cnt;
    logic [7:0]  rx_shift;
    logic [2:0]  rx_bit_cnt;
    logic        rx_complete_pulse;

    logic [31:0] baud_half;
    logic        rx_baud_tick, rx_half_tick;
    logic        rx_s2_cur;
    logic [6:0]  rx_shift_upper;
    logic [7:0]  rx_shift_shr;

    assign baud_half     = {1'b0, reg_data0[31:1]};
    assign rx_baud_tick  = (rx_baud_cnt == reg_data0);
    assign rx_half_tick  = (rx_baud_cnt == baud_half);
    assign rx_s2_cur     = rx_s2;
    assign rx_shift_upper = rx_shift[7:1];
    assign rx_shift_shr  = {rx_s2_cur, rx_shift_upper};  // shift right, new bit at MSB

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state          <= RX_IDLE;
            rx_baud_cnt       <= 32'd0;
            rx_shift          <= 8'd0;
            rx_bit_cnt        <= 3'd0;
            rx_complete_pulse <= 1'b0;
        end else begin
            rx_complete_pulse <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    if (uart_en && rx_fall) begin
                        rx_baud_cnt <= 32'd0;
                        rx_bit_cnt  <= 3'd0;
                        rx_state    <= RX_START;
                    end
                end
                RX_START: begin
                    // Count to baud_half to align sample to bit mid-point
                    if (rx_half_tick) begin
                        rx_baud_cnt <= 32'd0;
                        rx_state    <= RX_DATA;
                    end else
                        rx_baud_cnt <= rx_baud_cnt + 32'd1;
                end
                RX_DATA: begin
                    if (rx_baud_tick) begin
                        rx_shift    <= rx_shift_shr;   // sample rx_s2 into MSB, shift right
                        rx_baud_cnt <= 32'd0;
                        if (rx_bit_cnt == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_cnt <= rx_bit_cnt + 3'd1;
                    end else
                        rx_baud_cnt <= rx_baud_cnt + 32'd1;
                end
                RX_STOP: begin
                    if (rx_baud_tick) begin
                        rx_complete_pulse <= 1'b1;
                        rx_baud_cnt       <= 32'd0;
                        rx_state          <= RX_IDLE;
                    end else
                        rx_baud_cnt <= rx_baud_cnt + 32'd1;
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // ── irq sources: [1]=rx_complete  [0]=tx_done ───────────────────
    logic [31:0] irq_src_set;
    assign irq_src_set = {30'd0, rx_complete_pulse, tx_done_pulse};

    // STATUS word: [1]=rx_done (INTR_STATE[1] mirror) [0]=tx_busy
    logic intr_state_1;
    assign intr_state_1 = reg_intr_state[1];

    logic [31:0] status_w;
    assign status_w = {30'd0, intr_state_1, tx_busy_w};

    // ── SFR register write ────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl        <= 32'd0;
            reg_intr_enable <= 32'd0;
            reg_intr_state  <= 32'd0;
            reg_data0       <= 32'd0;
            reg_data1       <= 32'd0;
            reg_data2       <= 32'd0;
        end else begin
            // Accumulate TX done / RX complete into INTR_STATE
            reg_intr_state <= reg_intr_state | irq_src_set;
            // RX complete: latch received byte into DATA2
            if (rx_complete_pulse)
                reg_data2 <= {24'd0, rx_shift};
            // Bus write (last NBA wins for intr_state)
            if (state == IDLE && both_pending) begin
                case (wr_idx)
                    IDX_CTRL:
                        reg_ctrl <= (wr_data & be_mask) | (reg_ctrl & ~be_mask);
                    IDX_INTR_EN:
                        reg_intr_enable <= (wr_data & be_mask) | (reg_intr_enable & ~be_mask);
                    IDX_INTR_STATE:
                        reg_intr_state <= (reg_intr_state | irq_src_set) & ~(wr_data & be_mask);
                    IDX_INTR_TEST:
                        reg_intr_state <= reg_intr_state | irq_src_set | (wr_data & be_mask);
                    IDX_DATA0:
                        reg_data0 <= (wr_data & be_mask) | (reg_data0 & ~be_mask);
                    IDX_DATA1:
                        reg_data1 <= (wr_data & be_mask) | (reg_data1 & ~be_mask);
                    default: ;
                endcase
            end
        end
    end

    // ── AXI FSM + pending buffers ─────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            aw_got   <= 1'b0;
            w_got    <= 1'b0;
            aw_idx_r <= 6'd0;
            w_data_r <= 32'd0;
            w_strb_r <= 4'd0;
            rd_idx_r <= 6'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (aw_now) begin aw_idx_r <= awaddr_idx; aw_got <= 1'b1; end
                    if (w_now)  begin w_data_r <= WDATA; w_strb_r <= WSTRB; w_got <= 1'b1; end
                    if (both_pending) begin state <= WR_RESP; aw_got <= 1'b0; w_got <= 1'b0; end
                    if (ARVALID && ARREADY) begin rd_idx_r <= araddr_idx; state <= RD_RESP; end
                end
                WR_RESP: if (BREADY) state <= IDLE;
                RD_RESP: if (RREADY) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    // ── Read data mux ─────────────────────────────────────────────────
    logic [31:0] rd_data_mux;
    always_comb begin
        case (rd_idx_r)
            IDX_CTRL:       rd_data_mux = reg_ctrl;
            IDX_STATUS:     rd_data_mux = status_w;
            IDX_INTR_EN:    rd_data_mux = reg_intr_enable;
            IDX_INTR_STATE: rd_data_mux = reg_intr_state;
            IDX_DATA0:      rd_data_mux = reg_data0;
            IDX_DATA1:      rd_data_mux = reg_data1;
            IDX_DATA2:      rd_data_mux = reg_data2;
            IDX_PERIPH_ID:  rd_data_mux = PERIPH_ID_VAL;
            default:        rd_data_mux = 32'd0;
        endcase
    end

    assign RDATA  = rd_data_mux;
    assign BVALID = (state == WR_RESP);
    assign BRESP  = 2'b00;
    assign RVALID = (state == RD_RESP);
    assign RRESP  = 2'b00;

    logic [31:0] intr_masked;
    assign intr_masked = reg_intr_state & reg_intr_enable;
    assign irq = |intr_masked;

endmodule
