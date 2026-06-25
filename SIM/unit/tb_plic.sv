`timescale 1ns/1ps
// Unit test for RTL/plic.sv
// 25 test cases covering: reset, register R/W, IRQ raise/complete,
// priority selection, tie-break, threshold, enable mask, AHB source,
// edge detection, multi-source claim sequence

module tb_plic;

    logic        clk, rst_n;
    logic [5:0]  irq_src;
    logic        re, we;
    logic [23:0] addr;
    logic [31:0] wdata, rdata;
    logic        meip;

    plic u_dut (
        .clk(clk), .rst_n(rst_n),
        .irq_src(irq_src),
        .re(re), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata),
        .meip(meip)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk1(input string name, input logic a, e);
        if (a === e) begin $display("  PASS  %-46s got=%b", name, a); pass_cnt++; end
        else         begin $display("  FAIL  %-46s exp=%b  got=%b", name, e, a); fail_cnt++; end
    endtask

    task automatic chk32(input string name, input logic [31:0] a, e);
        if (a === e) begin $display("  PASS  %-46s got=0x%08X", name, a); pass_cnt++; end
        else         begin $display("  FAIL  %-46s exp=0x%08X  got=0x%08X", name, e, a); fail_cnt++; end
    endtask

    // Write PLIC register (takes 1 posedge to commit)
    task automatic plic_write(input [23:0] a, input [31:0] d);
        @(negedge clk); we = 1; addr = a; wdata = d;
        @(posedge clk);
        @(negedge clk); we = 0;
    endtask

    // Read PLIC register with 1-cycle latency and check result
    task automatic plic_read_check(input string name, input [23:0] a, input [31:0] exp);
        @(negedge clk); re = 1; addr = a;
        @(posedge clk); #1;
        chk32(name, rdata, exp);
        @(negedge clk); re = 0;
    endtask

    // Raise irq_src lines and wait 1 posedge for pending to register
    task automatic raise_irq(input [5:0] bits);
        @(negedge clk); irq_src = bits;
        @(posedge clk); #1;
    endtask

    // Lower irq_src lines
    task automatic lower_irq(input [5:0] bits);
        @(negedge clk); irq_src = bits;
        @(posedge clk); #1;
    endtask

    // Write COMPLETE register to clear a source's pending
    task automatic plic_complete(input [2:0] src_id);
        @(negedge clk); we = 1; addr = 24'h200004; wdata = {29'd0, src_id};
        @(posedge clk); #1;
        @(negedge clk); we = 0;
    endtask

    // Reset DUT to clean state
    task automatic do_reset;
        @(negedge clk);
        rst_n = 0; irq_src = 0; re = 0; we = 0; addr = 0; wdata = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
    endtask

    initial begin
        $display("=== tb_plic ===");

        //==========================================================
        // Group 1: Reset state
        //==========================================================
        $display("");
        $display("-- Group 1: Reset state --");
        do_reset;
        chk1("TC01 meip=0 after reset",              meip,  1'b0);
        plic_read_check("TC02 CLAIM=0 after reset",  24'h200004, 32'd0);

        //==========================================================
        // Group 2: Basic register read/write
        //==========================================================
        $display("");
        $display("-- Group 2: Register read/write --");

        plic_write(24'h000004, 32'd5);  // PRIORITY[1] = 5
        plic_read_check("TC03 PRIORITY[1] write/read=5", 24'h000004, 32'd5);

        plic_write(24'h002000, 32'd2);  // ENABLE: bit[1]=1 → source 1 enabled
        plic_read_check("TC04 ENABLE=2 write/read",       24'h002000, 32'd2);

        plic_write(24'h200000, 32'd3);  // THRESHOLD = 3
        plic_read_check("TC05 THRESHOLD=3 write/read",    24'h200000, 32'd3);

        //==========================================================
        // Group 3: IRQ raise → meip, pending, claim
        // Setup: PRIORITY[1]=5, ENABLE[1]=1, THRESHOLD=0
        //==========================================================
        $display("");
        $display("-- Group 3: IRQ raise → meip/pending/claim --");

        do_reset;
        plic_write(24'h000004, 32'd5);  // PRIORITY[1] = 5
        plic_write(24'h002000, 32'd2);  // ENABLE source 1
        plic_write(24'h200000, 32'd0);  // THRESHOLD = 0

        raise_irq(6'b000001);           // source 1 = irq_src[0]
        chk1("TC06 meip=1 after source1 raise", meip, 1'b1);

        // PENDING: {25'd0, reg_pending[6:1], 1'b0} → source1 → bit[1]=1 → value=2
        plic_read_check("TC07 PENDING=2 (source1 set)", 24'h001000, 32'd2);

        // CLAIM: winner_id = 1 (only active source)
        plic_read_check("TC08 CLAIM=1 (source1 wins)", 24'h200004, 32'd1);

        //==========================================================
        // Group 4: Complete → clears pending
        //==========================================================
        $display("");
        $display("-- Group 4: Complete clears pending --");

        // irq_src[0] still high but edge detect: irq_src_prev=1 → no re-trigger
        plic_complete(3'd1);
        chk1("TC09 meip=0 after complete(1)",          meip, 1'b0);
        plic_read_check("TC10 PENDING=0 after complete", 24'h001000, 32'd0);

        //==========================================================
        // Group 5: Priority selection — higher wins; tie → lower ID wins
        //==========================================================
        $display("");
        $display("-- Group 5: Priority selection --");

        do_reset;
        // Source 1 (pri=3) vs Source 2 (pri=5) → source 2 should win
        plic_write(24'h000004, 32'd3);  // PRIORITY[1] = 3
        plic_write(24'h000008, 32'd5);  // PRIORITY[2] = 5
        plic_write(24'h002000, 32'd6);  // ENABLE sources 1 and 2 (bits 1,2 → value 0b110=6)
        plic_write(24'h200000, 32'd0);  // THRESHOLD = 0

        // Both sources rise simultaneously
        @(negedge clk); irq_src = 6'b000011;  // irq_src[0]=src1, irq_src[1]=src2
        @(posedge clk); #1;
        plic_read_check("TC11 CLAIM=2 (pri5 beats pri3)", 24'h200004, 32'd2);

        // Tie-break: both sources same priority → lower ID wins
        plic_complete(3'd2);
        do_reset;
        plic_write(24'h000004, 32'd3);  // PRIORITY[1] = 3
        plic_write(24'h000008, 32'd3);  // PRIORITY[2] = 3 (tie)
        plic_write(24'h002000, 32'd6);  // ENABLE sources 1 and 2
        plic_write(24'h200000, 32'd0);  // THRESHOLD = 0
        @(negedge clk); irq_src = 6'b000011;
        @(posedge clk); #1;
        plic_read_check("TC12 CLAIM=1 (tie → lower ID wins)", 24'h200004, 32'd1);

        //==========================================================
        // Group 6: Threshold blocking
        //==========================================================
        $display("");
        $display("-- Group 6: Threshold --");

        // Setup: source1 active but threshold=3, priority[1]=2 → 2 > 3 is false → blocked
        plic_complete(3'd1); // clear from previous
        do_reset;
        plic_write(24'h000004, 32'd2);  // PRIORITY[1] = 2
        plic_write(24'h002000, 32'd2);  // ENABLE source 1
        plic_write(24'h200000, 32'd3);  // THRESHOLD = 3  (priority must be > threshold)
        raise_irq(6'b000001);
        chk1("TC13 meip=0 when priority<=threshold", meip, 1'b0);

        // Lower threshold: now priority=2 > threshold=1 → forward
        plic_write(24'h200000, 32'd1);  // THRESHOLD = 1
        @(posedge clk); #1;
        chk1("TC14 meip=1 after threshold lowered",  meip, 1'b1);

        //==========================================================
        // Group 7: Enable masking
        //==========================================================
        $display("");
        $display("-- Group 7: Enable mask --");

        // Clear pending via complete, then re-raise to test enable
        plic_complete(3'd1);
        lower_irq(6'b000000);   // bring irq low so edge detect fires again next time
        do_reset;
        plic_write(24'h000004, 32'd3);
        plic_write(24'h002000, 32'd0);  // ENABLE = 0 (all disabled)
        plic_write(24'h200000, 32'd0);
        raise_irq(6'b000001);           // pending[1] sets but not enabled
        chk1("TC15 meip=0 when source disabled",      meip, 1'b0);

        plic_write(24'h002000, 32'd2);  // Re-enable source 1 → active immediately
        @(posedge clk); #1;
        chk1("TC16 meip=1 after re-enable",           meip, 1'b1);

        //==========================================================
        // Group 8: Priority=0 disables source
        //==========================================================
        $display("");
        $display("-- Group 8: Priority=0 disable --");

        plic_complete(3'd1);
        lower_irq(6'b000000);
        do_reset;
        plic_write(24'h000004, 32'd0);  // PRIORITY[1] = 0 (disabled)
        plic_write(24'h002000, 32'd2);  // ENABLE source 1
        plic_write(24'h200000, 32'd0);  // THRESHOLD = 0
        raise_irq(6'b000001);
        chk1("TC17 meip=0 when priority=0",           meip, 1'b0);

        //==========================================================
        // Group 9: Multi-source claim sequence
        // Source1 pri=5, source2 pri=3 — both pending, claim highest first
        //==========================================================
        $display("");
        $display("-- Group 9: Multi-source claim sequence --");

        do_reset;
        plic_write(24'h000004, 32'd5);  // PRIORITY[1] = 5
        plic_write(24'h000008, 32'd3);  // PRIORITY[2] = 3
        plic_write(24'h002000, 32'd6);  // ENABLE sources 1,2
        plic_write(24'h200000, 32'd0);  // THRESHOLD = 0
        @(negedge clk); irq_src = 6'b000011;
        @(posedge clk); #1;

        // First claim: source 1 wins (priority 5 > 3)
        plic_read_check("TC18 first CLAIM=1 (pri5)",  24'h200004, 32'd1);
        plic_complete(3'd1);
        // Source 2 still pending
        chk1("TC18b meip=1 (source2 still pending)",  meip, 1'b1);

        // Second claim: source 2
        plic_read_check("TC19 second CLAIM=2",        24'h200004, 32'd2);
        plic_complete(3'd2);
        chk1("TC19b meip=0 (all complete)",           meip, 1'b0);

        //==========================================================
        // Group 10: AHB source (source 4 = irq_src[3])
        //==========================================================
        $display("");
        $display("-- Group 10: AHB source (source 4) --");

        lower_irq(6'b000000);
        do_reset;
        plic_write(24'h000010, 32'd1);  // PRIORITY[4] = 1 (offset 0x10)
        plic_write(24'h002000, 32'd16); // ENABLE source 4 (bit[4]=1 → value=16)
        plic_write(24'h200000, 32'd0);  // THRESHOLD = 0
        raise_irq(6'b001000);           // irq_src[3] = source 4
        chk1("TC20 meip=1 from AHB source4",          meip, 1'b1);
        plic_read_check("TC20b CLAIM=4",              24'h200004, 32'd4);
        plic_complete(3'd4);
        chk1("TC21 meip=0 after AHB complete",        meip, 1'b0);

        //==========================================================
        // Group 11: Rising-edge detection (no re-trigger while irq stays high)
        //==========================================================
        $display("");
        $display("-- Group 11: Edge detection --");

        lower_irq(6'b000000);
        do_reset;
        plic_write(24'h000004, 32'd1);
        plic_write(24'h002000, 32'd2);
        plic_write(24'h200000, 32'd0);

        // Raise irq: pending sets
        raise_irq(6'b000001);
        plic_complete(3'd1);            // clear pending while irq stays high
        // irq_src_prev[0]=1 now, irq_src[0]=1 → no rising edge → no re-trigger
        @(posedge clk); #1;
        chk1("TC22 no re-trigger while irq stays high", meip, 1'b0);
        plic_read_check("TC22b PENDING=0 (no re-trigger)", 24'h001000, 32'd0);

        // Lower then re-raise: edge detected again
        lower_irq(6'b000000);
        raise_irq(6'b000001);
        chk1("TC23 re-triggered after low→high",      meip, 1'b1);
        plic_complete(3'd1);

        //==========================================================
        // Group 12: All 6 priority registers write/read
        //==========================================================
        $display("");
        $display("-- Group 12: All priority registers --");

        lower_irq(6'b000000);
        do_reset;
        plic_write(24'h000004, 32'd7);  // PRI[1]=7
        plic_write(24'h000008, 32'd6);  // PRI[2]=6
        plic_write(24'h00000C, 32'd5);  // PRI[3]=5
        plic_write(24'h000010, 32'd4);  // PRI[4]=4
        plic_write(24'h000014, 32'd3);  // PRI[5]=3
        plic_write(24'h000018, 32'd2);  // PRI[6]=2
        plic_read_check("TC24a PRI[1]=7", 24'h000004, 32'd7);
        plic_read_check("TC24b PRI[3]=5", 24'h00000C, 32'd5);
        plic_read_check("TC24c PRI[6]=2", 24'h000018, 32'd2);

        // ENABLE all 6 sources: bits[6:1]=1 → value = 0b01111110 = 0x7E = 126
        plic_write(24'h002000, 32'h7E);
        plic_read_check("TC25 ENABLE=0x7E (all 6 sources)", 24'h002000, 32'h7E);

        //==========================================================
        // Summary
        //==========================================================
        $display("");
        $display("=== PLIC UNIT: %0d/%0d PASS ===", pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) $display("ALL PASS");
        else               $display("%0d FAIL", fail_cnt);
        $finish;
    end

endmodule
