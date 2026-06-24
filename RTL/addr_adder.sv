module addr_adder (
    input  logic [31:0] pc,
    input  logic [31:0] rs1_data,  // Đã qua Forwarding MUX
    input  logic [31:0] imm,       // imm đúng loại từ id_decoder (imm_b/imm_j/imm_i/imm_s)
    input  logic        branch,
    input  logic        jump,
    input  logic        jump_reg,  // 1: JALR (dùng rs1 làm base và mask bit 0)

    output logic [31:0] addr_out   // Địa chỉ đích cho jump/branch hoặc địa chỉ bộ nhớ cho Load/Store
);

    // Branch và JAL dùng PC làm base, còn lại (JALR, Load, Store) dùng rs1
    logic        use_pc;
    logic [31:0] base;
    logic [31:0] sum;

    assign use_pc   = branch | (jump & ~jump_reg);
    assign base     = use_pc ? pc : rs1_data;
    assign sum      = base + imm;

    // JALR yêu cầu xóa bit 0 của địa chỉ đích theo chuẩn RISC-V
    assign addr_out = jump_reg ? (sum & 32'hFFFF_FFFE) : sum;

endmodule
