// Formal verification: AHB interconnect routing correctness
//
// Proves that the address decoder in ahb_interconnect asserts HSEL to exactly
// one slave at a time, and that the correct slave is selected for each address.
//
// Properties proved (5):
//   P_AHB_HSEL_MUTEX : at most one of {HSEL0, HSEL1, HSEL2} is asserted at a time
//   P_AHB_ROUTE_S0   : valid transfer to S0 address range → HSEL0=1, HSEL1/2=0
//   P_AHB_ROUTE_S1   : valid transfer to S1 address range → HSEL1=1, HSEL0/2=0
//   P_AHB_ROUTE_S2   : valid transfer to S2 address range → HSEL2=1, HSEL0/1=0
//   P_AHB_IDLE_NO_SEL: HTRANS=IDLE (no transfer) → all HSEL = 0

`timescale 1ns/1ps
module fv_ahb_route (
    input logic clk,
    input logic rst_n
);

    // ── Symbolic inputs ────────────────────────────────────────────────
    logic [31:0] HADDR;
    logic [2:0]  HSIZE;
    logic [1:0]  HTRANS;
    logic        HWRITE;
    logic [31:0] HWDATA;

    logic        HREADYOUT0; logic [31:0] HRDATA0; logic HRESP0; logic irq0;
    logic        HREADYOUT1; logic [31:0] HRDATA1; logic HRESP1; logic irq1;
    logic        HREADYOUT2; logic [31:0] HRDATA2; logic HRESP2; logic irq2;

    // ── DUT outputs ────────────────────────────────────────────────────
    logic        HREADY; logic [31:0] HRDATA; logic HRESP;
    logic        HSEL0; logic HREADY0_in;
    logic        HSEL1; logic HREADY1_in;
    logic        HSEL2; logic HREADY2_in;
    logic        ahb_irq;

    ahb_interconnect dut (
        .clk_ahb    (clk),
        .rst_ahb_n  (rst_n),
        .HADDR      (HADDR),
        .HSIZE      (HSIZE),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HWDATA     (HWDATA),
        .HREADY     (HREADY),
        .HRDATA     (HRDATA),
        .HRESP      (HRESP),
        .HSEL0      (HSEL0),      .HREADY0_in (HREADY0_in),
        .HREADYOUT0 (HREADYOUT0), .HRDATA0    (HRDATA0),    .HRESP0 (HRESP0), .irq0 (irq0),
        .HSEL1      (HSEL1),      .HREADY1_in (HREADY1_in),
        .HREADYOUT1 (HREADYOUT1), .HRDATA1    (HRDATA1),    .HRESP1 (HRESP1), .irq1 (irq1),
        .HSEL2      (HSEL2),      .HREADY2_in (HREADY2_in),
        .HREADYOUT2 (HREADYOUT2), .HRDATA2    (HRDATA2),    .HRESP2 (HRESP2), .irq2 (irq2),
        .ahb_irq    (ahb_irq)
    );

    initial assume (!rst_n);

    // Address field used for decode
    logic [15:0] haddr_27_12;
    assign haddr_27_12 = HADDR[27:12];

    // Valid AHB transfer (HTRANS[1]=1 means NONSEQ or SEQ)
    logic htrans_valid;
    assign htrans_valid = HTRANS[1];

    // P_AHB_HSEL_MUTEX: at most one slave is selected per cycle
    always @(posedge clk) begin
        if (rst_n) begin
            assert (~(HSEL0 & HSEL1));
            assert (~(HSEL0 & HSEL2));
            assert (~(HSEL1 & HSEL2));
        end
    end

    // P_AHB_ROUTE_S0: valid transfer to slave 0 range → HSEL0=1, others=0
    always @(posedge clk) begin
        if (rst_n && htrans_valid && haddr_27_12 == 16'h0000) begin
            assert (HSEL0 == 1'b1);
            assert (HSEL1 == 1'b0);
            assert (HSEL2 == 1'b0);
        end
    end

    // P_AHB_ROUTE_S1: valid transfer to slave 1 range → HSEL1=1, others=0
    always @(posedge clk) begin
        if (rst_n && htrans_valid && haddr_27_12 == 16'h0001) begin
            assert (HSEL0 == 1'b0);
            assert (HSEL1 == 1'b1);
            assert (HSEL2 == 1'b0);
        end
    end

    // P_AHB_ROUTE_S2: valid transfer to slave 2 range → HSEL2=1, others=0
    always @(posedge clk) begin
        if (rst_n && htrans_valid && haddr_27_12 == 16'h0002) begin
            assert (HSEL0 == 1'b0);
            assert (HSEL1 == 1'b0);
            assert (HSEL2 == 1'b1);
        end
    end

    // P_AHB_IDLE_NO_SEL: IDLE or BUSY transfer (HTRANS[1]=0) → no HSEL asserted
    always @(posedge clk) begin
        if (rst_n && !htrans_valid) begin
            assert (HSEL0 == 1'b0);
            assert (HSEL1 == 1'b0);
            assert (HSEL2 == 1'b0);
        end
    end

endmodule
