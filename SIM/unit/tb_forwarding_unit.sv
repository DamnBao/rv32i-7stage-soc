`timescale 1ns/1ps

module tb_forwarding_unit;

    logic [4:0] ex_rs1_addr, ex_rs2_addr;
    logic [4:0] mem1_rd_addr, mem2_rd_addr, wb_rd_addr;
    logic       mem1_reg_write, mem2_reg_write, wb_reg_write;
    logic [1:0] fwd_sel_a, fwd_sel_b;

    forwarding_unit u_dut (.*);

    localparam NO_FWD = 2'b00,
               FWD_M1 = 2'b01,
               FWD_M2 = 2'b10,
               FWD_WB = 2'b11;

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk2(input string name, input logic [1:0] a, e);
        if (a === e) begin
            $display("  PASS  %-50s got=%02b", name, a);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-50s exp=%02b  got=%02b", name, e, a);
            fail_cnt++;
        end
    endtask

    // Positional: (rs1, rs2, m1_rd, m2_rd, wb_rd, m1_we, m2_we, wb_we)
    task automatic drv(
        input logic [4:0] rs1, rs2,
        input logic [4:0] m1_rd, m2_rd, wb_rd,
        input logic       m1_we, m2_we, wb_we
    );
        ex_rs1_addr    = rs1;
        ex_rs2_addr    = rs2;
        mem1_rd_addr   = m1_rd;
        mem1_reg_write = m1_we;
        mem2_rd_addr   = m2_rd;
        mem2_reg_write = m2_we;
        wb_rd_addr     = wb_rd;
        wb_reg_write   = wb_we;
        #1;
    endtask

    initial begin
        $display("======= tb_forwarding_unit =======");

        // ── Không có forward ──
        $display("--- No forward ---");
        drv(5'd1, 5'd2, 5'd5, 5'd6, 5'd7, 1, 1, 1);
        chk2("No match rs1 → NO_FWD",            fwd_sel_a, NO_FWD);
        chk2("No match rs2 → NO_FWD",            fwd_sel_b, NO_FWD);

        // ── Forward từ MEM1 ──
        $display("--- Forward from MEM1 ---");
        // MEM1/MEM2/WB đều có rd=x3, MEM1 phải thắng
        drv(5'd3, 5'd9, 5'd3, 5'd3, 5'd3, 1, 1, 1);
        chk2("MEM1 wins over MEM2/WB (rs1)",     fwd_sel_a, FWD_M1);

        drv(5'd9, 5'd3, 5'd3, 5'd9, 5'd9, 1, 1, 1);
        chk2("MEM1 wins over MEM2/WB (rs2)",     fwd_sel_b, FWD_M1);

        drv(5'd3, 5'd9, 5'd3, 5'd9, 5'd9, 0, 1, 1);   // mem1_we=0
        chk2("MEM1 we=0 → no MEM1 fwd (→ NO)",  fwd_sel_a, NO_FWD);

        // ── Forward từ MEM2 ──
        $display("--- Forward from MEM2 ---");
        drv(5'd4, 5'd5, 5'd9, 5'd4, 5'd4, 1, 1, 1);
        chk2("MEM2 wins over WB (rs1)",          fwd_sel_a, FWD_M2);

        drv(5'd9, 5'd5, 5'd9, 5'd5, 5'd5, 1, 1, 1);
        chk2("MEM2 wins over WB (rs2)",          fwd_sel_b, FWD_M2);

        drv(5'd4, 5'd9, 5'd9, 5'd4, 5'd4, 1, 0, 1);   // mem2_we=0
        chk2("MEM2 we=0 → falls to WB",          fwd_sel_a, FWD_WB);

        // ── Forward từ WB ──
        $display("--- Forward from WB ---");
        drv(5'd6, 5'd7, 5'd9, 5'd9, 5'd6, 1, 1, 1);
        chk2("WB fwd for rs1",                   fwd_sel_a, FWD_WB);

        drv(5'd9, 5'd7, 5'd9, 5'd9, 5'd7, 1, 1, 1);
        chk2("WB fwd for rs2",                   fwd_sel_b, FWD_WB);

        drv(5'd6, 5'd9, 5'd9, 5'd9, 5'd6, 1, 1, 0);   // wb_we=0
        chk2("WB we=0 → NO_FWD",                 fwd_sel_a, NO_FWD);

        // ── x0 không bao giờ forward (rd_addr check blocks it) ──
        $display("--- x0 never forwarded ---");
        drv(5'd0, 5'd0, 5'd0, 5'd0, 5'd0, 1, 1, 1);
        chk2("x0 rd=0 → no fwd rs1",             fwd_sel_a, NO_FWD);
        chk2("x0 rd=0 → no fwd rs2",             fwd_sel_b, NO_FWD);

        // rs2_addr=0 nhưng rd khác 0 — fwd_b phải NO_FWD vì không có match
        drv(5'd5, 5'd0, 5'd5, 5'd9, 5'd9, 1, 1, 1);
        chk2("rs1=5 match m1_rd=5 → FWD_M1",     fwd_sel_a, FWD_M1);
        chk2("rs2=0 no rd matches → NO_FWD",     fwd_sel_b, NO_FWD);

        // ── A và B kênh độc lập ──
        $display("--- Independent A and B ---");
        drv(5'd1, 5'd2, 5'd1, 5'd2, 5'd9, 1, 1, 1);
        chk2("A=MEM1, B=MEM2 simultaneously",    fwd_sel_a, FWD_M1);
        chk2("B=MEM2 simultaneously",            fwd_sel_b, FWD_M2);

        drv(5'd3, 5'd4, 5'd9, 5'd3, 5'd4, 1, 1, 1);
        chk2("A=MEM2, B=WB simultaneously",      fwd_sel_a, FWD_M2);
        chk2("B=WB simultaneously",              fwd_sel_b, FWD_WB);

        $display("==================================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_forwarding_unit: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_forwarding_unit: ALL PASSED");
        $finish;
    end

endmodule
