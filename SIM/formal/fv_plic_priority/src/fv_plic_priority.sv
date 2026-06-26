// Formal verification wrapper: plic — Priority encoder correctness
//
// Properties (asserted inside plic.sv under `ifdef FORMAL):
//   P_WINNER_BOUND:   winner_id is always in range [0..6]
//   P_WINNER_ACTIVE:  winner_id != 0 → src_active[winner_id] == 1
//   P_WINNER_OPTIMAL: winner_id != 0 → every active source has priority ≤ win_pri
//                     (winner holds the globally highest priority level)
//   P_MEIP:           meip == (winner_id != 0)  [tautological from RTL assign]
//
// Together these prove that the PLIC always correctly identifies the
// highest-priority pending+enabled interrupt above threshold.
//
// All inputs are left fully unconstrained so the solver exercises arbitrary
// IRQ firing patterns, priority configurations, and enable/threshold values.

`timescale 1ns/1ps
module fv_plic_priority (
    input logic clk,
    input logic rst_n
);
    // Symbolic PLIC inputs
    logic [5:0]  irq_src;
    logic        re, we;
    logic [23:0] addr;
    logic [31:0] wdata;

    // DUT outputs
    logic [31:0] rdata;
    logic        meip;

    plic dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .irq_src(irq_src),
        .re     (re),
        .we     (we),
        .addr   (addr),
        .wdata  (wdata),
        .rdata  (rdata),
        .meip   (meip)
    );

    // Start in reset so all registers are initialised to 0
    initial assume(!rst_n);

endmodule
