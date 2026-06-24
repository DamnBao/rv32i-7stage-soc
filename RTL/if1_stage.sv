module if1_stage #(
    parameter PC_RESET_VAL = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // Các tín hiệu điều khiển từ Hazard Unit và Zicsr
    input  logic        stall,
    input  logic        flush,
    input  logic [31:0] jump_addr, // Địa chỉ nhảy (do Branch/JAL hoặc Ngắt/Exception)

    // Đầu ra PC: Nối trực tiếp vào cổng Address của IMEM và đưa vào IF1_IF2_reg
    output logic [31:0] pc_out
);

    logic [31:0] pc_reg;
    logic [31:0] next_pc;

    //=========================================================
    // Mạch tổ hợp (Combinational Logic) tính toán PC tiếp theo
    //=========================================================
    always_comb begin
        if (flush) begin
            // Ưu tiên cao nhất: Bẻ hướng luồng lệnh
            next_pc = jump_addr;
        end else if (stall) begin
            // Đóng băng đường ống: Giữ nguyên địa chỉ PC hiện tại
            next_pc = pc_reg;
        end else begin
            // Hoạt động bình thường: Tăng PC tuần tự lên 4 byte
            next_pc = pc_reg + 32'd4;
        end
    end

    //=========================================================
    // Thanh ghi cập nhật PC (Sequential Logic)
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= PC_RESET_VAL;
        end else begin
            pc_reg <= next_pc;
        end
    end

    // Xuất giá trị PC ra ngoài
    assign pc_out = pc_reg;

endmodule
