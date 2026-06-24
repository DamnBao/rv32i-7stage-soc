// AXI-Lite Slave SFR — Standard Register Map (OpenTitan-inspired)
//
// Register layout (AWADDR[7:2] selects, word-aligned):
//   0x00  CTRL        RW     bit[0]=enable; bits[31:1]=peripheral-specific
//   0x04  STATUS      RO     driven by status_in (peripheral-supplied)
//   0x08  INTR_ENABLE RW     interrupt enable mask per source
//   0x0C  INTR_STATE  RW1C   pending flags; write 1 to clear
//   0x10  INTR_TEST   WO     write 1 to force-set INTR_STATE (debug/test)
//   0x14  DATA0       RW     general-purpose data 0
//   0x18  DATA1       RW     general-purpose data 1
//   0x1C  DATA2       RW     general-purpose data 2
//   0xFC  PERIPH_ID   RO     hardcoded peripheral identifier (parameter)
//
// IRQ: irq = |(INTR_STATE & INTR_ENABLE)
// irq_src: external event → sets INTR_STATE[0] each cycle it is high
// WSTRB: byte-enable per write; BRESP/RRESP: always OKAY (2'b00)

module axi_sfr #(
    parameter logic [31:0] PERIPH_ID_VAL = 32'h5346_5230
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

    // Peripheral interface
    input  logic [31:0] status_in,   // peripheral → readable via STATUS reg
    input  logic        irq_src,     // external event → sets INTR_STATE[0]
    output logic [31:0] data0_out,
    output logic [31:0] data1_out,
    output logic [31:0] data2_out,
    output logic        irq          // = |(INTR_STATE & INTR_ENABLE)
);

    localparam IDX_CTRL       = 6'h00;
    localparam IDX_STATUS     = 6'h01;
    localparam IDX_INTR_EN    = 6'h02;
    localparam IDX_INTR_STATE = 6'h03;
    localparam IDX_INTR_TEST  = 6'h04;
    localparam IDX_DATA0      = 6'h05;
    localparam IDX_DATA1      = 6'h06;
    localparam IDX_DATA2      = 6'h07;
    localparam IDX_PERIPH_ID  = 6'h3F;

    localparam IDLE    = 2'd0;
    localparam WR_RESP = 2'd1;
    localparam RD_RESP = 2'd2;

    logic [1:0] state;

    // Address extraction (Icarus-safe: outside always blocks)
    logic [5:0] awaddr_idx;
    logic [5:0] araddr_idx;
    assign awaddr_idx = AWADDR[7:2];
    assign araddr_idx = ARADDR[7:2];

    // AW/W pending buffers
    logic       aw_got, w_got;
    logic [5:0] aw_idx_r;
    logic [31:0] w_data_r;
    logic [3:0]  w_strb_r;
    logic [5:0]  rd_idx_r;

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

    // irq_src as full-word mask (avoids bit-select inside always)
    logic [31:0] irq_src_set;
    assign irq_src_set = {31'd0, irq_src};

    // Registers
    logic [31:0] reg_ctrl;
    logic [31:0] reg_intr_enable;
    logic [31:0] reg_intr_state;
    logic [31:0] reg_data0;
    logic [31:0] reg_data1;
    logic [31:0] reg_data2;

    // Register write (irq_src base, overridden by explicit bus write)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl        <= 32'd0;
            reg_intr_enable <= 32'd0;
            reg_intr_state  <= 32'd0;
            reg_data0       <= 32'd0;
            reg_data1       <= 32'd0;
            reg_data2       <= 32'd0;
        end else begin
            // Default: accumulate irq_src into intr_state
            reg_intr_state <= reg_intr_state | irq_src_set;
            // Bus write takes priority (last NBA wins in SV)
            if (state == IDLE && both_pending) begin
                case (wr_idx)
                    IDX_CTRL:
                        reg_ctrl <= (wr_data & be_mask) | (reg_ctrl & ~be_mask);
                    IDX_INTR_EN:
                        reg_intr_enable <= (wr_data & be_mask) | (reg_intr_enable & ~be_mask);
                    IDX_INTR_STATE:
                        // W1C: clear bits where wr_data=1; keep irq_src contribution
                        reg_intr_state <= (reg_intr_state | irq_src_set) & ~(wr_data & be_mask);
                    IDX_INTR_TEST:
                        // Force-set INTR_STATE bits
                        reg_intr_state <= reg_intr_state | irq_src_set | (wr_data & be_mask);
                    IDX_DATA0:
                        reg_data0 <= (wr_data & be_mask) | (reg_data0 & ~be_mask);
                    IDX_DATA1:
                        reg_data1 <= (wr_data & be_mask) | (reg_data1 & ~be_mask);
                    IDX_DATA2:
                        reg_data2 <= (wr_data & be_mask) | (reg_data2 & ~be_mask);
                    default: ;
                endcase
            end
        end
    end

    // FSM + pending buffer
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

    // Read data mux
    logic [31:0] rd_data_mux;
    always_comb begin
        case (rd_idx_r)
            IDX_CTRL:       rd_data_mux = reg_ctrl;
            IDX_STATUS:     rd_data_mux = status_in;
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

    assign data0_out = reg_data0;
    assign data1_out = reg_data1;
    assign data2_out = reg_data2;

    logic [31:0] intr_masked;
    assign intr_masked = reg_intr_state & reg_intr_enable;
    assign irq = |intr_masked;

endmodule
