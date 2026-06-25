`timescale 1ns/1ps
module tb_irq_sync2ff;

    logic clk, rst_n, d, q;

    irq_sync2ff dut (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (d),
        .q     (q)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;  // 1GHz

    int pass_cnt = 0, fail_cnt = 0;

    task check(input string msg, input logic exp, input logic got);
        if (got === exp) begin
            $display("  PASS  %-42s exp=%b got=%b", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-42s exp=%b got=%b", msg, exp, got);
            fail_cnt++;
        end
    endtask

    initial begin
        $display("=== tb_irq_sync2ff ===");
        rst_n = 0; d = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // T1: After reset, q = 0
        @(negedge clk);
        check("T1: q=0 after reset", 1'b0, q);

        // T2-T3: d=1 → q stays 0 after 1 cycle
        d = 1;
        @(posedge clk); @(negedge clk);
        check("T2: q=0 after 1 cycle (ff1 captures)", 1'b0, q);

        // T3: q=1 after 2nd cycle
        @(posedge clk); @(negedge clk);
        check("T3: q=1 after 2 cycles", 1'b1, q);

        // T4-T5: d=0 → q goes low after 2 cycles
        d = 0;
        @(posedge clk); @(negedge clk);
        check("T4: q=1 still (1 cycle after d=0)", 1'b1, q);
        @(posedge clk); @(negedge clk);
        check("T5: q=0 after 2 cycles", 1'b0, q);

        // T6: Single-cycle pulse — d=1 for exactly one posedge sampling window
        // Set d=1 at negedge, clear d=0 at NEXT negedge to avoid posedge race.
        d = 1;
        @(posedge clk); @(negedge clk);  // posedge: ff1←1, q←0; check not here
        d = 0;                           // clear at negedge (safe: 0.5ns before next posedge)
        @(posedge clk); @(negedge clk);  // posedge: ff1←0, q←1
        check("T6: q=1 from 1-cycle pulse", 1'b1, q);
        @(posedge clk); @(negedge clk);  // posedge: ff1←0, q←0
        check("T7: q=0 after pulse clears", 1'b0, q);

        // T8: Async reset de-asserts mid-operation
        d = 1;
        @(posedge clk);  // ff1=1
        @(negedge clk);
        rst_n = 0;       // async assert: ff1, q both go 0 immediately
        #0.1;
        check("T8: q=0 immediately on async rst", 1'b0, q);
        @(negedge clk); rst_n = 1;
        d = 0;
        @(posedge clk); @(negedge clk);
        check("T9: q=0 after rst released, d=0", 1'b0, q);

        // T10: Sustained high d → q stays high
        d = 1;
        repeat(5) @(posedge clk);
        @(negedge clk);
        check("T10: q=1 sustained", 1'b1, q);

        $display("===========================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("tb_irq_sync2ff: ALL PASSED");
        else               $display("tb_irq_sync2ff: SOME FAILED");
        $finish;
    end
endmodule
