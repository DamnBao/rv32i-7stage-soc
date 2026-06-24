module branch_comp (
    input  logic [31:0] rs1_data,   // Đã qua Forwarding MUX
    input  logic [31:0] rs2_data,   // Đã qua Forwarding MUX
    input  logic [2:0]  funct3,
    input  logic        branch,     // 1 nếu là lệnh B-type

    output logic        branch_taken
);

    // Thực hiện so sánh bên ngoài always_comb để tránh lỗi constant-select trên Icarus
    logic        eq;
    logic        slt;   // Signed less than
    logic        ult;   // Unsigned less than

    assign eq  =  (rs1_data == rs2_data);
    assign slt =  ($signed(rs1_data) < $signed(rs2_data));
    assign ult =  (rs1_data < rs2_data);

    always_comb begin
        branch_taken = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: branch_taken =  eq;   // BEQ
                3'b001: branch_taken = ~eq;   // BNE
                3'b100: branch_taken =  slt;  // BLT
                3'b101: branch_taken = ~slt;  // BGE
                3'b110: branch_taken =  ult;  // BLTU
                3'b111: branch_taken = ~ult;  // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

endmodule
