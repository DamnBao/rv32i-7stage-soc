`timescale 1ns/1ps
// Unit test for timer_axi: AXI-Lite Timer peripheral.
// Tests: PERIPH_ID, register R/W, compare match, IRQ masking, W1C, INTR_TEST, auto_reload.
// Note: timer_cnt does NOT reset on CTRL=0; only rst_n clears it.
module tb_timer_axi;

    logic        clk, rst_n;

    logic [31:0] AWADDR;  logic [2:0] AWPROT;  logic AWVALID, AWREADY;
    logic [31:0] WDATA;   logic [3:0] WSTRB;   logic WVALID,  WREADY;
    logic [1:0]  BRESP;   logic BVALID, BREADY;
    logic [31:0] ARADDR;  logic [2:0] ARPROT;  logic ARVALID, ARREADY;
    logic [31:0] RDATA;   logic [1:0] RRESP;   logic RVALID,  RREADY;
    logic        irq;

    timer_axi dut (
        .clk(clk), .rst_n(rst_n),
        .AWADDR(AWADDR), .AWPROT(AWPROT), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA),   .WSTRB(WSTRB),   .WVALID(WVALID),   .WREADY(WREADY),
        .BRESP(BRESP),   .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARPROT(ARPROT), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA),   .RRESP(RRESP),   .RVALID(RVALID),   .RREADY(RREADY),
        .irq(irq)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;

    localparam OFF_CTRL       = 32'h00;
    localparam OFF_STATUS     = 32'h04;
    localparam OFF_INTR_EN    = 32'h08;
    localparam OFF_INTR_STATE = 32'h0C;
    localparam OFF_INTR_TEST  = 32'h10;
    localparam OFF_DATA0      = 32'h14;  // PRESCALER
    localparam OFF_DATA1      = 32'h18;  // COMPARE
    localparam OFF_PERIPH_ID  = 32'hFC;

    task axi_write(input [31:0] addr, data);
        @(negedge clk);
        AWADDR = addr; AWPROT = 0; AWVALID = 1;
        WDATA  = data; WSTRB  = 4'hF; WVALID = 1;
        @(posedge clk);
        @(negedge clk);
        AWVALID = 0; WVALID = 0;
        BREADY = 1;
        @(posedge clk);
        @(negedge clk);
        BREADY = 0;
    endtask

    task axi_read(input [31:0] addr, output [31:0] rdata_out);
        @(negedge clk);
        ARADDR = addr; ARPROT = 0; ARVALID = 1;
        @(posedge clk);
        @(negedge clk);
        ARVALID = 0;
        RREADY = 1;
        @(posedge clk);
        @(negedge clk);
        rdata_out = RDATA;
        RREADY = 0;
    endtask

    task do_reset();
        rst_n = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(2) @(posedge clk);
    endtask

    task check32(input string msg, input [31:0] exp, got);
        if (got === exp) begin
            $display("  PASS  %-48s exp=%08h got=%08h", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-48s exp=%08h got=%08h", msg, exp, got);
            fail_cnt++;
        end
    endtask

    task check1(input string msg, input logic exp, got);
        if (got === exp) begin
            $display("  PASS  %-48s exp=%b got=%b", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-48s exp=%b got=%b", msg, exp, got);
            fail_cnt++;
        end
    endtask

    logic [31:0] rd;
    logic [31:0] cnt_before;

    initial begin
        $display("=== tb_timer_axi ===");
        {AWADDR, AWPROT, AWVALID} = 0;
        {WDATA, WSTRB, WVALID}    = 0;
        BREADY = 0;
        {ARADDR, ARPROT, ARVALID} = 0;
        RREADY = 0;

        do_reset();

        // ------ T1: Reset state ------
        $display("--- T1: Reset state ---");
        check1("irq=0 after reset", 1'b0, irq);

        // ------ T2: PERIPH_ID ------
        $display("--- T2: PERIPH_ID ---");
        axi_read(OFF_PERIPH_ID, rd);
        check32("PERIPH_ID=0x5449_4D52 (TIMR)", 32'h5449_4D52, rd);

        // ------ T3: Register write/read ------
        $display("--- T3: Register write/read ---");
        axi_write(OFF_DATA0, 32'd9);
        axi_write(OFF_DATA1, 32'd100);
        axi_read(OFF_DATA0, rd);
        check32("DATA0 (PRESCALER) read-back", 32'd9, rd);
        axi_read(OFF_DATA1, rd);
        check32("DATA1 (COMPARE) read-back", 32'd100, rd);
        axi_write(OFF_CTRL, 32'd3);
        axi_read(OFF_CTRL, rd);
        check32("CTRL read-back (3)", 32'd3, rd);

        // ------ T4: Timer disabled — STATUS stays 0 ------
        $display("--- T4: Timer disabled ---");
        do_reset();
        repeat(20) @(posedge clk);
        axi_read(OFF_STATUS, rd);
        check32("STATUS=0 when disabled", 32'd0, rd);
        check1("irq=0 when disabled", 1'b0, irq);

        // ------ T5: Enable timer, counter advances ------
        $display("--- T5: Timer counts ---");
        // PRESCALER=0 (tick every cycle), COMPARE=50
        axi_write(OFF_DATA0, 32'd0);
        axi_write(OFF_DATA1, 32'd50);
        axi_write(OFF_CTRL, 32'd1);   // enable
        repeat(5) @(posedge clk);
        axi_read(OFF_STATUS, rd);
        // STATUS = timer_cnt; must be > 0 after some cycles
        if (rd > 32'd0)
            begin $display("  PASS  STATUS nonzero after enable: %0d", rd); pass_cnt++; end
        else
            begin $display("  FAIL  STATUS still zero after enable: %0d", rd); fail_cnt++; end

        // ------ T6: Compare match → INTR_STATE set ------
        $display("--- T6: Compare match ---");
        do_reset();
        axi_write(OFF_DATA0, 32'd0);   // PRESCALER=0
        axi_write(OFF_DATA1, 32'd8);   // COMPARE=8
        axi_write(OFF_CTRL, 32'd1);    // enable
        repeat(20) @(posedge clk);
        axi_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE[0]=1 on compare match", 32'd1, rd);

        // ------ T7: IRQ fires when INTR_ENABLE=1 ------
        $display("--- T7: IRQ masking (enable) ---");
        // INTR_STATE[0] is still set from T6; just enable the interrupt
        axi_write(OFF_INTR_EN, 32'd1);
        @(negedge clk);
        check1("irq=1 with INTR_STATE set and INTR_ENABLE=1", 1'b1, irq);

        // ------ T8: IRQ masked when INTR_ENABLE=0 ------
        $display("--- T8: IRQ masked ---");
        axi_write(OFF_INTR_EN, 32'd0);
        @(negedge clk);
        check1("irq=0 with INTR_ENABLE=0 (masked)", 1'b0, irq);

        // ------ T9: W1C clear INTR_STATE ------
        $display("--- T9: W1C ---");
        axi_write(OFF_INTR_EN, 32'd1);  // re-enable to see irq
        @(negedge clk);
        check1("irq=1 before W1C", 1'b1, irq);
        axi_write(OFF_INTR_STATE, 32'h0000_0001);  // W1C bit0
        check1("irq=0 after W1C", 1'b0, irq);
        axi_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE=0 after W1C", 32'd0, rd);

        // ------ T10: INTR_TEST force-sets INTR_STATE ------
        $display("--- T10: INTR_TEST ---");
        axi_write(OFF_CTRL, 32'd0);
        axi_write(OFF_INTR_STATE, 32'hFFFF_FFFF);  // clear
        axi_write(OFF_INTR_EN, 32'd1);
        axi_write(OFF_INTR_TEST, 32'h0000_0001);   // force bit0
        check1("irq=1 via INTR_TEST", 1'b1, irq);
        axi_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE=1 via INTR_TEST", 32'd1, rd);
        // Clear
        axi_write(OFF_INTR_STATE, 32'h0000_0001);
        check1("irq=0 after clearing INTR_TEST state", 1'b0, irq);

        // ------ T11: Auto-reload ------
        $display("--- T11: Auto-reload ---");
        do_reset();
        axi_write(OFF_INTR_EN, 32'd1);
        axi_write(OFF_DATA0, 32'd0);   // PRESCALER=0
        axi_write(OFF_DATA1, 32'd5);   // COMPARE=5
        axi_write(OFF_CTRL, 32'd3);    // enable + auto_reload
        // Wait for two compare cycles (2×6 ticks = 12 + margin)
        repeat(30) @(posedge clk);
        axi_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE[0]=1 after auto_reload match", 32'd1, rd);
        // With auto_reload, STATUS (timer_cnt) should be ≤ COMPARE
        axi_read(OFF_STATUS, rd);
        if (rd <= 32'd5)
            begin $display("  PASS  STATUS=%0d <= COMPARE=5 (auto_reload working)", rd); pass_cnt++; end
        else
            begin $display("  FAIL  STATUS=%0d > COMPARE=5 (auto_reload broken)", rd); fail_cnt++; end

        // ------ T12: Counter without auto_reload passes compare ------
        $display("--- T12: Counter runs past compare (no auto_reload) ---");
        do_reset();
        axi_write(OFF_DATA0, 32'd0);   // PRESCALER=0
        axi_write(OFF_DATA1, 32'd3);   // COMPARE=3
        axi_write(OFF_CTRL, 32'd1);    // enable, NO auto_reload
        repeat(20) @(posedge clk);
        axi_read(OFF_STATUS, rd);
        if (rd > 32'd3)
            begin $display("  PASS  STATUS=%0d > COMPARE=3 (no auto_reload, continues)", rd); pass_cnt++; end
        else
            begin $display("  FAIL  STATUS=%0d should be > 3 without auto_reload", rd); fail_cnt++; end

        // ------ T13: Disable timer mid-run — counter freezes ------
        $display("--- T13: Timer stops on disable ---");
        do_reset();
        axi_write(OFF_DATA0, 32'd0);
        axi_write(OFF_DATA1, 32'd1000);
        axi_write(OFF_CTRL, 32'd1);
        repeat(10) @(posedge clk);
        axi_write(OFF_CTRL, 32'd0);   // disable
        axi_read(OFF_STATUS, rd);
        cnt_before = rd;
        repeat(10) @(posedge clk);
        axi_read(OFF_STATUS, rd);
        check32("Counter frozen after disable", cnt_before, rd);

        // ------ T14: PRESCALER divides clock ------
        $display("--- T14: PRESCALER divides tick rate ---");
        do_reset();
        // PRESCALER=4: tick every 5 cycles; COMPARE=2 fires at 15 cycles
        axi_write(OFF_DATA0, 32'd4);  // PRESCALER=4
        axi_write(OFF_DATA1, 32'd2);  // COMPARE=2
        axi_write(OFF_CTRL, 32'd1);
        // Tick fires at cycle 5 after enable; read at ~cycle 7 (before second tick at 10)
        repeat(3) @(posedge clk);
        axi_read(OFF_STATUS, rd);    // AXI read completes at ~cycle 7
        check32("STATUS=1 after ~7 cycles with PRESCALER=4", 32'd1, rd);
        repeat(15) @(posedge clk);   // > 15 cycles total → compare match at cycle 15
        axi_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE[0]=1 with PRESCALER=4", 32'd1, rd);

        // Done
        $display("--- Summary ---");
        $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TEST_PASS");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
