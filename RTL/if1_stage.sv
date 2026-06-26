// IF1 Stage — PC register with stall/flush/branch-prediction control.
//
// Priority (highest first):
//   flush=1     → load jump_addr (bp_mismatch correction or trap/MRET)
//   stall=1     → hold PC
//   bp_redirect → load bp_target (speculative branch predictor redirect)
//   else        → PC + 4
//
// bp_redirect is suppressed by both flush and stall via priority ordering.

module if1_stage #(
    parameter PC_RESET_VAL = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,       // Freeze PC (bus_stall or load/CSR-use hazard)
    input  logic        flush,       // Redirect PC (bp_mismatch, trap, MRET)
    input  logic [31:0] jump_addr,   // Redirect target (bp_correct_pc or zicsr_pc, muxed in soc_top)

    input  logic        bp_redirect, // Branch predictor: 1 = speculative redirect to bp_target
    input  logic [31:0] bp_target,   // Branch predictor: predicted target address

    output logic [31:0] pc_out       // Current PC → IMEM address + IF1/IF2 register
);

    logic [31:0] pc_reg;
    logic [31:0] next_pc;

    always_comb begin
        if (flush)           next_pc = jump_addr;      // highest priority: correction / trap
        else if (stall)      next_pc = pc_reg;          // freeze
        else if (bp_redirect) next_pc = bp_target;     // speculative redirect
        else                 next_pc = pc_reg + 32'd4; // sequential fetch
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_reg <= PC_RESET_VAL;
        else        pc_reg <= next_pc;
    end

    assign pc_out = pc_reg;

endmodule
