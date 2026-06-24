module alu (
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [3:0]  alu_op,

    output logic [31:0] alu_result
);

    // Định nghĩa các phép toán ALU (phải khớp với id_decoder)
    localparam ALU_ADD   = 4'd0;
    localparam ALU_SUB   = 4'd1;
    localparam ALU_SLL   = 4'd2;
    localparam ALU_SLT   = 4'd3;
    localparam ALU_SLTU  = 4'd4;
    localparam ALU_XOR   = 4'd5;
    localparam ALU_SRL   = 4'd6;
    localparam ALU_SRA   = 4'd7;
    localparam ALU_OR    = 4'd8;
    localparam ALU_AND   = 4'd9;
    localparam ALU_PASSB = 4'd10;

    // Bóc tách 5 bit thấp của toán hạng B để làm lượng dịch (shift amount)
    // Thực hiện bên ngoài always_comb để tránh lỗi cảnh báo của trình biên dịch
    logic [4:0] shift_amt;
    assign shift_amt = operand_b[4:0];

    always_comb begin
        // Khởi tạo giá trị mặc định để tránh tạo chốt (prevent latches)
        alu_result = 32'd0;

        case (alu_op)
            ALU_ADD:   alu_result = operand_a + operand_b;
            
            ALU_SUB:   alu_result = operand_a - operand_b;
            
            ALU_SLL:   alu_result = operand_a << shift_amt;
            
            // So sánh có dấu: Ép kiểu sang $signed để SystemVerilog tự xử lý bit dấu
            ALU_SLT:   alu_result = ($signed(operand_a) < $signed(operand_b))? 32'd1 : 32'd0;
            
            // So sánh không dấu
            ALU_SLTU:  alu_result = (operand_a < operand_b)? 32'd1 : 32'd0;
            
            ALU_XOR:   alu_result = operand_a ^ operand_b;
            
            ALU_SRL:   alu_result = operand_a >> shift_amt;
            
            // Dịch phải có dấu: Giữ nguyên bit dấu (MSB)
            // Ép kiểu $signed cho toán hạng, sử dụng toán tử >>>, sau đó ép lại $unsigned cho kết quả
            ALU_SRA:   alu_result = $unsigned($signed(operand_a) >>> shift_amt);
            
            ALU_OR:    alu_result = operand_a | operand_b;
            
            ALU_AND:   alu_result = operand_a & operand_b;
            
            // Bỏ qua toán hạng A, chỉ cho toán hạng B đi qua (Dành cho lệnh LUI)
            ALU_PASSB: alu_result = operand_b;
            
            default:   alu_result = 32'd0;
        endcase
    end

endmodule
