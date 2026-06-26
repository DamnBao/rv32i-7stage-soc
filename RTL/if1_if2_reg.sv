// IF1/IF2 Pipeline Register — holds PC + branch prediction metadata.
//
// bp_taken/bp_target carry the prediction made at IF1 for the instruction at pc_in.
// They travel with the instruction so EX can compare against actual outcome.
//
// Stall/flush priority (flush wins):
//   flush=1:  zero pc_out, clear bp fields → NOP bubble, no prediction
//   stall=1:  hold all values
//   else:     capture pc_in and bp inputs

module if1_if2_reg (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,
    input  logic        flush,

    input  logic [31:0] pc_in,
    input  logic        bp_taken_in,    // prediction made at IF1 for this instruction
    input  logic [31:0] bp_target_in,   // predicted target address

    output logic [31:0] pc_out,
    output logic        bp_taken_out,
    output logic [31:0] bp_target_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out        <= 32'd0;
            bp_taken_out  <= 1'b0;
            bp_target_out <= 32'd0;
        end else if (flush) begin
            pc_out        <= 32'd0;
            bp_taken_out  <= 1'b0;
            bp_target_out <= 32'd0;
        end else if (!stall) begin
            pc_out        <= pc_in;
            bp_taken_out  <= bp_taken_in;
            bp_target_out <= bp_target_in;
        end
        // stall && !flush: hold unchanged
    end

endmodule
