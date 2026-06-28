// Formal verification: AXI interconnect routing correctness
//
// Proves that the address decoder in axi_interconnect correctly routes AW and AR
// channels to exactly one slave, and that slave VALID signals are mutually exclusive.
//
// Properties proved (6):
//   P_AW_MUTEX    : at most one of {S0_AWVALID, S1_AWVALID, S2_AWVALID} is 1
//   P_AR_MUTEX    : at most one of {S0_ARVALID, S1_ARVALID, S2_ARVALID} is 1
//   P_AW_ROUTE_S0 : M_AWVALID && addr in S0 range → S0_AWVALID=1, S1/S2=0
//   P_AW_ROUTE_S1 : M_AWVALID && addr in S1 range → S1_AWVALID=1, S0/S2=0
//   P_AR_ROUTE_S0 : M_ARVALID && addr in S0 range → S0_ARVALID=1, S1/S2=0
//   P_AR_ROUTE_S2 : M_ARVALID && addr in S2 range → S2_ARVALID=1, S0/S1=0

`timescale 1ns/1ps
module fv_axi_route (
    input logic clk,
    input logic rst_n
);

    // ── Symbolic master-side inputs ──────────────────────────────────────
    logic [31:0] M_AWADDR; logic [2:0] M_AWPROT; logic M_AWVALID;
    logic [31:0] M_WDATA;  logic [3:0] M_WSTRB;  logic M_WVALID;
    logic        M_BREADY;
    logic [31:0] M_ARADDR; logic [2:0] M_ARPROT; logic M_ARVALID;
    logic        M_RREADY;

    // ── Symbolic slave-side inputs ────────────────────────────────────────
    logic S0_AWREADY, S0_WREADY; logic [1:0] S0_BRESP; logic S0_BVALID;
    logic S0_ARREADY; logic [31:0] S0_RDATA; logic [1:0] S0_RRESP; logic S0_RVALID;
    logic irq0;

    logic S1_AWREADY, S1_WREADY; logic [1:0] S1_BRESP; logic S1_BVALID;
    logic S1_ARREADY; logic [31:0] S1_RDATA; logic [1:0] S1_RRESP; logic S1_RVALID;
    logic irq1;

    logic S2_AWREADY, S2_WREADY; logic [1:0] S2_BRESP; logic S2_BVALID;
    logic S2_ARREADY; logic [31:0] S2_RDATA; logic [1:0] S2_RRESP; logic S2_RVALID;
    logic irq2;

    // ── DUT outputs (slave-facing) ────────────────────────────────────────
    logic M_AWREADY, M_WREADY; logic [1:0] M_BRESP; logic M_BVALID;
    logic M_ARREADY; logic [31:0] M_RDATA; logic [1:0] M_RRESP; logic M_RVALID;

    logic [31:0] S0_AWADDR; logic [2:0] S0_AWPROT; logic S0_AWVALID;
    logic [31:0] S0_WDATA_;  logic [3:0] S0_WSTRB_;  logic S0_WVALID;
    logic S0_BREADY;
    logic [31:0] S0_ARADDR; logic [2:0] S0_ARPROT; logic S0_ARVALID; logic S0_RREADY;

    logic [31:0] S1_AWADDR; logic [2:0] S1_AWPROT; logic S1_AWVALID;
    logic [31:0] S1_WDATA_;  logic [3:0] S1_WSTRB_;  logic S1_WVALID;
    logic S1_BREADY;
    logic [31:0] S1_ARADDR; logic [2:0] S1_ARPROT; logic S1_ARVALID; logic S1_RREADY;

    logic [31:0] S2_AWADDR; logic [2:0] S2_AWPROT; logic S2_AWVALID;
    logic [31:0] S2_WDATA_;  logic [3:0] S2_WSTRB_;  logic S2_WVALID;
    logic S2_BREADY;
    logic [31:0] S2_ARADDR; logic [2:0] S2_ARPROT; logic S2_ARVALID; logic S2_RREADY;

    logic axi_irq;

    axi_interconnect dut (
        .clk        (clk),       .rst_n      (rst_n),
        .M_AWADDR   (M_AWADDR),  .M_AWPROT   (M_AWPROT),  .M_AWVALID  (M_AWVALID),  .M_AWREADY  (M_AWREADY),
        .M_WDATA    (M_WDATA),   .M_WSTRB    (M_WSTRB),   .M_WVALID   (M_WVALID),   .M_WREADY   (M_WREADY),
        .M_BRESP    (M_BRESP),   .M_BVALID   (M_BVALID),  .M_BREADY   (M_BREADY),
        .M_ARADDR   (M_ARADDR),  .M_ARPROT   (M_ARPROT),  .M_ARVALID  (M_ARVALID),  .M_ARREADY  (M_ARREADY),
        .M_RDATA    (M_RDATA),   .M_RRESP    (M_RRESP),   .M_RVALID   (M_RVALID),   .M_RREADY   (M_RREADY),
        .S0_AWADDR  (S0_AWADDR), .S0_AWPROT  (S0_AWPROT), .S0_AWVALID (S0_AWVALID), .S0_AWREADY (S0_AWREADY),
        .S0_WDATA   (S0_WDATA_), .S0_WSTRB   (S0_WSTRB_), .S0_WVALID  (S0_WVALID),  .S0_WREADY  (S0_WREADY),
        .S0_BRESP   (S0_BRESP),  .S0_BVALID  (S0_BVALID), .S0_BREADY  (S0_BREADY),
        .S0_ARADDR  (S0_ARADDR), .S0_ARPROT  (S0_ARPROT), .S0_ARVALID (S0_ARVALID), .S0_ARREADY (S0_ARREADY),
        .S0_RDATA   (S0_RDATA),  .S0_RRESP   (S0_RRESP),  .S0_RVALID  (S0_RVALID),  .S0_RREADY  (S0_RREADY),
        .irq0       (irq0),
        .S1_AWADDR  (S1_AWADDR), .S1_AWPROT  (S1_AWPROT), .S1_AWVALID (S1_AWVALID), .S1_AWREADY (S1_AWREADY),
        .S1_WDATA   (S1_WDATA_), .S1_WSTRB   (S1_WSTRB_), .S1_WVALID  (S1_WVALID),  .S1_WREADY  (S1_WREADY),
        .S1_BRESP   (S1_BRESP),  .S1_BVALID  (S1_BVALID), .S1_BREADY  (S1_BREADY),
        .S1_ARADDR  (S1_ARADDR), .S1_ARPROT  (S1_ARPROT), .S1_ARVALID (S1_ARVALID), .S1_ARREADY (S1_ARREADY),
        .S1_RDATA   (S1_RDATA),  .S1_RRESP   (S1_RRESP),  .S1_RVALID  (S1_RVALID),  .S1_RREADY  (S1_RREADY),
        .irq1       (irq1),
        .S2_AWADDR  (S2_AWADDR), .S2_AWPROT  (S2_AWPROT), .S2_AWVALID (S2_AWVALID), .S2_AWREADY (S2_AWREADY),
        .S2_WDATA   (S2_WDATA_), .S2_WSTRB   (S2_WSTRB_), .S2_WVALID  (S2_WVALID),  .S2_WREADY  (S2_WREADY),
        .S2_BRESP   (S2_BRESP),  .S2_BVALID  (S2_BVALID), .S2_BREADY  (S2_BREADY),
        .S2_ARADDR  (S2_ARADDR), .S2_ARPROT  (S2_ARPROT), .S2_ARVALID (S2_ARVALID), .S2_ARREADY (S2_ARREADY),
        .S2_RDATA   (S2_RDATA),  .S2_RRESP   (S2_RRESP),  .S2_RVALID  (S2_RVALID),  .S2_RREADY  (S2_RREADY),
        .irq2       (irq2),
        .axi_irq    (axi_irq)
    );

    initial assume (!rst_n);

    // Address range helpers (addr[27:12] decode, matching axi_interconnect.sv)
    logic [15:0] awaddr_27_12, araddr_27_12;
    assign awaddr_27_12 = M_AWADDR[27:12];
    assign araddr_27_12 = M_ARADDR[27:12];

    // P_AW_MUTEX: at most one slave receives AWVALID at a time
    always @(posedge clk) begin
        if (rst_n) begin
            assert (~(S0_AWVALID & S1_AWVALID));
            assert (~(S0_AWVALID & S2_AWVALID));
            assert (~(S1_AWVALID & S2_AWVALID));
        end
    end

    // P_AR_MUTEX: at most one slave receives ARVALID at a time
    always @(posedge clk) begin
        if (rst_n) begin
            assert (~(S0_ARVALID & S1_ARVALID));
            assert (~(S0_ARVALID & S2_ARVALID));
            assert (~(S1_ARVALID & S2_ARVALID));
        end
    end

    // P_AW_ROUTE_S0: write to slave 0 address range goes to S0 only
    always @(posedge clk) begin
        if (rst_n && M_AWVALID && awaddr_27_12 == 16'h0000) begin
            assert (S0_AWVALID == 1'b1);
            assert (S1_AWVALID == 1'b0);
            assert (S2_AWVALID == 1'b0);
        end
    end

    // P_AW_ROUTE_S1: write to slave 1 address range goes to S1 only
    always @(posedge clk) begin
        if (rst_n && M_AWVALID && awaddr_27_12 == 16'h0001) begin
            assert (S0_AWVALID == 1'b0);
            assert (S1_AWVALID == 1'b1);
            assert (S2_AWVALID == 1'b0);
        end
    end

    // P_AR_ROUTE_S0: read from slave 0 address range goes to S0 only
    always @(posedge clk) begin
        if (rst_n && M_ARVALID && araddr_27_12 == 16'h0000) begin
            assert (S0_ARVALID == 1'b1);
            assert (S1_ARVALID == 1'b0);
            assert (S2_ARVALID == 1'b0);
        end
    end

    // P_AR_ROUTE_S2: read from slave 2 address range goes to S2 only
    always @(posedge clk) begin
        if (rst_n && M_ARVALID && araddr_27_12 == 16'h0002) begin
            assert (S0_ARVALID == 1'b0);
            assert (S1_ARVALID == 1'b0);
            assert (S2_ARVALID == 1'b1);
        end
    end

endmodule
