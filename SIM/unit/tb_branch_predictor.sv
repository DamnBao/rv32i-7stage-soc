`timescale 1ns/1ps

module tb_branch_predictor;

    logic        clk, rst_n;
    logic [31:0] fetch_pc;
    logic        predict_taken;
    logic [31:0] predict_target;
    logic        update_en;
    logic [31:0] update_pc;
    logic        update_taken;
    logic [31:0] update_target;

    branch_predictor u_dut (.*);

    int pass_cnt = 0, fail_cnt = 0;

    // 10ns clock
    initial clk = 0;
    always #5 clk = ~clk;

    task automatic chk(input string name, input logic a, e);
        if (a === e) begin $display("  PASS  %-50s got=%b", name, a); pass_cnt++; end
        else         begin $display("  FAIL  %-50s exp=%b  got=%b", name, e, a); fail_cnt++; end
    endtask

    task automatic chk32(input string name, input logic [31:0] a, e);
        if (a === e) begin $display("  PASS  %-50s got=%08h", name, a); pass_cnt++; end
        else         begin $display("  FAIL  %-50s exp=%08h  got=%08h", name, e, a); fail_cnt++; end
    endtask

    task automatic tick; @(posedge clk); #1; endtask

    task automatic do_update(input logic [31:0] pc, input logic taken, input logic [31:0] tgt);
        update_en     = 1;
        update_pc     = pc;
        update_taken  = taken;
        update_target = tgt;
        tick;
        update_en = 0;
    endtask

    task automatic lookup(input logic [31:0] pc);
        fetch_pc = pc;
        #1; // combinational settle
    endtask

    initial begin
        $display("=== tb_branch_predictor ===");
        rst_n     = 0;
        fetch_pc  = 0;
        update_en = 0;
        update_pc = 0;
        update_taken  = 0;
        update_target = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // ─────────────────────────────────────────────────────────
        // 1. Cold-start: all entries invalid → predict_taken=0
        // ─────────────────────────────────────────────────────────
        $display("--- 1. Cold start (BTB empty) ---");
        lookup(32'h0000_0100);
        chk("cold: predict_taken=0", predict_taken, 1'b0);

        lookup(32'h0000_0200);
        chk("cold PC2: predict_taken=0", predict_taken, 1'b0);

        // ─────────────────────────────────────────────────────────
        // 2. Single taken update → BHT 01→10, BTB written
        // ─────────────────────────────────────────────────────────
        $display("--- 2. First taken update ---");
        do_update(32'h0000_0100, 1'b1, 32'h0000_0200);  // branch at 0x100 taken → 0x200
        lookup(32'h0000_0100);
        chk  ("after 1 taken: predict_taken=1",  predict_taken,  1'b1);
        chk32("after 1 taken: predict_target",   predict_target, 32'h0000_0200);

        // ─────────────────────────────────────────────────────────
        // 3. Second taken update → BHT 10→11 (strongly taken)
        // ─────────────────────────────────────────────────────────
        $display("--- 3. Second taken update (strong taken) ---");
        do_update(32'h0000_0100, 1'b1, 32'h0000_0200);
        lookup(32'h0000_0100);
        chk  ("strong taken: predict_taken=1",  predict_taken,  1'b1);
        chk32("strong taken: predict_target",   predict_target, 32'h0000_0200);

        // ─────────────────────────────────────────────────────────
        // 4. One not-taken from strong (11→10) → still predict taken
        // ─────────────────────────────────────────────────────────
        $display("--- 4. Not-taken from strong (11→10, still taken) ---");
        do_update(32'h0000_0100, 1'b0, 32'h0000_0200);
        lookup(32'h0000_0100);
        chk("11→10: still predict_taken=1", predict_taken, 1'b1);

        // ─────────────────────────────────────────────────────────
        // 5. Second not-taken (10→01) → predict not-taken
        // ─────────────────────────────────────────────────────────
        $display("--- 5. Second not-taken (10→01, predict not-taken) ---");
        do_update(32'h0000_0100, 1'b0, 32'h0000_0200);
        lookup(32'h0000_0100);
        chk("10→01: predict_taken=0", predict_taken, 1'b0);

        // ─────────────────────────────────────────────────────────
        // 6. Saturate at 00 (two more not-taken) → stays 0
        // ─────────────────────────────────────────────────────────
        $display("--- 6. Saturate at strongly not-taken ---");
        do_update(32'h0000_0100, 1'b0, 32'h0000_0200);  // 01→00
        do_update(32'h0000_0100, 1'b0, 32'h0000_0200);  // 00 saturate
        lookup(32'h0000_0100);
        chk("00 saturated: predict_taken=0", predict_taken, 1'b0);
        // One taken: 00→01 → still not-taken
        do_update(32'h0000_0100, 1'b1, 32'h0000_0200);  // 00→01
        lookup(32'h0000_0100);
        chk("00→01: predict_taken=0", predict_taken, 1'b0);

        // ─────────────────────────────────────────────────────────
        // 7. Tag mismatch: different PC maps to same index, different tag → no hit
        // index = pc[5:2]; PC 0x100 → index 0; PC 0x140 → same index 0, different tag
        // ─────────────────────────────────────────────────────────
        $display("--- 7. Tag collision: different PC, same BTB index ---");
        // BTB[0] was written for 0x100 (tag=0x100>>6=4). Now lookup 0x140 (tag=0x140>>6=5)
        lookup(32'h0000_0140);  // PC[5:2]=0 same index, but tag differs from 0x100
        chk("tag mismatch: predict_taken=0", predict_taken, 1'b0);

        // ─────────────────────────────────────────────────────────
        // 8. Different index: branch at 0x110 (index=4) independent of 0x100 (index=0)
        // ─────────────────────────────────────────────────────────
        $display("--- 8. Independent entries (different indices) ---");
        do_update(32'h0000_0110, 1'b1, 32'h0000_0500);  // index=4, taken
        do_update(32'h0000_0110, 1'b1, 32'h0000_0500);  // make strongly taken
        lookup(32'h0000_0110);
        chk  ("idx4: predict_taken=1",   predict_taken,  1'b1);
        chk32("idx4: predict_target",    predict_target, 32'h0000_0500);
        // Verify index=0 is unaffected
        lookup(32'h0000_0100);
        chk("idx0 still 01: predict_taken=0", predict_taken, 1'b0);

        // ─────────────────────────────────────────────────────────
        // 9. BTB target update: taken again with new target overwrites BTB
        // ─────────────────────────────────────────────────────────
        $display("--- 9. BTB target update ---");
        // Warm up index=8 (PC=0x120)
        do_update(32'h0000_0120, 1'b1, 32'h0000_0AA0);  // first taken
        do_update(32'h0000_0120, 1'b1, 32'h0000_0BB0);  // taken again, new target
        lookup(32'h0000_0120);
        chk  ("updated target: predict_taken=1",   predict_taken,  1'b1);
        chk32("updated target: predict_target=BB0", predict_target, 32'h0000_0BB0);

        // ─────────────────────────────────────────────────────────
        // 10. Update_en=0: no change to predictor state
        // ─────────────────────────────────────────────────────────
        $display("--- 10. update_en=0 suppresses update ---");
        lookup(32'h0000_0120);
        chk("before: predict_taken=1", predict_taken, 1'b1);
        // Try to update with not-taken but update_en=0
        update_en    = 0;
        update_pc    = 32'h0000_0120;
        update_taken = 0;
        tick;
        lookup(32'h0000_0120);
        chk("after no-update: still predict_taken=1", predict_taken, 1'b1);

        // ─────────────────────────────────────────────────────────
        // 11. Reset: clears all state
        // ─────────────────────────────────────────────────────────
        $display("--- 11. Reset clears predictor ---");
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        lookup(32'h0000_0110);
        chk("after reset idx4: predict_taken=0", predict_taken, 1'b0);
        lookup(32'h0000_0120);
        chk("after reset idx8: predict_taken=0", predict_taken, 1'b0);

        // ─────────────────────────────────────────────────────────
        // 12. Loop simulation: 10 iterations, backward branch always taken
        // ─────────────────────────────────────────────────────────
        $display("--- 12. Loop: 10 taken + 1 not-taken, verify hysteresis ---");
        begin : loop_sim
            integer k;
            // PC 0x200: loop branch, target 0x200-20=0x1EC (backward)
            for (k = 0; k < 10; k = k + 1) begin
                do_update(32'h0000_0200, 1'b1, 32'h0000_01EC);
            end
            lookup(32'h0000_0200);
            chk  ("loop after 10 taken: predict_taken=1",    predict_taken,  1'b1);
            chk32("loop: predict_target=0x1EC",              predict_target, 32'h0000_01EC);
            // Loop exits: not-taken once → BHT 11→10 (still taken)
            do_update(32'h0000_0200, 1'b0, 32'h0000_01EC);
            lookup(32'h0000_0200);
            chk("loop exit (11→10): still predict_taken=1", predict_taken, 1'b1);
        end

        // ─────────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────────
        $display("");
        $display("=== tb_branch_predictor: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TEST_PASS");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
