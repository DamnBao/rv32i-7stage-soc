`timescale 1ns/1ps

module tb_register_file;

    logic        clk, rst_n;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] rs1_data, rs2_data, rd_data;
    logic        we;

    register_file u_dut (.*);

    initial clk = 0;
    always  #5 clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;

    task automatic check32(
        input string  name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual === expected) begin
            $display("  PASS  %-40s got=0x%08X", name, actual);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-40s expected=0x%08X  got=0x%08X",
                     name, expected, actual);
            fail_cnt++;
        end
    endtask

    // Ghi 1 register: áp dụng tín hiệu, đợi posedge
    task automatic rf_write(input logic [4:0] addr, input logic [31:0] data);
        rd_addr = addr;
        rd_data = data;
        we      = 1'b1;
        @(posedge clk); #1;   // 1ns sau posedge để latch xong
        we      = 1'b0;
    endtask

    // Đọc register (combinational)
    task automatic rf_read_check(
        input string  name,
        input logic [4:0] addr,
        input logic [31:0] expected
    );
        rs1_addr = addr;
        #1;
        check32(name, rs1_data, expected);
    endtask

    task automatic do_reset();
        rst_n = 0;
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
    endtask

    initial begin
        we = 0; rd_addr = 0; rd_data = 0;
        rs1_addr = 0; rs2_addr = 0;
        $display("======= tb_register_file =======");

        // ── Sau reset: tất cả = 0 ──
        $display("--- After reset ---");
        do_reset();
        rf_read_check("x0 after reset",  5'd0,  32'd0);
        rf_read_check("x1 after reset",  5'd1,  32'd0);
        rf_read_check("x31 after reset", 5'd31, 32'd0);

        // ── Ghi và đọc lại ──
        $display("--- Write then read ---");
        rf_write(5'd1, 32'hDEAD_BEEF);
        rf_read_check("x1 = DEAD_BEEF",  5'd1,  32'hDEAD_BEEF);

        rf_write(5'd31, 32'hABCD_1234);
        rf_read_check("x31 = ABCD_1234", 5'd31, 32'hABCD_1234);

        rf_write(5'd15, 32'h1234_5678);
        rf_read_check("x15 = 1234_5678", 5'd15, 32'h1234_5678);

        // ── x0 hardwired = 0 (write phải bị bỏ qua) ──
        $display("--- x0 hardwired zero ---");
        rf_write(5'd0, 32'hFFFF_FFFF);  // write x0 — phải bị ignore
        rf_read_check("x0 still = 0",    5'd0,  32'd0);

        // ── Dual-port read: rs1 và rs2 cùng lúc ──
        $display("--- Dual-port read ---");
        rf_write(5'd2, 32'hAAAA_AAAA);
        rf_write(5'd3, 32'h5555_5555);
        rs1_addr = 5'd2;
        rs2_addr = 5'd3;
        #1;
        check32("rs1 (x2)", rs1_data, 32'hAAAA_AAAA);
        check32("rs2 (x3)", rs2_data, 32'h5555_5555);

        // ── Read x0 qua rs2 ──
        rs2_addr = 5'd0;
        #1;
        check32("rs2 (x0) = 0", rs2_data, 32'd0);

        // ── we=0: write bị chặn ──
        $display("--- Write disabled (we=0) ---");
        rd_addr = 5'd4;
        rd_data = 32'hCAFE_BABE;
        we      = 1'b0;
        @(posedge clk); #1;
        rf_read_check("x4 unchanged (we=0)", 5'd4, 32'd0);

        // ── Ghi nhiều registers, kiểm tra không ảnh hưởng nhau ──
        $display("--- Independent registers ---");
        rf_write(5'd5,  32'd100);
        rf_write(5'd6,  32'd200);
        rf_write(5'd7,  32'd300);
        rf_read_check("x5 = 100", 5'd5, 32'd100);
        rf_read_check("x6 = 200", 5'd6, 32'd200);
        rf_read_check("x7 = 300", 5'd7, 32'd300);

        // ── Reset giữa chừng: mọi reg về 0 ──
        $display("--- Mid-test reset ---");
        rst_n = 0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
        rf_read_check("x1 after mid-reset", 5'd1,  32'd0);
        rf_read_check("x5 after mid-reset", 5'd5,  32'd0);
        rf_read_check("x31 after mid-reset",5'd31, 32'd0);

        $display("=================================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_register_file: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_register_file: ALL PASSED");
        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $fatal(1, "[TIMEOUT] tb_register_file hung");
    end

endmodule
