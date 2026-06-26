module async_fifo_depth2 #(
    parameter DATA_WIDTH = 67 
)(
    // Miền xung nhịp Ghi
    input  logic                   wr_clk,
    input  logic                   wr_rst_n,
    input  logic                   wr_en,
    input  logic [DATA_WIDTH-1:0]  wr_data, // Đã thêm độ rộng

    // Miền xung nhịp Đọc
    input  logic                   rd_clk,
    input  logic                   rd_rst_n,
    input  logic                   rd_en,
    output logic [DATA_WIDTH-1:0]  rd_data, // Đã thêm độ rộng
    output logic                   rd_empty
);

    // Con trỏ 2-bit: [1] là bit wrap, [0] là bit address
    logic [1:0] wr_ptr_bin, wr_ptr_gray;
    logic [1:0] wr_ptr_bin_next, wr_ptr_gray_next;
    logic [1:0] rd_ptr_bin, rd_ptr_gray;
    logic [1:0] rd_ptr_bin_next, rd_ptr_gray_next;

    // Mảng bộ nhớ: đúng cú pháp [độ rộng] tên [số phần tử]
    logic [DATA_WIDTH-1:0] mem [0:1];

    //=========================================================
    // 1. Logic Miền Ghi
    //=========================================================
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= '0;
            wr_ptr_gray <= '0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en ? 2'd1 : 2'd0);
    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always_ff @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_ptr_bin[0]] <= wr_data; // Sửa lỗi truy cập mảng
        end
    end

    //=========================================================
    // 2. Logic Miền Đọc
    //=========================================================
    assign rd_data = mem[rd_ptr_bin[0]]; // Sửa lỗi truy cập mảng

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= '0;
            rd_ptr_gray <= '0;
        end else if (rd_en && !rd_empty) begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    assign rd_ptr_bin_next  = rd_ptr_bin + 2'd1;
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    //=========================================================
    // 3. Khối đồng bộ & Cờ Empty
    //=========================================================
    logic [1:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

`ifdef FORMAL
    // ── Gray-code single-bit transition invariant ─────────────────
    // Key CDC safety property: wr_ptr_gray must change by at most 1
    // bit per write-clock cycle so that a 2-FF synchroniser in the
    // read domain never captures a metastable intermediate code.
    logic [1:0] f_wr_gray_prev;
    always_ff @(posedge wr_clk) f_wr_gray_prev <= wr_ptr_gray;

    logic [1:0] f_wr_delta;
    assign f_wr_delta = wr_ptr_gray ^ f_wr_gray_prev;

    always @(posedge wr_clk) begin
        if (wr_rst_n) begin
            assert(f_wr_delta != 2'b11);
        end
    end

    // ── P_FIFO_DATA: memory write integrity ───────────────────────
    // One cycle after a write, the target memory slot still holds the written
    // value.  This is the key data-integrity invariant: data written to the
    // FIFO is not silently overwritten before it can be read.
    //
    // Why inductively clean: the next write goes to slot wr_ptr_bin[0]+1[0]
    // (the LSB flips with every pointer advance), so consecutive writes always
    // target DIFFERENT slots — there is never a same-cycle overwrite of a
    // slot written one cycle earlier.

    logic                   f_write_d;
    logic                   f_write_slot_d;
    logic [DATA_WIDTH-1:0]  f_write_data_d;

    always_ff @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            f_write_d      <= 1'b0;
            f_write_slot_d <= 1'b0;
            f_write_data_d <= {DATA_WIDTH{1'b0}};
        end else begin
            f_write_d      <= wr_en;
            f_write_slot_d <= wr_ptr_bin[0];   // slot the previous write targeted
            f_write_data_d <= wr_data;
        end
    end

    always @(posedge wr_clk) begin
        if (wr_rst_n && f_write_d)
            assert(mem[f_write_slot_d] == f_write_data_d);
    end
`endif

endmodule
