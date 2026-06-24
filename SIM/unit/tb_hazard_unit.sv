`timescale 1ns/1ps

module tb_hazard_unit;

    logic       bus_stall_req;
    logic       ex_mem_read;
    logic [4:0] ex_rd_addr;
    logic [4:0] id_rs1_addr, id_rs2_addr;
    logic       branch_taken, jump;
    logic       zicsr_flush;

    logic       stall_if1_if2, stall_if2_id, stall_id_ex;
    logic       stall_ex_mem1, stall_mem1_mem2, stall_mem2_wb;
    logic       stall_pc, flush_pc;
    logic       flush_if1_if2, flush_if2_id, flush_id_ex;
    logic       flush_ex_mem1, flush_mem1_mem2, flush_mem2_wb;

    hazard_unit u_dut (.*);

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk1(input string name, input logic a, e);
        if (a === e) begin
            $display("  PASS  %-45s got=%b", name, a);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-45s exp=%b  got=%b", name, e, a);
            fail_cnt++;
        end
    endtask

    // Reset tất cả inputs về idle
    task automatic idle();
        bus_stall_req = 0;
        ex_mem_read   = 0;
        ex_rd_addr    = 5'd0;
        id_rs1_addr   = 5'd1;
        id_rs2_addr   = 5'd2;
        branch_taken  = 0;
        jump          = 0;
        zicsr_flush   = 0;
        #1;
    endtask

    initial begin
        $display("======= tb_hazard_unit =======");

        // ── Idle: không có hazard → tất cả stall=0, flush=0 ──
        $display("--- Idle: no hazard ---");
        idle();
        chk1("stall_pc=0",         stall_pc,        1'b0);
        chk1("stall_if1_if2=0",    stall_if1_if2,   1'b0);
        chk1("stall_if2_id=0",     stall_if2_id,    1'b0);
        chk1("stall_id_ex=0",      stall_id_ex,     1'b0);
        chk1("stall_ex_mem1=0",    stall_ex_mem1,   1'b0);
        chk1("stall_mem1_mem2=0",  stall_mem1_mem2, 1'b0);
        chk1("stall_mem2_wb=0",    stall_mem2_wb,   1'b0);
        chk1("flush_pc=0",         flush_pc,        1'b0);
        chk1("flush_if1_if2=0",    flush_if1_if2,   1'b0);
        chk1("flush_if2_id=0",     flush_if2_id,    1'b0);
        chk1("flush_id_ex=0",      flush_id_ex,     1'b0);
        chk1("flush_ex_mem1=0",    flush_ex_mem1,   1'b0);
        chk1("flush_mem1_mem2=0",  flush_mem1_mem2, 1'b0);
        chk1("flush_mem2_wb=0",    flush_mem2_wb,   1'b0);

        // ── Load-Use: ex_mem_read=1, rd=x3, id_rs1=x3 ──
        // Phải stall IF1..ID, flush ID/EX; KHÔNG stall EX..WB
        $display("--- Load-use hazard (rs1 match) ---");
        idle();
        ex_mem_read  = 1;
        ex_rd_addr   = 5'd3;
        id_rs1_addr  = 5'd3;   // match rs1
        id_rs2_addr  = 5'd9;   // no match
        #1;
        chk1("stall_pc=1",         stall_pc,        1'b1);
        chk1("stall_if1_if2=1",    stall_if1_if2,   1'b1);
        chk1("stall_if2_id=1",     stall_if2_id,    1'b1);
        chk1("stall_id_ex=0",      stall_id_ex,     1'b0); // ID/EX không stall, chỉ flush
        chk1("stall_ex_mem1=0",    stall_ex_mem1,   1'b0);
        chk1("flush_id_ex=1",      flush_id_ex,     1'b1); // bubble vào EX
        chk1("flush_if1_if2=0",    flush_if1_if2,   1'b0); // IF1/IF2 không flush
        chk1("flush_if2_id=0",     flush_if2_id,    1'b0); // IF2/ID không flush

        // Load-use qua rs2
        $display("--- Load-use hazard (rs2 match) ---");
        idle();
        ex_mem_read  = 1;
        ex_rd_addr   = 5'd4;
        id_rs1_addr  = 5'd9;
        id_rs2_addr  = 5'd4;   // match rs2
        #1;
        chk1("stall_pc=1 (rs2 match)", stall_pc,   1'b1);
        chk1("flush_id_ex=1",          flush_id_ex, 1'b1);

        // Load-use với rd=x0 → KHÔNG stall (x0 không ghi)
        $display("--- Load-use rd=x0 → no stall ---");
        idle();
        ex_mem_read  = 1;
        ex_rd_addr   = 5'd0;   // x0: không bao giờ gây hazard
        id_rs1_addr  = 5'd0;
        id_rs2_addr  = 5'd0;
        #1;
        chk1("stall_pc=0 (rd=x0)",    stall_pc,    1'b0);
        chk1("flush_id_ex=0 (rd=x0)", flush_id_ex, 1'b0);

        // Load-use nhưng ex_mem_read=0 → không stall
        $display("--- ex_mem_read=0 → no load-use stall ---");
        idle();
        ex_mem_read  = 0;
        ex_rd_addr   = 5'd3;
        id_rs1_addr  = 5'd3;
        #1;
        chk1("stall_pc=0 (not load)", stall_pc,    1'b0);

        // ── Branch taken: flush IF fetch stages + ID/EX ──
        $display("--- Branch taken ---");
        idle();
        branch_taken = 1;
        #1;
        chk1("flush_if1_if2=1",    flush_if1_if2,   1'b1);
        chk1("flush_if2_id=1",     flush_if2_id,    1'b1);
        chk1("flush_id_ex=1",      flush_id_ex,     1'b1);
        chk1("flush_ex_mem1=0",    flush_ex_mem1,   1'b0); // EX không flush
        chk1("stall_pc=0",         stall_pc,        1'b0); // không stall
        chk1("stall_if1_if2=0",    stall_if1_if2,   1'b0);

        // ── Jump: same flush pattern as branch ──
        $display("--- Jump ---");
        idle();
        jump = 1;
        #1;
        chk1("flush_if1_if2=1",    flush_if1_if2,   1'b1);
        chk1("flush_if2_id=1",     flush_if2_id,    1'b1);
        chk1("flush_id_ex=1",      flush_id_ex,     1'b1);
        chk1("flush_ex_mem1=0",    flush_ex_mem1,   1'b0);
        chk1("stall_pc=0",         stall_pc,        1'b0);

        // ── Bus stall: đóng băng toàn pipeline ──
        $display("--- Bus stall ---");
        idle();
        bus_stall_req = 1;
        #1;
        chk1("stall_pc=1",         stall_pc,        1'b1);
        chk1("stall_if1_if2=1",    stall_if1_if2,   1'b1);
        chk1("stall_if2_id=1",     stall_if2_id,    1'b1);
        chk1("stall_id_ex=1",      stall_id_ex,     1'b1);
        chk1("stall_ex_mem1=1",    stall_ex_mem1,   1'b1);
        chk1("stall_mem1_mem2=1",  stall_mem1_mem2, 1'b1);
        chk1("stall_mem2_wb=1",    stall_mem2_wb,   1'b1);
        // Bus stall không flush (pipeline đứng yên)
        chk1("flush_if1_if2=0",    flush_if1_if2,   1'b0);
        chk1("flush_id_ex=0",      flush_id_ex,     1'b0);

        // ── Zicsr flush: flush toàn pipeline ──
        $display("--- Zicsr flush ---");
        idle();
        zicsr_flush = 1;
        #1;
        chk1("flush_pc=1",         flush_pc,        1'b1);
        chk1("flush_if1_if2=1",    flush_if1_if2,   1'b1);
        chk1("flush_if2_id=1",     flush_if2_id,    1'b1);
        chk1("flush_id_ex=1",      flush_id_ex,     1'b1);
        chk1("flush_ex_mem1=1",    flush_ex_mem1,   1'b1);
        chk1("flush_mem1_mem2=1",  flush_mem1_mem2, 1'b1);
        chk1("flush_mem2_wb=1",    flush_mem2_wb,   1'b1);
        chk1("stall_pc=0",         stall_pc,        1'b0);  // flush, không stall

        // ── Load-use + branch taken cùng lúc ──
        // Load-use stalls IF1/IF2, IF2/ID, flushes ID/EX
        // Branch flush flushes IF1/IF2, IF2/ID, ID/EX → cùng effect
        // Kết quả: stall_if1_if2=1, stall_if2_id=1, flush_id_ex=1
        $display("--- Load-use + branch taken ---");
        idle();
        ex_mem_read  = 1;
        ex_rd_addr   = 5'd5;
        id_rs1_addr  = 5'd5;
        branch_taken = 1;
        #1;
        chk1("stall_pc=1",         stall_pc,        1'b1);
        chk1("flush_if1_if2=1",    flush_if1_if2,   1'b1);
        chk1("flush_id_ex=1",      flush_id_ex,     1'b1);

        // ── Zicsr flush trumps tất cả ──
        $display("--- Zicsr + branch + load-use ---");
        idle();
        zicsr_flush  = 1;
        branch_taken = 1;
        ex_mem_read  = 1;
        ex_rd_addr   = 5'd5;
        id_rs1_addr  = 5'd5;
        #1;
        chk1("flush_ex_mem1=1 (zicsr wins)", flush_ex_mem1, 1'b1);
        chk1("flush_mem2_wb=1 (zicsr wins)", flush_mem2_wb, 1'b1);

        $display("==============================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_hazard_unit: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_hazard_unit: ALL PASSED");
        $finish;
    end

endmodule
