module if1_if2_reg (
    input  logic        clk,
    input  logic        rst_n,

    // Tín hiệu điều khiển
    input  logic        stall,
    input  logic        flush,

    // Data in/out
    input  logic [31:0] pc_in,
    output logic [31:0] pc_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'd0;
        end else if (flush) begin
            // Khi nhảy PC, lệnh đang nạp bị sai luồng -> Xóa bằng cách chèn bong bóng (bubble)
            pc_out <= 32'd0; 
        end else if (!stall) begin
            // Khi không bị đóng băng -> Cập nhật PC xuống tầng dưới
            pc_out <= pc_in;
        end
        // Lưu ý: Nếu stall = 1 và flush = 0, mạch tự động không cập nhật (giữ nguyên pc_out)
    end

endmodule
