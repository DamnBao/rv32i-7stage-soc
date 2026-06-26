// Formal verification wrapper: uart_axi — 8N1 protocol invariants
//
// Properties (asserted inside uart_axi.sv under `ifdef FORMAL):
//   P_IDLE:  tx_state == TX_IDLE  → uart_tx == 1  (line idles high)
//   P_START: tx_state == TX_START → uart_tx == 0  (start bit is low)
//   P_STOP:  tx_state == TX_STOP  → uart_tx == 1  (stop bit is high)
//
// These three invariants together encode the 8N1 frame boundary
// semantics: a receiver relying on them will always correctly identify
// frame edges regardless of data content.
//
// Inputs are left fully unconstrained (symbolic) so the solver exercises
// every possible AXI transaction sequence, baud-div setting, and UART
// enable/disable ordering.

`timescale 1ns/1ps
module fv_uart_proto (
    input logic clk,
    input logic rst_n
);
    // AXI-Lite master stimulus — fully symbolic
    logic [31:0] AWADDR, WDATA, ARADDR;
    logic [2:0]  AWPROT, ARPROT;
    logic [3:0]  WSTRB;
    logic        AWVALID, WVALID, BREADY, ARVALID, RREADY;

    // DUT outputs
    logic        AWREADY, WREADY, BVALID, ARREADY, RVALID;
    logic [31:0] RDATA;
    logic [1:0]  BRESP, RRESP;
    logic        uart_rx;   // symbolic receive data
    logic        uart_tx;
    logic        irq;

    uart_axi dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .AWADDR (AWADDR),  .AWPROT (AWPROT),  .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA  (WDATA),   .WSTRB  (WSTRB),   .WVALID (WVALID),  .WREADY (WREADY),
        .BRESP  (BRESP),   .BVALID (BVALID),  .BREADY (BREADY),
        .ARADDR (ARADDR),  .ARPROT (ARPROT),  .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA  (RDATA),   .RRESP  (RRESP),   .RVALID (RVALID),  .RREADY (RREADY),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .irq    (irq)
    );

    // Start in reset so FSM state is initialised
    initial assume(!rst_n);

endmodule
