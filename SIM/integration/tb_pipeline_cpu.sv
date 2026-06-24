`timescale 1ns/1ps

// Integration testbench — full SoC (soc_top), CPU pipeline only exercises IMEM+DMEM.
// Halt mechanism: program writes x31=1 (pass) or x31=0 (fail), then executes EBREAK.
// Testbench monitors wb_ebreak in the WB stage, reads x31, then terminates.
//
// Runtime args:
//   +HEX=<path>   (required) hex file to load into IMEM
//   +DUMP=<path>  (optional) enable VCD dump to specified file

module tb_pipeline_cpu;

    logic clk_cpu, clk_ahb, rst_n;

    soc_top u_soc (
        .clk_cpu (clk_cpu),
        .clk_ahb (clk_ahb),
        .rst_n   (rst_n)
    );

    // clk_cpu: 1GHz (1ns period)
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;

    // clk_ahb: 500MHz (2ns period), 0.3ns phase offset to avoid simultaneous edges
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    string hex_file;
    string vcd_file;

    initial begin
        // Must specify program hex
        if (!$value$plusargs("HEX=%s", hex_file))
            $fatal(1, "[tb_pipeline_cpu] Usage: vvp <vvp> +HEX=<hex_file>");

        // Optional VCD
        if ($value$plusargs("DUMP=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_pipeline_cpu);
            $display("[DUMP] Writing waveform to %s", vcd_file);
        end

        // Hold reset, load IMEM while in reset (safe — bypass RTL logic)
        rst_n = 0;
        $readmemh(hex_file, u_soc.u_imem.mem);
        $display("[INFO] Loaded %s", hex_file);

        // 10-cycle reset
        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n = 1;
    end

    // Detect EBREAK at WB stage
    // addi x31,x0,1 commits at cycle N; ebreak commits at cycle N+1.
    // At cycle N+1's posedge: registers[31] is already 1 (written in cycle N).
    always @(posedge clk_cpu) begin
        if (rst_n && u_soc.wb_ebreak) begin
            if (u_soc.u_rf.registers[31] == 32'd1) begin
                $display("PASS  [%s]", hex_file);
            end else begin
                $fatal(1, "FAIL  [%s]  x31=0x%08X (expected 1)",
                       hex_file, u_soc.u_rf.registers[31]);
            end
            $finish;
        end
    end

    // Timeout: 200000 cycles @ 1GHz
    initial begin
        #200000;
        $fatal(1, "[TIMEOUT] %s — no EBREAK after 200000 cycles", hex_file);
    end

endmodule
