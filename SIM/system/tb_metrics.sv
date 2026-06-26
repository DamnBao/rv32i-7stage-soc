`timescale 1ns/1ps
//
// Metrics testbench — measures runtime statistics for three programs:
//
//   1. prog_forwarding  → IPC + stall breakdown (load-use, CSR, bus, branch)
//   2. prog_branch_pred → branch-predictor hit rate per test pattern
//   3. prog_ahb_sfr     → per-transaction AHB CDC latency (write + read)
//
// All counters reset per program.  Instruction retirement is counted at the
// EX→MEM1 boundary (when instr_valid_ex=1 && stall_idex=0), which is the
// first point where all instruction types (branch, store, ALU, load, CSR,
// ecall, ebreak) are unambiguously visible.
//
// Signals probed (all hierarchical references into u_soc):
//   u_soc.idex_{branch,jump,mem_read,mem_write,reg_write,csr_we,
//               ecall,ebreak,mret,illegal}
//   u_soc.stall_idex          (= bus_stall_req only)
//   u_soc.u_haz.load_use_stall
//   u_soc.u_haz.csr_use_stall
//   u_soc.bus_stall_req
//   u_soc.bp_mismatch
//
module tb_metrics;

    // ── Clocks & reset ───────────────────────────────────────────────
    logic clk_cpu, clk_ahb, rst_n;
    logic rst_cpu_n_o, rst_ahb_n_o;

    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    // ── AXI slave wires (S0/S1/S2) ───────────────────────────────────
    logic [31:0] axi_S0_AWADDR; logic [2:0] axi_S0_AWPROT;
    logic        axi_S0_AWVALID, axi_S0_AWREADY;
    logic [31:0] axi_S0_WDATA;  logic [3:0] axi_S0_WSTRB;
    logic        axi_S0_WVALID,  axi_S0_WREADY;
    logic [1:0]  axi_S0_BRESP;  logic axi_S0_BVALID, axi_S0_BREADY;
    logic [31:0] axi_S0_ARADDR; logic [2:0] axi_S0_ARPROT;
    logic        axi_S0_ARVALID, axi_S0_ARREADY;
    logic [31:0] axi_S0_RDATA;  logic [1:0] axi_S0_RRESP;
    logic        axi_S0_RVALID,  axi_S0_RREADY, axi_S0_irq;

    logic [31:0] axi_S1_AWADDR; logic [2:0] axi_S1_AWPROT;
    logic        axi_S1_AWVALID, axi_S1_AWREADY;
    logic [31:0] axi_S1_WDATA;  logic [3:0] axi_S1_WSTRB;
    logic        axi_S1_WVALID,  axi_S1_WREADY;
    logic [1:0]  axi_S1_BRESP;  logic axi_S1_BVALID, axi_S1_BREADY;
    logic [31:0] axi_S1_ARADDR; logic [2:0] axi_S1_ARPROT;
    logic        axi_S1_ARVALID, axi_S1_ARREADY;
    logic [31:0] axi_S1_RDATA;  logic [1:0] axi_S1_RRESP;
    logic        axi_S1_RVALID,  axi_S1_RREADY, axi_S1_irq;

    logic [31:0] axi_S2_AWADDR; logic [2:0] axi_S2_AWPROT;
    logic        axi_S2_AWVALID, axi_S2_AWREADY;
    logic [31:0] axi_S2_WDATA;  logic [3:0] axi_S2_WSTRB;
    logic        axi_S2_WVALID,  axi_S2_WREADY;
    logic [1:0]  axi_S2_BRESP;  logic axi_S2_BVALID, axi_S2_BREADY;
    logic [31:0] axi_S2_ARADDR; logic [2:0] axi_S2_ARPROT;
    logic        axi_S2_ARVALID, axi_S2_ARREADY;
    logic [31:0] axi_S2_RDATA;  logic [1:0] axi_S2_RRESP;
    logic        axi_S2_RVALID,  axi_S2_RREADY, axi_S2_irq;

    // ── AHB shared bus ───────────────────────────────────────────────
    logic [31:0] ahb_HADDR_o, ahb_HWDATA_o;
    logic [2:0]  ahb_HSIZE_o;
    logic [1:0]  ahb_HTRANS_o;
    logic        ahb_HWRITE_o;

    logic        ahb_S0_HSEL_o, ahb_S0_HREADY_o;
    logic        ahb_S0_HREADYOUT_i, ahb_S0_HRESP_i, ahb_S0_irq_i;
    logic [31:0] ahb_S0_HRDATA_i;

    logic        ahb_S1_HSEL_o, ahb_S1_HREADY_o;
    logic        ahb_S1_HREADYOUT_i, ahb_S1_HRESP_i, ahb_S1_irq_i;
    logic [31:0] ahb_S1_HRDATA_i;

    logic        ahb_S2_HSEL_o, ahb_S2_HREADY_o;
    logic        ahb_S2_HREADYOUT_i, ahb_S2_HRESP_i, ahb_S2_irq_i;
    logic [31:0] ahb_S2_HRDATA_i;

    // ── SoC + Peripherals ────────────────────────────────────────────
    soc_top u_soc (
        .clk_cpu(clk_cpu), .clk_ahb(clk_ahb), .rst_n(rst_n),
        .rst_cpu_n_o(rst_cpu_n_o), .rst_ahb_n_o(rst_ahb_n_o),
        .axi_S0_AWADDR(axi_S0_AWADDR), .axi_S0_AWPROT(axi_S0_AWPROT),
        .axi_S0_AWVALID(axi_S0_AWVALID), .axi_S0_AWREADY(axi_S0_AWREADY),
        .axi_S0_WDATA(axi_S0_WDATA), .axi_S0_WSTRB(axi_S0_WSTRB),
        .axi_S0_WVALID(axi_S0_WVALID), .axi_S0_WREADY(axi_S0_WREADY),
        .axi_S0_BRESP(axi_S0_BRESP), .axi_S0_BVALID(axi_S0_BVALID), .axi_S0_BREADY(axi_S0_BREADY),
        .axi_S0_ARADDR(axi_S0_ARADDR), .axi_S0_ARPROT(axi_S0_ARPROT),
        .axi_S0_ARVALID(axi_S0_ARVALID), .axi_S0_ARREADY(axi_S0_ARREADY),
        .axi_S0_RDATA(axi_S0_RDATA), .axi_S0_RRESP(axi_S0_RRESP),
        .axi_S0_RVALID(axi_S0_RVALID), .axi_S0_RREADY(axi_S0_RREADY), .axi_S0_irq(axi_S0_irq),
        .axi_S1_AWADDR(axi_S1_AWADDR), .axi_S1_AWPROT(axi_S1_AWPROT),
        .axi_S1_AWVALID(axi_S1_AWVALID), .axi_S1_AWREADY(axi_S1_AWREADY),
        .axi_S1_WDATA(axi_S1_WDATA), .axi_S1_WSTRB(axi_S1_WSTRB),
        .axi_S1_WVALID(axi_S1_WVALID), .axi_S1_WREADY(axi_S1_WREADY),
        .axi_S1_BRESP(axi_S1_BRESP), .axi_S1_BVALID(axi_S1_BVALID), .axi_S1_BREADY(axi_S1_BREADY),
        .axi_S1_ARADDR(axi_S1_ARADDR), .axi_S1_ARPROT(axi_S1_ARPROT),
        .axi_S1_ARVALID(axi_S1_ARVALID), .axi_S1_ARREADY(axi_S1_ARREADY),
        .axi_S1_RDATA(axi_S1_RDATA), .axi_S1_RRESP(axi_S1_RRESP),
        .axi_S1_RVALID(axi_S1_RVALID), .axi_S1_RREADY(axi_S1_RREADY), .axi_S1_irq(axi_S1_irq),
        .axi_S2_AWADDR(axi_S2_AWADDR), .axi_S2_AWPROT(axi_S2_AWPROT),
        .axi_S2_AWVALID(axi_S2_AWVALID), .axi_S2_AWREADY(axi_S2_AWREADY),
        .axi_S2_WDATA(axi_S2_WDATA), .axi_S2_WSTRB(axi_S2_WSTRB),
        .axi_S2_WVALID(axi_S2_WVALID), .axi_S2_WREADY(axi_S2_WREADY),
        .axi_S2_BRESP(axi_S2_BRESP), .axi_S2_BVALID(axi_S2_BVALID), .axi_S2_BREADY(axi_S2_BREADY),
        .axi_S2_ARADDR(axi_S2_ARADDR), .axi_S2_ARPROT(axi_S2_ARPROT),
        .axi_S2_ARVALID(axi_S2_ARVALID), .axi_S2_ARREADY(axi_S2_ARREADY),
        .axi_S2_RDATA(axi_S2_RDATA), .axi_S2_RRESP(axi_S2_RRESP),
        .axi_S2_RVALID(axi_S2_RVALID), .axi_S2_RREADY(axi_S2_RREADY), .axi_S2_irq(axi_S2_irq),
        .ahb_HADDR_o(ahb_HADDR_o), .ahb_HSIZE_o(ahb_HSIZE_o),
        .ahb_HTRANS_o(ahb_HTRANS_o), .ahb_HWRITE_o(ahb_HWRITE_o), .ahb_HWDATA_o(ahb_HWDATA_o),
        .ahb_S0_HSEL_o(ahb_S0_HSEL_o), .ahb_S0_HREADY_o(ahb_S0_HREADY_o),
        .ahb_S0_HREADYOUT_i(ahb_S0_HREADYOUT_i), .ahb_S0_HRDATA_i(ahb_S0_HRDATA_i),
        .ahb_S0_HRESP_i(ahb_S0_HRESP_i), .ahb_S0_irq_i(ahb_S0_irq_i),
        .ahb_S1_HSEL_o(ahb_S1_HSEL_o), .ahb_S1_HREADY_o(ahb_S1_HREADY_o),
        .ahb_S1_HREADYOUT_i(ahb_S1_HREADYOUT_i), .ahb_S1_HRDATA_i(ahb_S1_HRDATA_i),
        .ahb_S1_HRESP_i(ahb_S1_HRESP_i), .ahb_S1_irq_i(ahb_S1_irq_i),
        .ahb_S2_HSEL_o(ahb_S2_HSEL_o), .ahb_S2_HREADY_o(ahb_S2_HREADY_o),
        .ahb_S2_HREADYOUT_i(ahb_S2_HREADYOUT_i), .ahb_S2_HRDATA_i(ahb_S2_HRDATA_i),
        .ahb_S2_HRESP_i(ahb_S2_HRESP_i), .ahb_S2_irq_i(ahb_S2_irq_i)
    );

    axi_sfr u_axi_sfr0 (.clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S0_AWADDR), .AWPROT(axi_S0_AWPROT), .AWVALID(axi_S0_AWVALID), .AWREADY(axi_S0_AWREADY),
        .WDATA(axi_S0_WDATA), .WSTRB(axi_S0_WSTRB), .WVALID(axi_S0_WVALID), .WREADY(axi_S0_WREADY),
        .BRESP(axi_S0_BRESP), .BVALID(axi_S0_BVALID), .BREADY(axi_S0_BREADY),
        .ARADDR(axi_S0_ARADDR), .ARPROT(axi_S0_ARPROT), .ARVALID(axi_S0_ARVALID), .ARREADY(axi_S0_ARREADY),
        .RDATA(axi_S0_RDATA), .RRESP(axi_S0_RRESP), .RVALID(axi_S0_RVALID), .RREADY(axi_S0_RREADY),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(axi_S0_irq));

    axi_sfr u_axi_sfr1 (.clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S1_AWADDR), .AWPROT(axi_S1_AWPROT), .AWVALID(axi_S1_AWVALID), .AWREADY(axi_S1_AWREADY),
        .WDATA(axi_S1_WDATA), .WSTRB(axi_S1_WSTRB), .WVALID(axi_S1_WVALID), .WREADY(axi_S1_WREADY),
        .BRESP(axi_S1_BRESP), .BVALID(axi_S1_BVALID), .BREADY(axi_S1_BREADY),
        .ARADDR(axi_S1_ARADDR), .ARPROT(axi_S1_ARPROT), .ARVALID(axi_S1_ARVALID), .ARREADY(axi_S1_ARREADY),
        .RDATA(axi_S1_RDATA), .RRESP(axi_S1_RRESP), .RVALID(axi_S1_RVALID), .RREADY(axi_S1_RREADY),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(axi_S1_irq));

    axi_sfr u_axi_sfr2 (.clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S2_AWADDR), .AWPROT(axi_S2_AWPROT), .AWVALID(axi_S2_AWVALID), .AWREADY(axi_S2_AWREADY),
        .WDATA(axi_S2_WDATA), .WSTRB(axi_S2_WSTRB), .WVALID(axi_S2_WVALID), .WREADY(axi_S2_WREADY),
        .BRESP(axi_S2_BRESP), .BVALID(axi_S2_BVALID), .BREADY(axi_S2_BREADY),
        .ARADDR(axi_S2_ARADDR), .ARPROT(axi_S2_ARPROT), .ARVALID(axi_S2_ARVALID), .ARREADY(axi_S2_ARREADY),
        .RDATA(axi_S2_RDATA), .RRESP(axi_S2_RRESP), .RVALID(axi_S2_RVALID), .RREADY(axi_S2_RREADY),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(axi_S2_irq));

    ahb_sfr u_ahb_sfr0 (.clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S0_HSEL_o), .HREADY(ahb_S0_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S0_HRDATA_i), .HREADYOUT(ahb_S0_HREADYOUT_i), .HRESP(ahb_S0_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S0_irq_i));

    ahb_sfr u_ahb_sfr1 (.clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S1_HSEL_o), .HREADY(ahb_S1_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S1_HRDATA_i), .HREADYOUT(ahb_S1_HREADYOUT_i), .HRESP(ahb_S1_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S1_irq_i));

    ahb_sfr u_ahb_sfr2 (.clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S2_HSEL_o), .HREADY(ahb_S2_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S2_HRDATA_i), .HREADYOUT(ahb_S2_HREADYOUT_i), .HRESP(ahb_S2_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S2_irq_i));

    // ================================================================
    // Metric counters  (reset via task reset_counters)
    // ================================================================

    // -- instruction retirement signal (EX stage, non-stalled)
    // An instruction is counted retired when it exits EX (advances to MEM1).
    // stall_idex=1 freezes EX → same instruction would be counted again next cycle.
    wire instr_valid_ex = |{u_soc.idex_mem_read,  u_soc.idex_mem_write,
                            u_soc.idex_reg_write,  u_soc.idex_branch,
                            u_soc.idex_jump,        u_soc.idex_csr_we,
                            u_soc.idex_ecall,       u_soc.idex_ebreak,
                            u_soc.idex_mret,        u_soc.idex_illegal};

    integer total_cycles;
    integer instr_retired;
    integer stall_load_use_cycles;
    integer stall_csr_cycles;
    integer stall_bus_cycles;
    integer bp_total_branches;
    integer bp_mispredictions;

    // AHB latency tracking (used during prog_ahb_sfr only)
    logic   bus_stall_prev;
    integer ahb_stall_start;
    integer ahb_txn_count;
    integer ahb_lat_min;
    integer ahb_lat_max;
    integer ahb_lat_total;
    logic   measure_ahb;   // enabled only for prog_ahb_sfr run

    logic running;

    task reset_counters;
        total_cycles         = 0;
        instr_retired        = 0;
        stall_load_use_cycles = 0;
        stall_csr_cycles     = 0;
        stall_bus_cycles     = 0;
        bp_total_branches    = 0;
        bp_mispredictions    = 0;
        ahb_txn_count        = 0;
        ahb_lat_min          = 99999;
        ahb_lat_max          = 0;
        ahb_lat_total        = 0;
        ahb_stall_start      = 0;
        bus_stall_prev       = 0;
        measure_ahb          = 0;
        running              = 0;
    endtask

    always @(posedge clk_cpu) begin
        if (running) begin
            total_cycles = total_cycles + 1;

            // Instruction retirement at EX boundary
            if (instr_valid_ex && !u_soc.stall_idex)
                instr_retired = instr_retired + 1;

            // Stall type breakdown (mutually exclusive in most cycles;
            // bus_stall wins: if bus_stall_req=1, load_use/csr_use are not active)
            if (u_soc.u_haz.load_use_stall)
                stall_load_use_cycles = stall_load_use_cycles + 1;
            if (u_soc.u_haz.csr_use_stall)
                stall_csr_cycles = stall_csr_cycles + 1;
            if (u_soc.bus_stall_req)
                stall_bus_cycles = stall_bus_cycles + 1;

            // Branch predictor: count at EX (non-stalled) to avoid double-count
            if ((u_soc.idex_branch | u_soc.idex_jump) && !u_soc.stall_idex)
                bp_total_branches = bp_total_branches + 1;
            // Mispredictions: suppress during bus stall (EX frozen → same branch repeats)
            if (u_soc.bp_mismatch && !u_soc.bus_stall_req)
                bp_mispredictions = bp_mispredictions + 1;

            // AHB latency: detect rising/falling edge of bus_stall_req.
            // bus_stall_prev must be read BEFORE updating so edge detection works.
            if (measure_ahb) begin
                if (!bus_stall_prev && u_soc.bus_stall_req) begin
                    // rising edge: stall begins
                    ahb_stall_start = total_cycles;
                end
                if (bus_stall_prev && !u_soc.bus_stall_req) begin
                    // falling edge: stall ends — measure duration
                    ahb_lat_this  = total_cycles - ahb_stall_start;
                    ahb_txn_count = ahb_txn_count + 1;
                    ahb_lat_total = ahb_lat_total + ahb_lat_this;
                    if (ahb_lat_this < ahb_lat_min) ahb_lat_min = ahb_lat_this;
                    if (ahb_lat_this > ahb_lat_max) ahb_lat_max = ahb_lat_this;
                end
                bus_stall_prev = u_soc.bus_stall_req;  // update AFTER edge check
            end
        end
    end

    // ================================================================
    // Helper: run one program and return whether it PASSed
    // ================================================================
    integer run_cycles;
    logic   run_done;
    integer ahb_lat_this;  // per-transaction latency scratch

    task run_program(input string hexfile);
        rst_n  = 1'b0;
        for (int j = 0; j < 16384; j++) u_soc.u_dmem.mem[j] = 32'd0;
        $readmemh(hexfile, u_soc.u_imem.mem);
        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n   = 1'b1;
        running = 1;

        run_done = 0;
        for (run_cycles = 0; run_cycles < 500000 && !run_done; run_cycles++) begin
            @(posedge clk_cpu);
            if (rst_n && u_soc.wb_ebreak)
                run_done = 1;
        end
        running = 0;

        if (!run_done)
            $display("  WARNING: program did not reach EBREAK (timeout)");
        else if (u_soc.u_rf.registers[31] !== 32'd1)
            $display("  WARNING: program FAILED (x31=0x%08X)",
                     u_soc.u_rf.registers[31]);
    endtask

    // ================================================================
    // Main
    // ================================================================
    initial begin
        reset_counters();
        $display("");
        $display("================================================================");
        $display("  Pipeline Metrics Report");
        $display("================================================================");

        // ============================================================
        // 1. IPC + Stall breakdown — prog_forwarding
        //    Arithmetic-heavy program; exercises all 4 forwarding paths.
        //    Minimal stalls expected (NOP gaps force WB forwarding but
        //    no real load-use; branch-jump uses bne which mostly not-taken).
        // ============================================================
        $display("");
        $display("--- [1/3] prog_forwarding : IPC + Stall Breakdown -----");
        reset_counters();
        run_program("programs/prog_forwarding.hex");

        $display("  Total cycles     : %0d", total_cycles);
        $display("  Instr retired    : %0d  (counted at EX exit)", instr_retired);
        if (instr_retired > 0)
            $display("  CPI              : %.3f",
                     real'(total_cycles) / real'(instr_retired));
        else
            $display("  CPI              : N/A");
        $display("  Stalls load-use  : %0d cycles", stall_load_use_cycles);
        $display("  Stalls CSR-use   : %0d cycles", stall_csr_cycles);
        $display("  Stalls bus (AXI/AHB): %0d cycles", stall_bus_cycles);
        $display("  Branch flushes   : %0d events (x2 penalty each)",
                 bp_mispredictions);
        begin
            integer total_stall;
            total_stall = stall_load_use_cycles + stall_csr_cycles
                        + stall_bus_cycles + bp_mispredictions * 2;
            $display("  Total stall+flush: %0d cycles (%.1f%% of runtime)",
                     total_stall,
                     real'(total_stall) * 100.0 / real'(total_cycles));
        end

        // ============================================================
        // 2. Branch predictor hit rate — prog_branch_pred
        //    4 test patterns: tight loop, JAL BTB, nested loops,
        //    alternating branch.  Steady-state hit rate expected ~85-90%.
        // ============================================================
        $display("");
        $display("--- [2/3] prog_branch_pred : Branch Predictor Hit Rate --");
        $display("  (Patterns: tight loop, JAL BTB, nested loops, alternating)");
        $display("  Note: Test 4 alternating T/NT is adversarial for 2-bit predictor.");
        reset_counters();
        run_program("programs/prog_branch_pred.hex");

        $display("  Total cycles          : %0d", total_cycles);
        $display("  Instr retired         : %0d", instr_retired);
        $display("  Branches + jumps      : %0d", bp_total_branches);
        $display("  Mispredictions        : %0d", bp_mispredictions);
        if (bp_total_branches > 0) begin
            $display("  Hit rate              : %.1f%%",
                     (real'(bp_total_branches - bp_mispredictions)
                      / real'(bp_total_branches)) * 100.0);
            $display("  Miss rate             : %.1f%%",
                     real'(bp_mispredictions)
                     / real'(bp_total_branches) * 100.0);
            $display("  Cycles saved vs always-miss: %0d  (%.1f%%)",
                     (bp_total_branches - bp_mispredictions) * 2,
                     real'((bp_total_branches - bp_mispredictions) * 2)
                     / real'(total_cycles) * 100.0);
        end else
            $display("  (no branches detected)");

        // ============================================================
        // 3. AHB CDC latency — prog_ahb_sfr
        //    Writes then reads 3 AHB SFR slaves.  Every sw/lw to 0x3xxx
        //    triggers a full CDC round-trip: push req FIFO → 2-FF sync
        //    (AHB domain) → AHB transaction → push resp FIFO → 2-FF sync
        //    (CPU domain).  All bus_stall_req events in this program are
        //    AHB (no AXI accesses in prog_ahb_sfr).
        // ============================================================
        $display("");
        $display("--- [3/3] prog_ahb_sfr : AHB CDC Transaction Latency ---");
        reset_counters();
        measure_ahb = 1;
        run_program("programs/prog_ahb_sfr.hex");

        $display("  Total cycles          : %0d", total_cycles);
        $display("  Instr retired         : %0d", instr_retired);
        if (instr_retired > 0)
            $display("  CPI (incl. bus stall) : %.3f",
                     real'(total_cycles) / real'(instr_retired));
        $display("  Bus stall cycles total: %0d", stall_bus_cycles);
        $display("  AHB transactions      : %0d", ahb_txn_count);
        if (ahb_txn_count > 0) begin
            $display("  Latency min           : %0d CPU cycles", ahb_lat_min);
            $display("  Latency max           : %0d CPU cycles", ahb_lat_max);
            $display("  Latency avg           : %.1f CPU cycles",
                     real'(ahb_lat_total) / real'(ahb_txn_count));
            $display("  Breakdown: reqFIFO(1cpu) + 2FFsync-req(2ahb) +");
            $display("   AHB_xact(2ahb) + 2FFsync-resp(2ahb) + detect(1cpu)");
            $display("   = 6 AHB cycles = 12 CPU cycles (2:1 ratio), best-case ~9");
        end else
            $display("  (no AHB transactions detected — check measure_ahb logic)");

        $display("");
        $display("================================================================");
        $display("  Metrics collection complete");
        $display("================================================================");
        $finish;
    end

endmodule
