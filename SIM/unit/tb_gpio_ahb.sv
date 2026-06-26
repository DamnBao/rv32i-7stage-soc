`timescale 1ns/1ps
// Unit test for gpio_ahb: AHB-Lite GPIO peripheral.
// Drives AHB-Lite transactions directly (no CDC); checks gpio_out, STATUS, edge IRQ.
module tb_gpio_ahb;

    logic        clk_ahb, rst_ahb_n;

    // AHB-Lite
    logic        HSEL;
    logic        HREADY;
    logic [31:0] HADDR;
    logic [1:0]  HTRANS;
    logic        HWRITE;
    logic [31:0] HWDATA;
    logic [31:0] HRDATA;
    logic        HREADYOUT;
    logic        HRESP;

    // GPIO
    logic [31:0] gpio_in;
    logic [31:0] gpio_out;
    logic        irq;

    gpio_ahb dut (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n),
        .HSEL(HSEL), .HREADY(HREADY), .HADDR(HADDR), .HTRANS(HTRANS),
        .HWRITE(HWRITE), .HWDATA(HWDATA),
        .HRDATA(HRDATA), .HREADYOUT(HREADYOUT), .HRESP(HRESP),
        .gpio_in(gpio_in), .gpio_out(gpio_out), .irq(irq)
    );

    initial clk_ahb = 0;
    always #5 clk_ahb = ~clk_ahb;

    int pass_cnt = 0, fail_cnt = 0;

    localparam HTRANS_IDLE  = 2'b00;
    localparam HTRANS_NONSEQ = 2'b10;

    localparam OFF_CTRL       = 32'h00;
    localparam OFF_STATUS     = 32'h04;
    localparam OFF_INTR_EN    = 32'h08;
    localparam OFF_INTR_STATE = 32'h0C;
    localparam OFF_INTR_TEST  = 32'h10;
    localparam OFF_DATA0      = 32'h14;
    localparam OFF_DATA1      = 32'h18;
    localparam OFF_DATA2      = 32'h1C;
    localparam OFF_PERIPH_ID  = 32'hFC;

    // AHB write: address phase, then data phase (non-pipelined)
    task ahb_write(input [31:0] addr, data);
        @(negedge clk_ahb);
        HSEL   = 1; HREADY = 1;
        HTRANS = HTRANS_NONSEQ; HWRITE = 1; HADDR = addr;
        @(posedge clk_ahb);          // address phase sampled
        @(negedge clk_ahb);
        HWDATA = data;
        HTRANS = HTRANS_IDLE; HSEL = 0;
        @(posedge clk_ahb);          // data phase applied
        @(negedge clk_ahb);
    endtask

    // AHB read: address phase, then sample HRDATA in data phase
    task ahb_read(input [31:0] addr, output [31:0] rdata_out);
        @(negedge clk_ahb);
        HSEL   = 1; HREADY = 1;
        HTRANS = HTRANS_NONSEQ; HWRITE = 0; HADDR = addr;
        @(posedge clk_ahb);          // address phase sampled → addr_ph_idx captured
        @(negedge clk_ahb);          // HRDATA valid (comb from addr_ph_idx)
        rdata_out = HRDATA;
        HTRANS = HTRANS_IDLE; HSEL = 0; HWRITE = 0;
        @(posedge clk_ahb);
        @(negedge clk_ahb);
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

    initial begin
        $display("=== tb_gpio_ahb ===");
        HSEL = 0; HREADY = 1; HTRANS = HTRANS_IDLE;
        HWRITE = 0; HADDR = 0; HWDATA = 0;
        gpio_in = 32'd0;

        rst_ahb_n = 0;
        repeat(4) @(posedge clk_ahb);
        @(negedge clk_ahb); rst_ahb_n = 1;
        repeat(2) @(posedge clk_ahb);

        // ------ G1: Reset state ------
        $display("--- G1: Reset state ---");
        check1("irq=0 after reset",       1'b0, irq);
        check32("gpio_out=0 after reset", 32'd0, gpio_out);

        // ------ G2: PERIPH_ID ------
        $display("--- G2: PERIPH_ID ---");
        ahb_read(OFF_PERIPH_ID, rd);
        check32("PERIPH_ID=0x47504941 (GPIA)", 32'h4750_4941, rd);

        // ------ G3: DATA0 write → gpio_out controlled by DATA1[0] ------
        $display("--- G3: gpio_out control ---");
        ahb_write(OFF_DATA0, 32'hDEAD_BEEF);
        check32("gpio_out=0 (DATA1[0]=0, OE off)", 32'd0, gpio_out);
        ahb_write(OFF_DATA1, 32'h0000_0001);  // OE on
        check32("gpio_out=DATA0 when OE=1", 32'hDEAD_BEEF, gpio_out);
        ahb_write(OFF_DATA1, 32'h0000_0000);  // OE off
        check32("gpio_out=0 when OE=0", 32'd0, gpio_out);

        // ------ G4: DATA0 read-back ------
        $display("--- G4: DATA0 read-back ---");
        ahb_read(OFF_DATA0, rd);
        check32("DATA0 read-back = 0xDEAD_BEEF", 32'hDEAD_BEEF, rd);

        // ------ G5: STATUS = sync'd gpio_in ------
        $display("--- G5: STATUS = sync'd gpio_in ---");
        gpio_in = 32'h0000_0055;
        repeat(4) @(posedge clk_ahb);  // 3-FF sync: s1, s2, prev — need 3 cycles
        ahb_read(OFF_STATUS, rd);
        check32("STATUS=0x55 after sync settle", 32'h0000_0055, rd);

        // ------ G6: Rising-edge detect → INTR_STATE ------
        $display("--- G6: Rising edge detect ---");
        // Start with gpio_in[0]=0, let settle
        gpio_in = 32'd0;
        repeat(5) @(posedge clk_ahb);
        // Clear any stale INTR_STATE
        ahb_write(OFF_INTR_STATE, 32'hFFFF_FFFF);
        ahb_write(OFF_INTR_EN, 32'd1);
        check1("irq=0 before rising edge", 1'b0, irq);
        // Rising edge on gpio_in[0]
        gpio_in[0] = 1'b1;
        repeat(5) @(posedge clk_ahb);
        @(negedge clk_ahb);
        check1("irq=1 after gpio_in[0] rising edge", 1'b1, irq);
        ahb_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE[0]=1 on rising edge", 32'd1, rd);

        // ------ G7: W1C clear ------
        $display("--- G7: W1C ---");
        ahb_write(OFF_INTR_STATE, 32'h0000_0001);
        check1("irq=0 after W1C", 1'b0, irq);
        ahb_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE=0 after W1C", 32'd0, rd);

        // ------ G8: IRQ masked when INTR_ENABLE=0 ------
        $display("--- G8: IRQ masking ---");
        // gpio_in[0] is high (from G6); clear it and generate rising edge again
        gpio_in[0] = 1'b0;
        repeat(5) @(posedge clk_ahb);
        ahb_write(OFF_INTR_STATE, 32'hFFFF_FFFF);  // clear
        ahb_write(OFF_INTR_EN, 32'd0);              // mask
        gpio_in[0] = 1'b1;                          // rising edge
        repeat(5) @(posedge clk_ahb);
        @(negedge clk_ahb);
        check1("irq=0 with INTR_EN=0 (masked)", 1'b0, irq);
        // But INTR_STATE should still be set
        ahb_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE[0]=1 even when masked", 32'd1, rd);

        // ------ G9: INTR_TEST ------
        $display("--- G9: INTR_TEST ---");
        gpio_in = 32'd0;
        repeat(5) @(posedge clk_ahb);
        ahb_write(OFF_INTR_STATE, 32'hFFFF_FFFF);
        ahb_write(OFF_INTR_EN, 32'd1);
        ahb_write(OFF_INTR_TEST, 32'h0000_0001);
        check1("irq=1 via INTR_TEST", 1'b1, irq);
        ahb_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE=1 via INTR_TEST", 32'd1, rd);
        ahb_write(OFF_INTR_STATE, 32'h0000_0001);
        check1("irq=0 after clearing INTR_TEST", 1'b0, irq);

        // ------ G10: Falling edge detect ------
        $display("--- G10: Falling edge detect ---");
        // Set edge_type=1 (falling), gpio_in[0]=1 to start
        gpio_in = 32'd0; repeat(5) @(posedge clk_ahb);
        ahb_write(OFF_DATA2, 32'h0000_0001);    // edge_type=1 (falling)
        ahb_write(OFF_INTR_STATE, 32'hFFFF_FFFF);
        ahb_write(OFF_INTR_EN, 32'd1);
        gpio_in[0] = 1'b1;
        repeat(5) @(posedge clk_ahb);           // let gpio_in[0]=1 settle
        ahb_write(OFF_INTR_STATE, 32'hFFFF_FFFF); // clear any rising-edge artifacts
        // Now falling edge:
        gpio_in[0] = 1'b0;
        repeat(5) @(posedge clk_ahb);
        @(negedge clk_ahb);
        check1("irq=1 on falling edge (DATA2[0]=1)", 1'b1, irq);
        ahb_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE[0]=1 on falling edge", 32'd1, rd);

        // ------ G11: No spurious IRQ when gpio_in stable ------
        $display("--- G11: No spurious IRQ ---");
        ahb_write(OFF_DATA2, 32'd0);             // back to rising
        gpio_in = 32'hAAAA_AAAA;                 // stable non-zero
        repeat(5) @(posedge clk_ahb);
        ahb_write(OFF_INTR_STATE, 32'hFFFF_FFFF);
        repeat(10) @(posedge clk_ahb);
        ahb_read(OFF_INTR_STATE, rd);
        check32("INTR_STATE=0 when gpio_in stable", 32'd0, rd);

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
