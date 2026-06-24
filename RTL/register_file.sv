module register_file (
    input  logic        clk,
    input  logic        rst_n,

    // Port Đọc 1 (phục vụ rs1 tại tầng ID)
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,

    // Port Đọc 2 (phục vụ rs2 tại tầng ID)
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,

    // Port Ghi (phục vụ rd từ tầng WB)
    input  logic        we,        // Write Enable (từ tín hiệu điều khiển của lệnh)
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data
);

    // Mảng 32 thanh ghi 32-bit
    logic [31:0] registers [0:31];
    integer i;

    // Gap-4 RAW bypass: WB và ID trùng chu kỳ, mảng chưa cập nhật nên
    // forward rd_data trực tiếp khi WB đang ghi đúng thanh ghi đang đọc.
    logic we_valid;
    assign we_valid = we && (rd_addr != 5'd0);

    //=========================================================
    // Thao tác Ghi (Synchronous Write)
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (we_valid) begin
            registers[rd_addr] <= rd_data;
        end
    end

    //=========================================================
    // Thao tác Đọc (Combinational Read, write-before-read bypass)
    //=========================================================

    assign rs1_data = (rs1_addr == 5'd0)             ? 32'd0   :
                      (we_valid && rd_addr == rs1_addr) ? rd_data :
                      registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0)             ? 32'd0   :
                      (we_valid && rd_addr == rs2_addr) ? rd_data :
                      registers[rs2_addr];

endmodule
