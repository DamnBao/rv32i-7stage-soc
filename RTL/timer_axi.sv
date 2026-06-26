// Timer AXI — AXI-Lite Timer peripheral, Standard SFR Register Map
//
// Register layout (AWADDR/ARADDR [7:2] index):
//   0x00  CTRL        RW   [0]=enable  [1]=auto_reload (reset counter on compare match)
//   0x04  STATUS      RO   current timer_cnt value (read-only snapshot)
//   0x08  INTR_ENABLE RW   [0]=compare_match IRQ enable
//   0x0C  INTR_STATE  RW1C [0]=compare match pending (W1C to clear)
//   0x10  INTR_TEST   WO   write 1 to force-set INTR_STATE[0] (software test)
//   0x14  DATA0       RW   PRESCALER — counter ticks every (PRESCALER+1) clock cycles
//   0x18  DATA1       RW   COMPARE   — counter value that triggers IRQ
//   0x1C  DATA2       RW   (reserved/unused)
//   0xFC  PERIPH_ID   RO   0x54494D52 ("TIMR")
//
// Timer behavior:
//   psc_cnt counts 0 to PRESCALER, resets → generates one tick per (PRESCALER+1) cycles
//   timer_cnt increments one per tick
//   On compare match (timer_cnt == COMPARE):
//     INTR_STATE[0] = 1  (latched; cleared by W1C write or software)
//     if auto_reload: timer_cnt resets to 0; else continues counting
//
// IRQ: irq = INTR_STATE[0] & INTR_ENABLE[0]
// PERIPH_ID: 0x54494D52 (ASCII "TIMR")

`timescale 1ns/1ps

module timer_axi #(
    parameter logic [31:0] PERIPH_ID_VAL = 32'h5449_4D52
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

    output logic        irq
);
    localparam IDX_CTRL       = 6'h00;
    localparam IDX_STATUS     = 6'h01;
    localparam IDX_INTR_EN    = 6'h02;
    localparam IDX_INTR_STATE = 6'h03;
    localparam IDX_INTR_TEST  = 6'h04;
    localparam IDX_DATA0      = 6'h05;  // PRESCALER
    localparam IDX_DATA1      = 6'h06;  // COMPARE
    localparam IDX_DATA2      = 6'h07;  // reserved
    localparam IDX_PERIPH_ID  = 6'h3F;

    localparam IDLE    = 2'd0;
    localparam WR_RESP = 2'd1;
    localparam RD_RESP = 2'd2;

    // ── AXI handshake state ─────────────────────────────────────
    logic [1:0] state;
    logic       aw_got, w_got;
    logic [5:0] aw_idx_r;
    logic [31:0] w_data_r;
    logic [3:0]  w_strb_r;
    logic [5:0]  rd_idx_r;

    // Address extraction (bit-selects outside always per Icarus rule)
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

    // ── SFR Registers ───────────────────────────────────────────
    logic [31:0] reg_ctrl;
    logic [31:0] reg_intr_enable;
    logic [31:0] reg_intr_state;
    logic [31:0] reg_prescaler;   // DATA0
    logic [31:0] reg_compare;     // DATA1

    // ── Timer state ─────────────────────────────────────────────
    logic [31:0] psc_cnt;
    logic [31:0] timer_cnt;

    // Control bits extracted (outside always per Icarus rule)
    logic timer_en, auto_reload;
    assign timer_en    = reg_ctrl[0];
    assign auto_reload = reg_ctrl[1];

    // Prescaler tick: fires when psc_cnt reaches reg_prescaler
    logic tick_w;
    assign tick_w = timer_en && (psc_cnt == reg_prescaler);

    // Compare match: one cycle after tick fires at compare value
    logic cmp_match_w;
    assign cmp_match_w = tick_w && (timer_cnt == reg_compare);

    // irq_src as 32-bit mask for INTR_STATE ORing
    logic [31:0] cmp_match_set;
    assign cmp_match_set = {31'd0, cmp_match_w};

    // ── Prescaler counter ─────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psc_cnt <= 32'd0;
        end else if (timer_en) begin
            if (psc_cnt == reg_prescaler)
                psc_cnt <= 32'd0;
            else
                psc_cnt <= psc_cnt + 32'd1;
        end else begin
            psc_cnt <= 32'd0;
        end
    end

    // ── Main counter ─────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_cnt <= 32'd0;
        end else if (tick_w) begin
            if (timer_cnt == reg_compare)
                timer_cnt <= auto_reload ? 32'd0 : timer_cnt + 32'd1;
            else
                timer_cnt <= timer_cnt + 32'd1;
        end
    end

    // ── SFR Register write ────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl        <= 32'd0;
            reg_intr_enable <= 32'd0;
            reg_intr_state  <= 32'd0;
            reg_prescaler   <= 32'd0;
            reg_compare     <= 32'd0;
        end else begin
            // Accumulate compare match into INTR_STATE[0]
            reg_intr_state <= reg_intr_state | cmp_match_set;
            // Bus write (last NBA wins for intr_state)
            if (state == IDLE && both_pending) begin
                case (wr_idx)
                    IDX_CTRL:
                        reg_ctrl <= (wr_data & be_mask) | (reg_ctrl & ~be_mask);
                    IDX_INTR_EN:
                        reg_intr_enable <= (wr_data & be_mask) | (reg_intr_enable & ~be_mask);
                    IDX_INTR_STATE:
                        reg_intr_state <= (reg_intr_state | cmp_match_set) & ~(wr_data & be_mask);
                    IDX_INTR_TEST:
                        reg_intr_state <= reg_intr_state | cmp_match_set | (wr_data & be_mask);
                    IDX_DATA0:
                        reg_prescaler <= (wr_data & be_mask) | (reg_prescaler & ~be_mask);
                    IDX_DATA1:
                        reg_compare <= (wr_data & be_mask) | (reg_compare & ~be_mask);
                    default: ;
                endcase
            end
        end
    end

    // ── AXI FSM + pending buffers ─────────────────────────────────
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

    // ── Read data mux ─────────────────────────────────────────────
    logic [31:0] rd_data_mux;
    always_comb begin
        case (rd_idx_r)
            IDX_CTRL:       rd_data_mux = reg_ctrl;
            IDX_STATUS:     rd_data_mux = timer_cnt;        // current counter (read-only)
            IDX_INTR_EN:    rd_data_mux = reg_intr_enable;
            IDX_INTR_STATE: rd_data_mux = reg_intr_state;
            IDX_DATA0:      rd_data_mux = reg_prescaler;
            IDX_DATA1:      rd_data_mux = reg_compare;
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
