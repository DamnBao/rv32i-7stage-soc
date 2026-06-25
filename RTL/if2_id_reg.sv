// IF2/ID Pipeline Register — carries PC and instruction from IF2 to ID.
//
// flush: clears to NOP (ADDI x0,x0,0) and zeroes PC — inserts a bubble.
// stall: holds current register values (freeze entire fetch pipeline).
// flush wins if both assert simultaneously.

module if2_id_reg (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,   // Freeze (from hazard_unit)
    input  logic        flush,   // Clear to NOP bubble (branch/jump/trap)

    // Data in (Từ tầng IF2)
    input  logic [31:0] pc_in,
    input  logic [31:0] instr_in,

    // Data out (Đưa sang tầng ID)
    output logic [31:0] pc_out,
    output logic [31:0] instr_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out    <= 32'd0;
            instr_out <= 32'h0000_0013; // Khởi tạo bằng lệnh NOP
        end else if (flush) begin
            // Xóa lệnh đang nạp khi bị bẻ hướng, chèn bong bóng (NOP)
            pc_out    <= 32'd0;
            instr_out <= 32'h0000_0013;
        end else if (!stall) begin
            // Cập nhật đường ống khi không bị stall
            pc_out    <= pc_in;
            instr_out <= instr_in;
        end
        // Nếu stall = 1 và flush = 0: Thanh ghi giữ nguyên giá trị cũ để chờ
    end

endmodule
