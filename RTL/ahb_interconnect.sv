// AHB-Lite Interconnect (500MHz domain)
//
// 1 Master (ahb_interface) → 3 Slaves (SFR0, SFR1, SFR2)
//
// Address decode (dùng addr[27:12], bóc tách ngoài always):
//   addr[27:12] == 16'h0000 → Slave 0 (base 0x3000_0000)
//   addr[27:12] == 16'h0001 → Slave 1 (base 0x3000_1000)
//   addr[27:12] == 16'h0002 → Slave 2 (base 0x3000_2000)
//   Không khớp → Default slave (HRDATA=0, HREADYOUT=1, HRESP=0)
//
// HREADYOUT mux: dựa trên registered slave select (data phase).
// Tất cả slave SFR simple → HREADYOUT=1 always → HREADY=1 always.
//
// IRQ aggregation: OR của tất cả slave IRQ (trước khi cross sang CPU domain).

module ahb_interconnect (
    input  logic        clk_ahb,
    input  logic        rst_ahb_n,

    //----------------- TỪ AHB MASTER (ahb_interface) -----------------
    input  logic [31:0] HADDR,
    input  logic [2:0]  HSIZE,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,
    output logic        HREADY,     // = muxed HREADYOUT về master
    output logic [31:0] HRDATA,     // = muxed HRDATA về master
    output logic        HRESP,      // = muxed HRESP về master

    //----------------- SLAVE 0 -----------------
    output logic        HSEL0,
    output logic        HREADY0_in, // HREADY đến slave 0
    input  logic        HREADYOUT0,
    input  logic [31:0] HRDATA0,
    input  logic        HRESP0,
    input  logic        irq0,

    //----------------- SLAVE 1 -----------------
    output logic        HSEL1,
    output logic        HREADY1_in,
    input  logic        HREADYOUT1,
    input  logic [31:0] HRDATA1,
    input  logic        HRESP1,
    input  logic        irq1,

    //----------------- SLAVE 2 -----------------
    output logic        HSEL2,
    output logic        HREADY2_in,
    input  logic        HREADYOUT2,
    input  logic [31:0] HRDATA2,
    input  logic        HRESP2,
    input  logic        irq2,

    //----------------- IRQ AGGREGATION → CPU domain -----------------
    output logic        ahb_irq     // OR của tất cả slave IRQ (500MHz domain)
);

    //=========================================================
    // 1. Address Decode (Combinational)
    //    Bóc tách addr[27:12] ngoài always
    //=========================================================
    logic [15:0] haddr_27_12;
    assign haddr_27_12 = HADDR[27:12];

    // Valid AHB transfer
    logic htrans_valid;
    assign htrans_valid = HTRANS[1];   // NONSEQ (2'b10) or SEQ (2'b11)

    logic [1:0] sel_now;   // Combinational slave select based on current HADDR
    logic       sel_valid; // 1 nếu một slave được chọn

    always_comb begin
        sel_now   = 2'd3;  // Default: no slave
        sel_valid = 1'b0;
        if (htrans_valid) begin
            if      (haddr_27_12 == 16'h0000) begin sel_now = 2'd0; sel_valid = 1'b1; end
            else if (haddr_27_12 == 16'h0001) begin sel_now = 2'd1; sel_valid = 1'b1; end
            else if (haddr_27_12 == 16'h0002) begin sel_now = 2'd2; sel_valid = 1'b1; end
        end
    end

    // HSEL: combinational — slave thấy HSEL trong address phase
    assign HSEL0 = htrans_valid && (sel_now == 2'd0);
    assign HSEL1 = htrans_valid && (sel_now == 2'd1);
    assign HSEL2 = htrans_valid && (sel_now == 2'd2);

    //=========================================================
    // 2. Registered Slave Select (để mux HRDATA trong data phase)
    //    Cập nhật khi có address phase mới (HREADY=1)
    //=========================================================
    logic [1:0] sel_reg;

    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n)
            sel_reg <= 2'd3;
        else if (HREADY)           // Address phase kết thúc → latch slave select
            sel_reg <= sel_now;
    end

    //=========================================================
    // 3. HREADY, HRDATA, HRESP Mux (data phase dùng sel_reg)
    //=========================================================
    // HREADYOUT mux về master
    always_comb begin
        case (sel_reg)
            2'd0:    HREADY = HREADYOUT0;
            2'd1:    HREADY = HREADYOUT1;
            2'd2:    HREADY = HREADYOUT2;
            default: HREADY = 1'b1;   // Default slave: luôn sẵn sàng
        endcase
    end

    // HRDATA mux
    always_comb begin
        case (sel_reg)
            2'd0:    HRDATA = HRDATA0;
            2'd1:    HRDATA = HRDATA1;
            2'd2:    HRDATA = HRDATA2;
            default: HRDATA = 32'd0;
        endcase
    end

    // HRESP mux
    always_comb begin
        case (sel_reg)
            2'd0:    HRESP = HRESP0;
            2'd1:    HRESP = HRESP1;
            2'd2:    HRESP = HRESP2;
            default: HRESP = 1'b0;
        endcase
    end

    //=========================================================
    // 4. HREADY đến từng slave (HREADY-in = global HREADY)
    //    Vì tất cả slave simple (HREADYOUT=1), HREADY=1 luôn.
    //=========================================================
    assign HREADY0_in = HREADY;
    assign HREADY1_in = HREADY;
    assign HREADY2_in = HREADY;

    //=========================================================
    // 5. IRQ Aggregation
    //=========================================================
    assign ahb_irq = irq0 | irq1 | irq2;

endmodule
