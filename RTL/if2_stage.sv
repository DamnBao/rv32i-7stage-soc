// IF2 Stage — instruction fetch second cycle, pass-through including prediction metadata.
//
// IMEM has 1-cycle read latency, so the instruction arrives in IF2.
// Branch prediction metadata (bp_taken, bp_target) flows through unchanged
// so EX can compare predicted vs actual outcome.

module if2_stage (
    input  logic [31:0] pc_in,
    input  logic [31:0] instr_in,
    input  logic        bp_taken_in,
    input  logic [31:0] bp_target_in,

    output logic [31:0] pc_out,
    output logic [31:0] instr_out,
    output logic        bp_taken_out,
    output logic [31:0] bp_target_out
);

    assign pc_out        = pc_in;
    assign instr_out     = instr_in;
    assign bp_taken_out  = bp_taken_in;
    assign bp_target_out = bp_target_in;

endmodule
