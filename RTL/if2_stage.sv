// IF2 Stage — instruction fetch second cycle, currently a pass-through.
//
// IMEM has 1-cycle read latency, so the instruction arrives in IF2.
// Stall/flush on the IF1/IF2 register propagates control to this stage.
// A branch predictor or I-cache miss handler would be inserted here.

module if2_stage (
    input  logic [31:0] pc_in,       // PC from IF1/IF2 register
    input  logic [31:0] instr_in,    // Instruction from IMEM (1-cycle latency)

    output logic [31:0] pc_out,      // PC to IF2/ID register
    output logic [31:0] instr_out    // Instruction to IF2/ID register
);

    assign pc_out    = pc_in;
    assign instr_out = instr_in;

endmodule
