module imem #(
    parameter SIZE_KB = 64
)(
    input  logic        clk,
    input  logic        stall,       // Hold output during load-use stall (sync with if1_if2_reg freeze)
    input  logic        flush,       // Flush: output NOP so the stale IMEM word doesn't reach ID as a ghost instruction
    input  logic [31:0] addr,        // Nối trực tiếp từ pc_out của if1_stage
    output logic [31:0] instr_out    // Xuất ra ở tầng IF2
);

    localparam DEPTH  = (SIZE_KB * 1024) / 4;
    localparam ADDR_W = $clog2(DEPTH);

    // Mảng thanh ghi 32-bit, độ sâu DEPTH từ = 16384 từ cho 64KB
    logic [31:0] mem [0:DEPTH-1];

    // Cắt 2 bit thấp (word-aligned), giữ ADDR_W bit làm chỉ số mảng
    // Dùng assign bên ngoài always_* để tránh lỗi constant-select trên Icarus
    logic [ADDR_W-1:0] word_addr;
    assign word_addr = addr >> 2;

    // flush: pipeline redirect just fired; register a NOP so the stale word at the
    // old address never reaches ID as a ghost instruction one cycle later.
    // stall: hold output when if1_if2_reg is frozen to keep PC/instruction in sync.
    always_ff @(posedge clk) begin
        if (flush)
            instr_out <= 32'h0000_0013;  // addi x0,x0,0 — harmless NOP
        else if (!stall)
            instr_out <= mem[word_addr];
    end

endmodule
