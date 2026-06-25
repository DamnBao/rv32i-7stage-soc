`timescale 1ns/1ps
// Unit test for gpio_sfr (wraps axi_sfr + GPIO edge-detect logic).
// Drives AXI-Lite transactions directly; checks gpio_out, irq, and read-back values.
module tb_gpio_sfr;

    // ---------- DUT signals ----------
    logic        clk, rst_n;

    // AXI-Lite
    logic [31:0] AWADDR;  logic [2:0] AWPROT;  logic AWVALID, AWREADY;
    logic [31:0] WDATA;   logic [3:0] WSTRB;   logic WVALID,  WREADY;
    logic [1:0]  BRESP;   logic BVALID, BREADY;
    logic [31:0] ARADDR;  logic [2:0] ARPROT;  logic ARVALID, ARREADY;
    logic [31:0] RDATA;   logic [1:0] RRESP;   logic RVALID,  RREADY;

    // GPIO
    logic [31:0] gpio_in;
    logic [31:0] gpio_out;
    logic        irq;

    gpio_sfr dut (
        .clk     (clk),     .rst_n   (rst_n),
        .AWADDR  (AWADDR),  .AWPROT  (AWPROT),  .AWVALID (AWVALID), .AWREADY (AWREADY),
        .WDATA   (WDATA),   .WSTRB   (WSTRB),   .WVALID  (WVALID),  .WREADY  (WREADY),
        .BRESP   (BRESP),   .BVALID  (BVALID),  .BREADY  (BREADY),
        .ARADDR  (ARADDR),  .ARPROT  (ARPROT),  .ARVALID (ARVALID), .ARREADY (ARREADY),
        .RDATA   (RDATA),   .RRESP   (RRESP),   .RVALID  (RVALID),  .RREADY  (RREADY),
        .gpio_in (gpio_in), .gpio_out(gpio_out), .irq     (irq)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100MHz (10ns) for readability

    int pass_cnt = 0, fail_cnt = 0;

    // SFR register offsets
    localparam OFF_CTRL       = 32'h00;
    localparam OFF_STATUS     = 32'h04;
    localparam OFF_INTR_EN    = 32'h08;
    localparam OFF_INTR_STATE = 32'h0C;
    localparam OFF_INTR_TEST  = 32'h10;
    localparam OFF_DATA0      = 32'h14;
    localparam OFF_DATA1      = 32'h18;
    localparam OFF_PERIPH_ID  = 32'hFC;

    // ---------- AXI write task ----------
    // Drive AW+W simultaneously at negedge; deassert at NEXT negedge to
    // avoid race with always_ff sampling in the same posedge active region.
    task axi_write(input [31:0] addr, data, input [3:0] strb = 4'hF);
        @(negedge clk);
        AWADDR = addr; AWPROT = 0; AWVALID = 1;
        WDATA  = data; WSTRB  = strb; WVALID = 1;
        @(posedge clk);          // AW+W handshake fires; state→WR_RESP (NB)
        @(negedge clk);          // deassert AFTER posedge committed handshake
        AWVALID = 0; WVALID = 0;
        BREADY = 1;
        @(posedge clk);          // BVALID=1, BREADY=1 → B handshake; state→IDLE
        @(negedge clk);
        BREADY = 0;
    endtask

    // ---------- AXI read task ----------
    // Deassert ARVALID at negedge; set RREADY after; sample RDATA at negedge.
    task axi_read(input [31:0] addr, output [31:0] rdata_out);
        @(negedge clk);
        ARADDR = addr; ARPROT = 0; ARVALID = 1;
        @(posedge clk);          // AR handshake fires; state→RD_RESP (NB)
        @(negedge clk);          // deassert AFTER posedge committed handshake
        ARVALID = 0;
        RREADY = 1;
        @(posedge clk);          // RVALID=1, RREADY=1 → R handshake
        @(negedge clk);          // sample at negedge: RDATA stable, rd_idx_r unchanged
        rdata_out = RDATA;
        RREADY = 0;
    endtask

    task check32(input string msg, input [31:0] exp, got);
        if (got === exp) begin
            $display("  PASS  %-44s exp=%08h got=%08h", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-44s exp=%08h got=%08h", msg, exp, got);
            fail_cnt++;
        end
    endtask

    task check1(input string msg, input logic exp, got);
        if (got === exp) begin
            $display("  PASS  %-44s exp=%b got=%b", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-44s exp=%b got=%b", msg, exp, got);
            fail_cnt++;
        end
    endtask

    logic [31:0] rd;

    initial begin
        $display("=== tb_gpio_sfr ===");
        // Init AXI channels
        {AWADDR, AWPROT, AWVALID} = 0;
        {WDATA, WSTRB, WVALID}    = 0;
        BREADY = 0;
        {ARADDR, ARPROT, ARVALID} = 0;
        RREADY = 0;
        gpio_in = 32'd0;

        // Reset
        rst_n = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(2) @(posedge clk);
        @(negedge clk);

        // ------ G1: Reset state ------
        $display("--- G1: Reset state ---");
        check1("T1: irq=0 after reset",        1'b0, irq);
        check32("T2: gpio_out=0 after reset",  32'd0, gpio_out);

        // ------ G2: PERIPH_ID ------
        $display("--- G2: PERIPH_ID ---");
        axi_read(OFF_PERIPH_ID, rd);
        check32("T3: PERIPH_ID=0x47504900", 32'h4750_4900, rd);

        // ------ G3: DATA0 write → gpio_out controlled by DATA1[0] ------
        $display("--- G3: GPIO output ---");
        axi_write(OFF_DATA0, 32'hABCD_EF01);
        check32("T4: gpio_out=0 (DATA1[0]=0 → OE off)", 32'd0, gpio_out);

        axi_write(OFF_DATA1, 32'h0000_0001);  // OE on
        check32("T5: gpio_out=DATA0 when OE=1", 32'hABCD_EF01, gpio_out);

        axi_write(OFF_DATA1, 32'h0000_0000);  // OE off
        check32("T6: gpio_out=0 when OE=0", 32'd0, gpio_out);

        // Read-back DATA0
        axi_read(OFF_DATA0, rd);
        check32("T7: DATA0 read-back", 32'hABCD_EF01, rd);

        // ------ G4: STATUS = gpio_in (bit0 sync'd) ------
        $display("--- G4: STATUS ---");
        gpio_in = 32'h0000_00FE;  // bit0=0
        repeat(4) @(posedge clk);  // let sync settle (3-FF chain)
        axi_read(OFF_STATUS, rd);
        check32("T8: STATUS=gpio_in (bit0=0 sync'd)", 32'h0000_00FE, rd);

        gpio_in = 32'h1234_5679;  // bit0=1
        repeat(4) @(posedge clk);
        axi_read(OFF_STATUS, rd);
        check32("T9: STATUS bit0 sync'd=1", 32'h1234_5679, rd);

        // ------ G5: Edge-detect IRQ ------
        $display("--- G5: Edge-detect IRQ ---");
        gpio_in = 32'd0;
        repeat(4) @(posedge clk);  // let gpio_s2,prev settle to 0
        // W1C-clear any leftover INTR_STATE from G4 gpio_in[0] rising edge
        axi_write(OFF_INTR_STATE, 32'hFFFF_FFFF);

        // Enable interrupt
        axi_write(OFF_INTR_EN, 32'h0000_0001);

        // Verify no IRQ yet (irq is combinational)
        check1("T10: irq=0 before edge", 1'b0, irq);

        // Rising edge on gpio_in[0]:
        //   cycle 1: gpio_s1←1
        //   cycle 2: gpio_s2←1, gpio_prev=0 → irq_src_pulse=1 → INTR_STATE[0]←1
        //   cycle 3+: pulse gone, but INTR_STATE is sticky
        gpio_in[0] = 1'b1;
        repeat(4) @(posedge clk);
        @(negedge clk);
        check1("T11: irq=1 after gpio_in[0] rising edge", 1'b1, irq);

        axi_read(OFF_INTR_STATE, rd);
        check32("T12: INTR_STATE[0]=1", 32'h0000_0001, rd);

        // ------ G6: W1C clear ------
        $display("--- G6: INTR_STATE W1C ---");
        axi_write(OFF_INTR_STATE, 32'h0000_0001);  // clear bit0
        check1("T13: irq=0 after W1C", 1'b0, irq);
        axi_read(OFF_INTR_STATE, rd);
        check32("T14: INTR_STATE=0 after W1C", 32'd0, rd);

        // ------ G7: INTR_TEST force-sets INTR_STATE ------
        $display("--- G7: INTR_TEST ---");
        gpio_in[0] = 1'b0;  // no hw event
        repeat(3) @(posedge clk);
        axi_write(OFF_INTR_TEST, 32'h0000_0001);
        check1("T15: irq=1 via INTR_TEST", 1'b1, irq);
        axi_read(OFF_INTR_STATE, rd);
        check32("T16: INTR_STATE=1 via INTR_TEST", 32'h0000_0001, rd);

        // Clear
        axi_write(OFF_INTR_STATE, 32'h0000_0001);
        check1("T17: irq=0 after clearing INTR_TEST state", 1'b0, irq);

        // ------ G8: IRQ masked when INTR_ENABLE=0 ------
        $display("--- G8: IRQ masking ---");
        axi_write(OFF_INTR_EN, 32'h0000_0000);  // disable
        gpio_in[0] = 1'b1;
        repeat(4) @(posedge clk);
        @(negedge clk);
        check1("T18: irq=0 when INTR_EN=0 despite pending", 1'b0, irq);
        axi_read(OFF_INTR_STATE, rd);
        check32("T19: INTR_STATE set even when masked", 32'h0000_0001, rd);

        // ------ G9: Multiple DATA0/DATA1 write-read ------
        $display("--- G9: DATA write/read ---");
        axi_write(OFF_DATA0, 32'hDEAD_BEEF);
        axi_write(OFF_DATA1, 32'hCAFE_0001);
        axi_read(OFF_DATA0, rd);
        check32("T20: DATA0 read-back", 32'hDEAD_BEEF, rd);
        axi_read(OFF_DATA1, rd);
        check32("T21: DATA1 read-back", 32'hCAFE_0001, rd);
        check32("T22: gpio_out=DATA0 (OE=1)", 32'hDEAD_BEEF, gpio_out);

        $display("===========================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("tb_gpio_sfr: ALL PASSED");
        else               $display("tb_gpio_sfr: SOME FAILED");
        $finish;
    end
endmodule
