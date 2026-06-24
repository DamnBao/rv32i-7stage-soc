module if2_stage (
    input  logic [31:0] pc_in,       // PC từ thanh ghi IF1/IF2
    input  logic [31:0] instr_in,    // Mã lệnh từ IMEM
    
    output logic [31:0] pc_out,      // Chuyển tiếp PC
    output logic [31:0] instr_out    // Chuyển tiếp mã lệnh
);

    // Ở kiến trúc cơ bản, IF2 chỉ đi xuyên qua (pass-through)
    assign pc_out    = pc_in;
    assign instr_out = instr_in;

endmodule
