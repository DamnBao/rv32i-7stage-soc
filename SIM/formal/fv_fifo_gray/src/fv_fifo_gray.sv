// Formal verification wrapper: async_fifo_depth2 — Gray-code single-bit transition
//
// Property (asserted inside async_fifo.sv under `ifdef FORMAL):
//   P_GRAY: consecutive values of wr_ptr_gray differ by at most 1 bit.
//   i.e.  XOR of successive values never equals 2'b11 (two-bit flip).
//
// This is the key CDC invariant: a 2-FF synchroniser is only safe if the
// sampled signal changes by at most 1 bit per source clock.
//
// Simplification for formal: wr_clk == rd_clk (single-clock model).
// The gray-code property lives entirely within the write domain, so
// collapsing the clocks does not affect correctness of the proof.

`timescale 1ns/1ps
module fv_fifo_gray (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic [7:0] wr_data   // data width reduced to 8 for efficiency
);
    logic [7:0] rd_data;
    logic       rd_empty;

    // Tie both clock domains to a single symbolic clock
    async_fifo_depth2 #(.DATA_WIDTH(8)) dut (
        .wr_clk  (clk),
        .wr_rst_n(rst_n),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .rd_clk  (clk),
        .rd_rst_n(rst_n),
        .rd_en   (rd_en),
        .rd_empty(rd_empty),
        .rd_data (rd_data)
    );

    // Start in synchronous reset so pointers begin at 0
    initial assume(!rst_n);

endmodule
