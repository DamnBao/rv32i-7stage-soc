`timescale 1ns/1ps

// System-level batch testbench: runs all programs in sequence with full SoC reset
// between each run, then reports aggregate PASS/FAIL summary.
//
// Covers all 17 programs:
//   Phase 3 (9): arithmetic, forwarding, load_store, branch_jump, csr,
//                ecall, interrupt_msi, interrupt_mei, load_fault
//   Phase 5 (4): axi_sfr, ahb_sfr, axi_irq, ahb_irq
//   Phase 6 (3): rv32i_shifts, rv32i_compare, dmem_endurance
//   Phase 7 (1): plic_basic (PLIC claim/complete flow)
//
// Usage: vvp system/tb_soc_top.vvp

module tb_soc_top;

    logic clk_cpu, clk_ahb, rst_n;
    logic rst_cpu_n_o, rst_ahb_n_o;

    // ── AXI Slave 0 ──────────────────────────────────────────────────────
    logic [31:0] axi_S0_AWADDR; logic [2:0] axi_S0_AWPROT;
    logic        axi_S0_AWVALID, axi_S0_AWREADY;
    logic [31:0] axi_S0_WDATA;  logic [3:0] axi_S0_WSTRB;
    logic        axi_S0_WVALID,  axi_S0_WREADY;
    logic [1:0]  axi_S0_BRESP;  logic axi_S0_BVALID, axi_S0_BREADY;
    logic [31:0] axi_S0_ARADDR; logic [2:0] axi_S0_ARPROT;
    logic        axi_S0_ARVALID, axi_S0_ARREADY;
    logic [31:0] axi_S0_RDATA;  logic [1:0] axi_S0_RRESP;
    logic        axi_S0_RVALID,  axi_S0_RREADY, axi_S0_irq;

    // ── AXI Slave 1 ──────────────────────────────────────────────────────
    logic [31:0] axi_S1_AWADDR; logic [2:0] axi_S1_AWPROT;
    logic        axi_S1_AWVALID, axi_S1_AWREADY;
    logic [31:0] axi_S1_WDATA;  logic [3:0] axi_S1_WSTRB;
    logic        axi_S1_WVALID,  axi_S1_WREADY;
    logic [1:0]  axi_S1_BRESP;  logic axi_S1_BVALID, axi_S1_BREADY;
    logic [31:0] axi_S1_ARADDR; logic [2:0] axi_S1_ARPROT;
    logic        axi_S1_ARVALID, axi_S1_ARREADY;
    logic [31:0] axi_S1_RDATA;  logic [1:0] axi_S1_RRESP;
    logic        axi_S1_RVALID,  axi_S1_RREADY, axi_S1_irq;

    // ── AXI Slave 2 ──────────────────────────────────────────────────────
    logic [31:0] axi_S2_AWADDR; logic [2:0] axi_S2_AWPROT;
    logic        axi_S2_AWVALID, axi_S2_AWREADY;
    logic [31:0] axi_S2_WDATA;  logic [3:0] axi_S2_WSTRB;
    logic        axi_S2_WVALID,  axi_S2_WREADY;
    logic [1:0]  axi_S2_BRESP;  logic axi_S2_BVALID, axi_S2_BREADY;
    logic [31:0] axi_S2_ARADDR; logic [2:0] axi_S2_ARPROT;
    logic        axi_S2_ARVALID, axi_S2_ARREADY;
    logic [31:0] axi_S2_RDATA;  logic [1:0] axi_S2_RRESP;
    logic        axi_S2_RVALID,  axi_S2_RREADY, axi_S2_irq;

    // ── AHB shared bus ───────────────────────────────────────────────────
    logic [31:0] ahb_HADDR_o, ahb_HWDATA_o;
    logic [2:0]  ahb_HSIZE_o;
    logic [1:0]  ahb_HTRANS_o;
    logic        ahb_HWRITE_o;

    // ── AHB Slave 0 ──────────────────────────────────────────────────────
    logic        ahb_S0_HSEL_o, ahb_S0_HREADY_o;
    logic        ahb_S0_HREADYOUT_i, ahb_S0_HRESP_i, ahb_S0_irq_i;
    logic [31:0] ahb_S0_HRDATA_i;

    // ── AHB Slave 1 ──────────────────────────────────────────────────────
    logic        ahb_S1_HSEL_o, ahb_S1_HREADY_o;
    logic        ahb_S1_HREADYOUT_i, ahb_S1_HRESP_i, ahb_S1_irq_i;
    logic [31:0] ahb_S1_HRDATA_i;

    // ── AHB Slave 2 ──────────────────────────────────────────────────────
    logic        ahb_S2_HSEL_o, ahb_S2_HREADY_o;
    logic        ahb_S2_HREADYOUT_i, ahb_S2_HRESP_i, ahb_S2_irq_i;
    logic [31:0] ahb_S2_HRDATA_i;

    // ── SoC Top ──────────────────────────────────────────────────────────
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
        .axi_S0_RVALID(axi_S0_RVALID), .axi_S0_RREADY(axi_S0_RREADY),
        .axi_S0_irq(axi_S0_irq),
        .axi_S1_AWADDR(axi_S1_AWADDR), .axi_S1_AWPROT(axi_S1_AWPROT),
        .axi_S1_AWVALID(axi_S1_AWVALID), .axi_S1_AWREADY(axi_S1_AWREADY),
        .axi_S1_WDATA(axi_S1_WDATA), .axi_S1_WSTRB(axi_S1_WSTRB),
        .axi_S1_WVALID(axi_S1_WVALID), .axi_S1_WREADY(axi_S1_WREADY),
        .axi_S1_BRESP(axi_S1_BRESP), .axi_S1_BVALID(axi_S1_BVALID), .axi_S1_BREADY(axi_S1_BREADY),
        .axi_S1_ARADDR(axi_S1_ARADDR), .axi_S1_ARPROT(axi_S1_ARPROT),
        .axi_S1_ARVALID(axi_S1_ARVALID), .axi_S1_ARREADY(axi_S1_ARREADY),
        .axi_S1_RDATA(axi_S1_RDATA), .axi_S1_RRESP(axi_S1_RRESP),
        .axi_S1_RVALID(axi_S1_RVALID), .axi_S1_RREADY(axi_S1_RREADY),
        .axi_S1_irq(axi_S1_irq),
        .axi_S2_AWADDR(axi_S2_AWADDR), .axi_S2_AWPROT(axi_S2_AWPROT),
        .axi_S2_AWVALID(axi_S2_AWVALID), .axi_S2_AWREADY(axi_S2_AWREADY),
        .axi_S2_WDATA(axi_S2_WDATA), .axi_S2_WSTRB(axi_S2_WSTRB),
        .axi_S2_WVALID(axi_S2_WVALID), .axi_S2_WREADY(axi_S2_WREADY),
        .axi_S2_BRESP(axi_S2_BRESP), .axi_S2_BVALID(axi_S2_BVALID), .axi_S2_BREADY(axi_S2_BREADY),
        .axi_S2_ARADDR(axi_S2_ARADDR), .axi_S2_ARPROT(axi_S2_ARPROT),
        .axi_S2_ARVALID(axi_S2_ARVALID), .axi_S2_ARREADY(axi_S2_ARREADY),
        .axi_S2_RDATA(axi_S2_RDATA), .axi_S2_RRESP(axi_S2_RRESP),
        .axi_S2_RVALID(axi_S2_RVALID), .axi_S2_RREADY(axi_S2_RREADY),
        .axi_S2_irq(axi_S2_irq),
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

    // ── External AXI SFR peripherals ─────────────────────────────────────
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

    // ── External AHB SFR peripherals ─────────────────────────────────────
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

    // ── Clocks ───────────────────────────────────────────────────────────
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    //=========================================================
    // Program list (hardcoded)
    //=========================================================
    localparam int N_PROGS = 17;

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
        // Phase 7
        programs[16] = "programs/prog_plic_basic.hex";

        pass_cnt = 0;
        fail_cnt = 0;

        $display("=== System Test: %0d programs ===", N_PROGS);
        $display("");

        for (int i = 0; i < N_PROGS; i++) begin

            // ── Reset phase ──
            rst_n = 1'b0;
            for (int j = 0; j < 16384; j++)
                u_soc.u_dmem.mem[j] = 32'd0;
            $readmemh(programs[i], u_soc.u_imem.mem);
            repeat(10) @(posedge clk_cpu);
            @(negedge clk_cpu);
            rst_n = 1'b1;

            // ── Run until EBREAK or timeout ──
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
                rst_n = 1'b0;
            end
        end

        // ── Summary ──
        $display("");
        $display("=== SYSTEM TEST: %0d/%0d PASS ===", pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("ALL PASS");
        else
            $display("%0d FAIL", fail_cnt);
        $finish;
    end

endmodule
