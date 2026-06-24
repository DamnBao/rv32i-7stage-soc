module dmem #(
    parameter SIZE_KB = 64
)(
    input  logic        clk,

    // Read port (từ MEM1 stage)
    input  logic        re,
    input  logic [31:0] addr,
    output logic [31:0] rdata,   // Đồng bộ: data ra ở cạnh clock tiếp theo (giống IMEM)

    // Write port
    input  logic        we,
    input  logic [31:0] wdata,   // = rs2_data (full 32-bit, CPU không căn chỉnh trước)
    input  logic [1:0]  size     // 00=byte, 01=half, 10=word
);

    localparam DEPTH  = (SIZE_KB * 1024) / 4;
    localparam ADDR_W = $clog2(DEPTH);

    logic [31:0] mem [0:DEPTH-1];

    // Word address — bỏ 2 bit thấp (word-aligned), giống IMEM
    logic [ADDR_W-1:0] word_addr;
    assign word_addr = addr >> 2;

    // Bóc tách byte/half offset ngoài always để tránh lỗi Icarus
    logic [1:0] byte_off;
    logic       half_off;
    assign byte_off = addr[1:0];
    assign half_off = addr[1];

    // Bóc tách byte và half từ wdata ngoài always
    logic [7:0]  wdata_byte;
    logic [15:0] wdata_half;
    assign wdata_byte = wdata[7:0];
    assign wdata_half = wdata[15:0];

    //=========================================================
    // Byte Write Enable
    // RISC-V CPU truyền wdata không căn chỉnh (byte ở [7:0], half ở [15:0])
    // → replicate dữ liệu lên toàn bộ word, sau đó dùng be_mask để chọn byte đúng
    //=========================================================
    logic [3:0]  be;
    logic [31:0] wr_data_aligned;

    always_comb begin
        case (size)
            2'b10: begin // Word
                be             = 4'b1111;
                wr_data_aligned = wdata;
            end
            2'b01: begin // Half-word
                be             = half_off ? 4'b1100 : 4'b0011;
                wr_data_aligned = {wdata_half, wdata_half};
            end
            default: begin // Byte
                be             = 4'b0001 << byte_off;
                wr_data_aligned = {wdata_byte, wdata_byte, wdata_byte, wdata_byte};
            end
        endcase
    end

    // Mở rộng be thành byte mask 32-bit (dùng assign để tránh lỗi Icarus)
    logic [31:0] be_mask;
    assign be_mask = {{8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}}};

    //=========================================================
    // Synchronous Write (Read-Modify-Write với byte mask)
    // Không cần rst_n cho mảng RAM (tương tự IMEM)
    //=========================================================
    always_ff @(posedge clk) begin
        if (we)
            mem[word_addr] <= (wr_data_aligned & be_mask) | (mem[word_addr] & ~be_mask);
    end

    //=========================================================
    // Synchronous Read — hành vi giống IMEM
    // Gated by re để rdata chỉ cập nhật khi có lệnh Load
    // MEM2 nhận data ở chu kỳ kế tiếp sau khi MEM1 issue read
    //=========================================================
    always_ff @(posedge clk) begin
        if (re)
            rdata <= mem[word_addr];
    end

endmodule
