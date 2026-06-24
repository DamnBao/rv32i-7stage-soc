`timescale 1ns/1ps

// System-level batch testbench: runs all programs in sequence with full SoC reset
// between each run, then reports aggregate PASS/FAIL summary.
//
// Covers all 16 programs:
//   Phase 3 (9): arithmetic, forwarding, load_store, branch_jump, csr,
//                ecall, interrupt_msi, interrupt_mei, load_fault
//   Phase 5 (4): axi_sfr, ahb_sfr, axi_irq, ahb_irq
//   Phase 6 (3): rv32i_shifts, rv32i_compare, dmem_endurance
//
// Usage: vvp system/tb_soc_top.vvp

module tb_soc_top;

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

    //=========================================================
    // Program list (hardcoded)
    //=========================================================
    localparam int N_PROGS = 16;

    string programs [0:N_PROGS-1];
    int    pass_cnt, fail_cnt;
    int    cycle_cnt;
    logic  done;

    initial begin
        // Phase 3
        programs[0]  = "programs/prog_arithmetic.hex";
        programs[1]  = "programs/prog_forwarding.hex";
        programs[2]  = "programs/prog_load_store.hex";
        programs[3]  = "programs/prog_branch_jump.hex";
        programs[4]  = "programs/prog_csr.hex";
        programs[5]  = "programs/prog_ecall.hex";
        programs[6]  = "programs/prog_interrupt_msi.hex";
        programs[7]  = "programs/prog_interrupt_mei.hex";
        programs[8]  = "programs/prog_load_fault.hex";
        // Phase 5
        programs[9]  = "programs/prog_axi_sfr.hex";
        programs[10] = "programs/prog_ahb_sfr.hex";
        programs[11] = "programs/prog_axi_irq.hex";
        programs[12] = "programs/prog_ahb_irq.hex";
        // Phase 6
        programs[13] = "programs/prog_rv32i_shifts.hex";
        programs[14] = "programs/prog_rv32i_compare.hex";
        programs[15] = "programs/prog_dmem_endurance.hex";

        pass_cnt = 0;
        fail_cnt = 0;

        $display("=== System Test: %0d programs ===", N_PROGS);
        $display("");

        for (int i = 0; i < N_PROGS; i++) begin

            // ── Reset phase ──
            rst_n = 1'b0;
            // Clear DMEM (64KB = 16384 words) for inter-program isolation
            for (int j = 0; j < 16384; j++)
                u_soc.u_dmem.mem[j] = 32'd0;
            // Load IMEM
            $readmemh(programs[i], u_soc.u_imem.mem);
            // Hold reset for 10 cycles
            repeat(10) @(posedge clk_cpu);
            @(negedge clk_cpu);
            rst_n = 1'b1;

            // ── Run until EBREAK or timeout (200000 cycles) ──
            done = 1'b0;
            for (cycle_cnt = 0; cycle_cnt < 200000 && !done; cycle_cnt++) begin
                @(posedge clk_cpu);
                if (rst_n && u_soc.wb_ebreak)
                    done = 1'b1;
            end

            // ── Record result ──
            if (done) begin
                if (u_soc.u_rf.registers[31] == 32'd1) begin
                    $display("PASS  [%0s]", programs[i]);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("FAIL  [%0s]  x31=0x%08X",
                             programs[i], u_soc.u_rf.registers[31]);
                    fail_cnt = fail_cnt + 1;
                end
            end else begin
                $display("TIMEOUT  [%0s]", programs[i]);
                fail_cnt = fail_cnt + 1;
                rst_n = 1'b0; // abort the stalled program
            end
        end

        // ── Summary ──
        $display("");
        $display("=== SYSTEM TEST: %0d/%0d PASS ===", pass_cnt, N_PROGS);
        if (fail_cnt == 0)
            $display("ALL PASS");
        else
            $display("%0d FAIL", fail_cnt);
        $finish;
    end

endmodule
