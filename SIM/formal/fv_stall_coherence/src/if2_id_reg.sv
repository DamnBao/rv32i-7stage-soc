// IF2/ID Pipeline Register — carries PC, instruction, and branch prediction metadata.
//
// flush: clears to NOP, zeroes PC, clears bp fields — inserts a bubble with no prediction.
// stall: holds all register values.
// flush wins if both assert simultaneously.

module if2_id_reg (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,
    input  logic        flush,

    input  logic [31:0] pc_in,
    input  logic [31:0] instr_in,
    input  logic        bp_taken_in,
    input  logic [31:0] bp_target_in,

    output logic [31:0] pc_out,
    output logic [31:0] instr_out,
    output logic        bp_taken_out,
    output logic [31:0] bp_target_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out        <= 32'd0;
            instr_out     <= 32'h0000_0013;
            bp_taken_out  <= 1'b0;
            bp_target_out <= 32'd0;
        end else if (flush) begin
            pc_out        <= 32'd0;
            instr_out     <= 32'h0000_0013;
            bp_taken_out  <= 1'b0;
            bp_target_out <= 32'd0;
        end else if (!stall) begin
            pc_out        <= pc_in;
            instr_out     <= instr_in;
            bp_taken_out  <= bp_taken_in;
            bp_target_out <= bp_target_in;
        end
    end

endmodule
