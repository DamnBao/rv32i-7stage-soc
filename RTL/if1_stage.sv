// IF1 Stage — PC register with stall/flush control.
//
// flush has priority over stall. On flush, PC loads jump_addr (the redirect
// target from soc_top mux: zicsr_pc on trap/MRET, ex_jump_addr on branch/jump).
// On stall without flush, PC holds its current value.
// Normal operation: PC increments by 4 each cycle.

module if1_stage #(
    parameter PC_RESET_VAL = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,       // Freeze PC (from hazard_unit: bus_stall or load/CSR-use)
    input  logic        flush,       // Redirect PC (branch, jump, trap, MRET)
    input  logic [31:0] jump_addr,   // Redirect target (zicsr_pc or ex_jump_addr, muxed in soc_top)

    output logic [31:0] pc_out       // Current PC → IMEM address + IF1/IF2 register
);

    logic [31:0] pc_reg;
    logic [31:0] next_pc;

    //=========================================================
    // Mạch tổ hợp (Combinational Logic) tính toán PC tiếp theo
    //=========================================================
    always_comb begin
        if (flush)      next_pc = jump_addr;      // Redirect: highest priority
        else if (stall) next_pc = pc_reg;         // Freeze
        else            next_pc = pc_reg + 32'd4; // Normal sequential fetch
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_reg <= PC_RESET_VAL;
        else        pc_reg <= next_pc;
    end

    assign pc_out = pc_reg;

endmodule
