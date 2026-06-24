`timescale 1ns/1ps

// Compliance testbench: single-program runner with machine-parseable output.
// Outputs "TEST_PASS" or "TEST_FAIL" for script parsing (scripts/run_one_test.sh).
//
// Halt mechanism: program executes addi x31,x0,1; ebreak  (PASS)
//                              or: addi x31,x0,0; ebreak  (FAIL)
//
// Usage: vvp system/tb_compliance.vvp +HEX=<path> [+DUMP=<vcd_path>]

module tb_compliance;

    logic clk_cpu, clk_ahb, rst_n;

    soc_top u_soc (
        .clk_cpu (clk_cpu),
        .clk_ahb (clk_ahb),
        .rst_n   (rst_n)
    );

    // clk_cpu: 1GHz (1ns period)
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;

    // clk_ahb: 500MHz (2ns period), 0.3ns phase offset
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    string hex_file;
    string vcd_file;

    initial begin
        if (!$value$plusargs("HEX=%s", hex_file))
            $fatal(1, "[tb_compliance] Usage: vvp <vvp> +HEX=<hex_file>");

        if ($value$plusargs("DUMP=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_compliance);
        end

        rst_n = 0;
        $readmemh(hex_file, u_soc.u_imem.mem);
        $display("[INFO] Loaded: %s", hex_file);

        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n = 1;
    end

    // Detect EBREAK, output compliance result
    always @(posedge clk_cpu) begin
        if (rst_n && u_soc.wb_ebreak) begin
            if (u_soc.u_rf.registers[31] == 32'd1) begin
                $display("TEST_PASS");
                $finish(0);
            end else begin
                $display("TEST_FAIL  x31=0x%08X  mepc=0x%08X  mcause=0x%08X",
                         u_soc.u_rf.registers[31],
                         u_soc.u_zicsr.mepc,
                         u_soc.u_zicsr.mcause);
                $finish(1);
            end
        end
    end

    // Timeout watchdog: 200000 cycles
    initial begin
        #200000;
        $display("TEST_FAIL  TIMEOUT — no EBREAK after 200000 cycles");
        $finish(1);
    end

endmodule
