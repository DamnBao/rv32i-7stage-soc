// IF1/IF2 Pipeline Register — holds the PC of the instruction being fetched.
//
// Stall/flush priority (flush wins):
//   flush=1: zero pc_out → inserts a NOP bubble (discards in-flight fetch)
//   stall=1: hold pc_out → freezes pipeline (load-use, CSR-use, bus stall)
//   else:    capture pc_in

module if1_if2_reg (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,   // Freeze (from hazard_unit)
    input  logic        flush,   // Clear to bubble (branch/jump/trap — takes priority over stall)

    input  logic [31:0] pc_in,
    output logic [31:0] pc_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)     pc_out <= 32'd0;
        else if (flush) pc_out <= 32'd0;
        else if (!stall) pc_out <= pc_in;
        // stall && !flush: hold pc_out unchanged
    end

endmodule
