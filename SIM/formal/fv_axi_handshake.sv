// Formal verification wrapper: axi_interface — AXI4-Lite VALID-stability
//
// Properties (checked here in wrapper, signals are DUT outputs):
//   P_AXI_AR: once ARVALID asserted, must not deassert until ARREADY
//   P_AXI_AW: once AWVALID asserted, must not deassert until AWREADY
//   P_AXI_W:  once WVALID  asserted, must not deassert until WREADY
//
// AXI4 spec §A3.2.1 rule: "Once VALID is asserted it must remain asserted
// until the handshake occurs."  Violations cause deadlock (master de-asserts
// VALID while slave is still waiting → slave never sees it).
//
// All AXI slave responses and CPU request inputs are left fully symbolic so
// the solver explores every possible handshake ordering and request sequence.

`timescale 1ns/1ps
module fv_axi_handshake (
    input logic clk,
    input logic rst_n
);
    // CPU-side inputs — symbolic
    logic        axi_req_valid;
    logic [31:0] axi_req_addr;
    logic        axi_req_we;
    logic [31:0] axi_req_wdata;
    logic [1:0]  axi_req_size;

    // AXI slave responses — symbolic
    logic        AWREADY, WREADY, BVALID;
    logic [1:0]  BRESP;
    logic        ARREADY, RVALID;
    logic [31:0] RDATA;
    logic [1:0]  RRESP;

    // DUT outputs
    logic        axi_resp_valid, axi_resp_err;
    logic [31:0] axi_resp_rdata;
    logic [31:0] AWADDR, WDATA, ARADDR;
    logic [2:0]  AWPROT, ARPROT;
    logic [3:0]  WSTRB;
    logic        AWVALID, WVALID, ARVALID;
    logic        BREADY, RREADY;

    axi_interface dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .axi_req_valid (axi_req_valid),
        .axi_req_addr  (axi_req_addr),
        .axi_req_we    (axi_req_we),
        .axi_req_wdata (axi_req_wdata),
        .axi_req_size  (axi_req_size),
        .axi_resp_valid(axi_resp_valid),
        .axi_resp_rdata(axi_resp_rdata),
        .axi_resp_err  (axi_resp_err),
        .AWADDR(AWADDR), .AWPROT(AWPROT), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA (WDATA),  .WSTRB (WSTRB),  .WVALID (WVALID),  .WREADY (WREADY),
        .BRESP (BRESP),  .BVALID(BVALID), .BREADY (BREADY),
        .ARADDR(ARADDR), .ARPROT(ARPROT), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA (RDATA),  .RRESP (RRESP),  .RVALID (RVALID),  .RREADY (RREADY)
    );

    // Start in reset
    initial assume(!rst_n);

    // ── P_AXI_AR: read-address VALID stability ───────────────────────
    // If ARVALID was high last cycle and ARREADY was NOT (no handshake),
    // ARVALID must still be high this cycle.
    always @(posedge clk) begin
        if (rst_n) begin
            if ($past(ARVALID) && !$past(ARREADY))
                assert(ARVALID);
        end
    end

    // ── P_AXI_AW: write-address VALID stability ──────────────────────
    always @(posedge clk) begin
        if (rst_n) begin
            if ($past(AWVALID) && !$past(AWREADY))
                assert(AWVALID);
        end
    end

    // ── P_AXI_W: write-data VALID stability ──────────────────────────
    always @(posedge clk) begin
        if (rst_n) begin
            if ($past(WVALID) && !$past(WREADY))
                assert(WVALID);
        end
    end

endmodule
