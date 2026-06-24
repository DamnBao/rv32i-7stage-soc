// AXI-Lite Slave SFR (1GHz domain)
//
// Generic SFR peripheral với 8 × 32-bit registers.
// Reg address: AWADDR/ARADDR [4:2] (3-bit → 8 word registers, offset 0x000..0x01C)
//
// Write protocol:
//   AW + W có thể đến đồng thời hoặc lần lượt → track riêng (aw_got, w_got)
//   Khi cả hai có mặt: ghi register (với WSTRB byte-enable), phát BVALID
//
// Read protocol:
//   Chấp nhận ARVALID khi IDLE (không có write pending)
//   Ngay chu kỳ sau: RVALID=1, RDATA=sfr_reg[rd_idx_r]
//
// Register map:
//   Offset 0x00 (REG0): Control
//   Offset 0x04 (REG1): Status
//   Offset 0x08..0x18: General-purpose
//   Offset 0x1C (REG7): IRQ — REG7[0]=1 → assert irq output
//
// WSTRB: byte-enable ghi từng byte trong register (read-modify-write)
// BRESP/RRESP: luôn 2'b00 (OKAY)

module axi_sfr (
    input  logic        clk,
    input  logic        rst_n,

    //----------------- AXI4-LITE SLAVE -----------------
    // Write address
    input  logic [31:0] AWADDR,
    input  logic [2:0]  AWPROT,
    input  logic        AWVALID,
    output logic        AWREADY,

    // Write data
    input  logic [31:0] WDATA,
    input  logic [3:0]  WSTRB,
    input  logic        WVALID,
    output logic        WREADY,

    // Write response
    output logic [1:0]  BRESP,
    output logic        BVALID,
    input  logic        BREADY,

    // Read address
    input  logic [31:0] ARADDR,
    input  logic [2:0]  ARPROT,
    input  logic        ARVALID,
    output logic        ARREADY,

    // Read data
    output logic [31:0] RDATA,
    output logic [1:0]  RRESP,
    output logic        RVALID,
    input  logic        RREADY,

    //----------------- IRQ -----------------
    output logic        irq   // = sfr_reg[7][0]
);

    //=========================================================
    // FSM States
    //=========================================================
    localparam IDLE    = 2'd0;
    localparam WR_RESP = 2'd1;   // Sending B response
    localparam RD_RESP = 2'd2;   // Sending R response

    logic [1:0] state;

    //=========================================================
    // Pre-extract địa chỉ register (Icarus-safe)
    //=========================================================
    logic [2:0] awaddr_4_2, araddr_4_2;
    assign awaddr_4_2 = AWADDR[4:2];
    assign araddr_4_2 = ARADDR[4:2];

    //=========================================================
    // AW/W Pending Buffers
    //    aw_got: đã nhận địa chỉ ghi, chờ data
    //    w_got:  đã nhận data, chờ địa chỉ
    //=========================================================
    logic        aw_got, w_got;
    logic [2:0]  aw_idx_r;   // Registered AW address
    logic [31:0] w_data_r;   // Registered W data
    logic [3:0]  w_strb_r;   // Registered W strobe

    // Registered read address
    logic [2:0] rd_idx_r;

    //=========================================================
    // READY signals (IDLE state and no conflict)
    //=========================================================
    assign AWREADY = (state == IDLE) && !aw_got;
    assign WREADY  = (state == IDLE) && !w_got;
    // Chấp nhận read chỉ khi không có write nào đang pending
    assign ARREADY = (state == IDLE) && !aw_got && !w_got;

    //=========================================================
    // Combinational: will both AW+W be pending after this cycle?
    //=========================================================
    logic aw_now, w_now;
    assign aw_now = AWVALID && AWREADY;
    assign w_now  = WVALID  && WREADY;

    logic aw_pending_next, w_pending_next;
    assign aw_pending_next = aw_got || aw_now;
    assign w_pending_next  = w_got  || w_now;

    logic both_pending;
    assign both_pending = aw_pending_next && w_pending_next;

    //=========================================================
    // Effective write address/data (combinational)
    //    Dùng combinational nếu đến cùng lúc, hoặc registered nếu đã latch trước
    //=========================================================
    logic [2:0]  wr_idx;
    logic [31:0] wr_data;
    logic [3:0]  wr_strb;
    assign wr_idx  = aw_now ? awaddr_4_2 : aw_idx_r;
    assign wr_data = w_now  ? WDATA      : w_data_r;
    assign wr_strb = w_now  ? WSTRB      : w_strb_r;

    //=========================================================
    // Byte-enable mask (Icarus-safe: constant selects trong assign)
    //=========================================================
    logic [31:0] be_mask;
    assign be_mask = {{8{wr_strb[3]}}, {8{wr_strb[2]}}, {8{wr_strb[1]}}, {8{wr_strb[0]}}};

    //=========================================================
    // SFR Register File (8 × 32-bit)
    //=========================================================
    logic [31:0] sfr_reg [0:7];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1)
                sfr_reg[i] <= 32'd0;
        end else if (state == IDLE && both_pending) begin
            // Write with byte enable (read-modify-write)
            sfr_reg[wr_idx] <= (wr_data & be_mask) | (sfr_reg[wr_idx] & ~be_mask);
        end
    end

    //=========================================================
    // FSM + Pending Buffer Register
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            aw_got    <= 1'b0;
            w_got     <= 1'b0;
            aw_idx_r  <= 3'd0;
            w_data_r  <= 32'd0;
            w_strb_r  <= 4'd0;
            rd_idx_r  <= 3'd0;

        end else begin
            case (state)
                IDLE: begin
                    // Latch AW nếu đến
                    if (aw_now) begin
                        aw_idx_r <= awaddr_4_2;
                        aw_got   <= 1'b1;
                    end
                    // Latch W nếu đến
                    if (w_now) begin
                        w_data_r <= WDATA;
                        w_strb_r <= WSTRB;
                        w_got    <= 1'b1;
                    end
                    // Khi cả hai có mặt: ghi đã xảy ra, chuyển sang WR_RESP
                    if (both_pending) begin
                        state  <= WR_RESP;
                        aw_got <= 1'b0;
                        w_got  <= 1'b0;
                    end
                    // Nhận read address: chuyển sang RD_RESP
                    if (ARVALID && ARREADY) begin
                        rd_idx_r <= araddr_4_2;
                        state    <= RD_RESP;
                    end
                end

                WR_RESP: begin
                    if (BREADY) state <= IDLE;
                end

                RD_RESP: begin
                    if (RREADY) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    //=========================================================
    // Read Data (Combinational từ registered read address)
    //=========================================================
    assign RDATA = sfr_reg[rd_idx_r];

    //=========================================================
    // Fixed response signals
    //=========================================================
    assign BVALID = (state == WR_RESP);
    assign BRESP  = 2'b00;
    assign RVALID = (state == RD_RESP);
    assign RRESP  = 2'b00;

    //=========================================================
    // IRQ (bóc tách ngoài để Icarus không lỗi)
    //=========================================================
    logic sfr7_bit0;
    assign sfr7_bit0 = sfr_reg[7][0];
    assign irq = sfr7_bit0;

endmodule
