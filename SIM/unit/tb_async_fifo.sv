`timescale 1ns/1ps

module tb_async_fifo;

    localparam DW = 8;

    logic wr_clk, rd_clk;
    logic wr_rst_n, rd_rst_n;
    logic          wr_en;
    logic [DW-1:0] wr_data;
    logic          rd_en;
    logic [DW-1:0] rd_data;
    logic          rd_empty;

    async_fifo_depth2 #(.DATA_WIDTH(DW)) u_dut (
        .wr_clk   (wr_clk),   .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),    .wr_data  (wr_data),
        .rd_clk   (rd_clk),   .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),    .rd_data  (rd_data),
        .rd_empty (rd_empty)
    );

    // wr_clk: 10ns period (1GHz)
    initial wr_clk = 0;
    always  #5  wr_clk = ~wr_clk;

    // rd_clk: 20ns period (500MHz), fase lệch 7ns để stress CDC
    initial begin rd_clk = 0; #7; forever #10 rd_clk = ~rd_clk; end

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk1(input string name, input logic a, e);
        if (a === e) begin $display("  PASS  %-38s got=%b", name, a); pass_cnt++; end
        else         begin $display("  FAIL  %-38s exp=%b  got=%b", name, e, a); fail_cnt++; end
    endtask

    task automatic chkD(input string name, input logic [DW-1:0] a, e);
        if (a === e) begin $display("  PASS  %-38s got=0x%02X", name, a); pass_cnt++; end
        else         begin $display("  FAIL  %-38s exp=0x%02X  got=0x%02X", name, e, a); fail_cnt++; end
    endtask

    //------------------------------------------------------------------
    // Write task: set wr_en on negedge wr_clk → stable before posedge
    //------------------------------------------------------------------
    task automatic fifo_write(input logic [DW-1:0] data);
        @(negedge wr_clk);
        wr_en   = 1;
        wr_data = data;
        @(posedge wr_clk);  // Data captured here, ptr advances
        @(negedge wr_clk);
        wr_en   = 0;
    endtask

    //------------------------------------------------------------------
    // Read task: capture rd_data on negedge rd_clk (stable, ptr not yet advanced)
    //           then pulse rd_en to advance ptr
    //------------------------------------------------------------------
    task automatic fifo_read_check(input string name, input logic [DW-1:0] expected);
        // Check data at negedge (combinational output, ptr not advanced)
        @(negedge rd_clk); #1;
        chkD(name, rd_data, expected);
        // Advance: assert rd_en before posedge
        rd_en = 1;
        @(posedge rd_clk);  // Ptr advances here
        @(negedge rd_clk);
        rd_en = 0;
    endtask

    //------------------------------------------------------------------
    // Wait N rd_clk cycles for 2-FF sync to propagate
    //------------------------------------------------------------------
    task automatic sync_wait(input int n);
        repeat(n) @(posedge rd_clk);
        @(negedge rd_clk); #1;
    endtask

    //------------------------------------------------------------------
    // Check rd_empty at stable point (after negedge)
    //------------------------------------------------------------------
    task automatic check_empty(input string name, input logic expected);
        @(negedge rd_clk); #1;
        chk1(name, rd_empty, expected);
    endtask

    //------------------------------------------------------------------
    // Reset both domains
    //------------------------------------------------------------------
    task automatic do_reset();
        wr_rst_n = 0; rd_rst_n = 0;
        wr_en = 0;    rd_en   = 0;
        repeat(4) @(posedge wr_clk);
        repeat(3) @(posedge rd_clk);
        @(negedge wr_clk); wr_rst_n = 1;
        @(negedge rd_clk); rd_rst_n = 1;
        sync_wait(3);   // extra settle
    endtask

    initial begin
        $display("======= tb_async_fifo (depth=2, DW=%0d) =======", DW);

        // ── Sau reset: rd_empty=1 ──
        $display("--- After reset: empty ---");
        do_reset();
        chk1("rd_empty=1 after reset", rd_empty, 1'b1);

        // ── Ghi 1 word → empty clears sau 2 rd_clk sync cycles ──
        $display("--- Write 0xAB → empty clears ---");
        fifo_write(8'hAB);
        sync_wait(4);  // 4 cycles đảm bảo 2-FF fully propagated
        chk1("rd_empty=0 after write", rd_empty, 1'b0);

        // ── Đọc lại → verify data đúng và empty trở lại 1 ──
        $display("--- Read back 0xAB ---");
        fifo_read_check("rd_data=0xAB", 8'hAB);
        sync_wait(4);
        chk1("rd_empty=1 after read",  rd_empty, 1'b1);

        // ── Ghi 2 words liên tiếp (full capacity), đọc theo thứ tự ──
        $display("--- Write 2 words (CA, FE), read in order ---");
        do_reset();
        fifo_write(8'hCA);
        fifo_write(8'hFE);
        sync_wait(4);
        chk1("rd_empty=0 (2 written)",  rd_empty, 1'b0);

        fifo_read_check("1st word=0xCA", 8'hCA);   // đọc word đầu và advance ptr
        // Không cần sync_wait vì rd_ptr thay đổi trong rd domain (immediate)
        @(negedge rd_clk); #1;
        chk1("rd_empty=0 (1 left)",  rd_empty, 1'b0);

        fifo_read_check("2nd word=0xFE", 8'hFE);   // đọc word hai và advance ptr
        sync_wait(4);
        chk1("rd_empty=1 (all read)", rd_empty, 1'b1);

        // ── rd_en=1 khi empty → pointer không tiến ──
        $display("--- rd_en=1 when empty: no spurious advance ---");
        do_reset();
        chk1("start empty",    rd_empty, 1'b1);
        rd_en = 1;
        repeat(4) @(posedge rd_clk);
        rd_en = 0;
        @(negedge rd_clk); #1;
        chk1("still empty",    rd_empty, 1'b1);

        // Viết sau đó đọc — nếu ptr đã bị advance sai thì FIFO sẽ miss
        fifo_write(8'h42);
        sync_wait(4);
        chk1("rd_empty=0 after write",  rd_empty, 1'b0);
        fifo_read_check("data=0x42 (ptr not corrupted)", 8'h42);
        sync_wait(4);
        chk1("rd_empty=1 after read",   rd_empty, 1'b1);

        // ── Reset giữa chừng xoá state ──
        $display("--- Reset restores empty ---");
        fifo_write(8'hDE);
        sync_wait(4);
        chk1("non-empty before reset",  rd_empty, 1'b0);
        do_reset();
        chk1("empty after reset",       rd_empty, 1'b1);

        // ── Ghi xen kẽ đọc với nhiều transactions ──
        $display("--- Multi-write/read sequence ---");
        do_reset();
        fifo_write(8'hB1);
        sync_wait(4);
        fifo_read_check("B1", 8'hB1);
        sync_wait(4);
        chk1("empty after B1", rd_empty, 1'b1);

        fifo_write(8'hB2);
        fifo_write(8'hB3);
        sync_wait(4);
        fifo_read_check("B2", 8'hB2);
        @(negedge rd_clk); #1;
        chk1("B3 still pending", rd_empty, 1'b0);
        fifo_read_check("B3", 8'hB3);
        sync_wait(4);
        chk1("empty after B3", rd_empty, 1'b1);

        $display("=======================================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_async_fifo: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_async_fifo: ALL PASSED");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "[TIMEOUT] tb_async_fifo");
    end

endmodule
