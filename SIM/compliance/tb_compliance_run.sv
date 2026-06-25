`timescale 1ns/1ps

// tb_compliance_run.sv — Testbench for RV32I compliance test signature dump
//
// Loads a compliance test ELF (code-only hex) into IMEM, runs until EBREAK,
// then dumps the signature region from DMEM to a text file for comparison.
//
// Plusargs:
//   +HEX=<path>        IMEM hex (code-only sections, objcopy verilog format)
//   +SIG_BEGIN=<hex>   byte address of begin_signature (e.g. 10040)
//   +SIG_END=<hex>     byte address of end_signature   (e.g. 10970)
//   +SIG_FILE=<path>   output file path for signature words (one 8-digit hex per line)
//   +DUMP=<vcd_path>   optional VCD dump
//
// Signature format: each 32-bit word on a separate line, lowercase 8-digit hex,
// matching the format of riscv-arch-test *.reference_output files.
//
// Hierarchy:
//   u_soc.u_imem.mem  — IMEM word array (loaded from HEX)
//   u_soc.u_dmem.mem  — DMEM word array (populated by test sw instructions)
//   u_soc.wb_ebreak   — EBREAK detected at WB stage
//   u_soc.u_rf.registers[31] — x31 (not used for compliance, uses sig comparison)

module tb_compliance_run;

    logic clk_cpu, clk_ahb, rst_n;
    logic rst_cpu_n_o, rst_ahb_n_o;

    // ── AXI slaves (unused in compliance tests — all normal axi_sfr) ─────────
    logic [31:0] axi_S0_AWADDR, axi_S1_AWADDR, axi_S2_AWADDR;
    logic [2:0]  axi_S0_AWPROT, axi_S1_AWPROT, axi_S2_AWPROT;
    logic        axi_S0_AWVALID, axi_S1_AWVALID, axi_S2_AWVALID;
    logic        axi_S0_AWREADY, axi_S1_AWREADY, axi_S2_AWREADY;
    logic [31:0] axi_S0_WDATA,  axi_S1_WDATA,  axi_S2_WDATA;
    logic [3:0]  axi_S0_WSTRB,  axi_S1_WSTRB,  axi_S2_WSTRB;
    logic        axi_S0_WVALID, axi_S1_WVALID, axi_S2_WVALID;
    logic        axi_S0_WREADY, axi_S1_WREADY, axi_S2_WREADY;
    logic [1:0]  axi_S0_BRESP,  axi_S1_BRESP,  axi_S2_BRESP;
    logic        axi_S0_BVALID, axi_S1_BVALID, axi_S2_BVALID;
    logic        axi_S0_BREADY, axi_S1_BREADY, axi_S2_BREADY;
    logic [31:0] axi_S0_ARADDR, axi_S1_ARADDR, axi_S2_ARADDR;
    logic [2:0]  axi_S0_ARPROT, axi_S1_ARPROT, axi_S2_ARPROT;
    logic        axi_S0_ARVALID, axi_S1_ARVALID, axi_S2_ARVALID;
    logic        axi_S0_ARREADY, axi_S1_ARREADY, axi_S2_ARREADY;
    logic [31:0] axi_S0_RDATA,  axi_S1_RDATA,  axi_S2_RDATA;
    logic [1:0]  axi_S0_RRESP,  axi_S1_RRESP,  axi_S2_RRESP;
    logic        axi_S0_RVALID, axi_S1_RVALID, axi_S2_RVALID;
    logic        axi_S0_RREADY, axi_S1_RREADY, axi_S2_RREADY;
    logic        axi_S0_irq, axi_S1_irq, axi_S2_irq;

    // ── AHB shared bus (unused in compliance tests) ───────────────────────────
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

    // ── SoC Top (512KB IMEM for compliance — branch tests need up to ~294KB) ─
    soc_top #(.IMEM_SIZE_KB(512)) u_soc (
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

    // ── AXI SFR peripherals (all normal, not tested by compliance programs) ───
    axi_sfr u_axi_sfr0 (
        .clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S0_AWADDR), .AWPROT(axi_S0_AWPROT), .AWVALID(axi_S0_AWVALID), .AWREADY(axi_S0_AWREADY),
        .WDATA(axi_S0_WDATA), .WSTRB(axi_S0_WSTRB), .WVALID(axi_S0_WVALID), .WREADY(axi_S0_WREADY),
        .BRESP(axi_S0_BRESP), .BVALID(axi_S0_BVALID), .BREADY(axi_S0_BREADY),
        .ARADDR(axi_S0_ARADDR), .ARPROT(axi_S0_ARPROT), .ARVALID(axi_S0_ARVALID), .ARREADY(axi_S0_ARREADY),
        .RDATA(axi_S0_RDATA), .RRESP(axi_S0_RRESP), .RVALID(axi_S0_RVALID), .RREADY(axi_S0_RREADY),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(axi_S0_irq));

    axi_sfr u_axi_sfr1 (
        .clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S1_AWADDR), .AWPROT(axi_S1_AWPROT), .AWVALID(axi_S1_AWVALID), .AWREADY(axi_S1_AWREADY),
        .WDATA(axi_S1_WDATA), .WSTRB(axi_S1_WSTRB), .WVALID(axi_S1_WVALID), .WREADY(axi_S1_WREADY),
        .BRESP(axi_S1_BRESP), .BVALID(axi_S1_BVALID), .BREADY(axi_S1_BREADY),
        .ARADDR(axi_S1_ARADDR), .ARPROT(axi_S1_ARPROT), .ARVALID(axi_S1_ARVALID), .ARREADY(axi_S1_ARREADY),
        .RDATA(axi_S1_RDATA), .RRESP(axi_S1_RRESP), .RVALID(axi_S1_RVALID), .RREADY(axi_S1_RREADY),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(axi_S1_irq));

    axi_sfr u_axi_sfr2 (
        .clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S2_AWADDR), .AWPROT(axi_S2_AWPROT), .AWVALID(axi_S2_AWVALID), .AWREADY(axi_S2_AWREADY),
        .WDATA(axi_S2_WDATA), .WSTRB(axi_S2_WSTRB), .WVALID(axi_S2_WVALID), .WREADY(axi_S2_WREADY),
        .BRESP(axi_S2_BRESP), .BVALID(axi_S2_BVALID), .BREADY(axi_S2_BREADY),
        .ARADDR(axi_S2_ARADDR), .ARPROT(axi_S2_ARPROT), .ARVALID(axi_S2_ARVALID), .ARREADY(axi_S2_ARREADY),
        .RDATA(axi_S2_RDATA), .RRESP(axi_S2_RRESP), .RVALID(axi_S2_RVALID), .RREADY(axi_S2_RREADY),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(axi_S2_irq));

    // ── AHB SFR peripherals ───────────────────────────────────────────────────
    ahb_sfr u_ahb_sfr0 (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S0_HSEL_o), .HREADY(ahb_S0_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S0_HRDATA_i), .HREADYOUT(ahb_S0_HREADYOUT_i), .HRESP(ahb_S0_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S0_irq_i));

    ahb_sfr u_ahb_sfr1 (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S1_HSEL_o), .HREADY(ahb_S1_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S1_HRDATA_i), .HREADYOUT(ahb_S1_HREADYOUT_i), .HRESP(ahb_S1_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S1_irq_i));

    ahb_sfr u_ahb_sfr2 (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S2_HSEL_o), .HREADY(ahb_S2_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S2_HRDATA_i), .HREADYOUT(ahb_S2_HREADYOUT_i), .HRESP(ahb_S2_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S2_irq_i));

    // ── Clocks ────────────────────────────────────────────────────────────────
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    // ── Plusargs and signature dump ───────────────────────────────────────────
    string hex_file, sig_file, vcd_file;
    longint unsigned sig_begin_byte, sig_end_byte;

    initial begin
        if (!$value$plusargs("HEX=%s",       hex_file))      $fatal(1, "Missing +HEX");
        if (!$value$plusargs("SIG_BEGIN=%h",  sig_begin_byte)) $fatal(1, "Missing +SIG_BEGIN");
        if (!$value$plusargs("SIG_END=%h",    sig_end_byte))   $fatal(1, "Missing +SIG_END");
        if (!$value$plusargs("SIG_FILE=%s",  sig_file))       $fatal(1, "Missing +SIG_FILE");

        if ($value$plusargs("DUMP=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_compliance_run);
        end

        rst_n = 0;
        $readmemh(hex_file, u_soc.u_imem.mem);

        // Pre-initialize DMEM from ELF .data section (needed by load/store tests)
        // DMEM hex is rebased from 0x10000 to 0x0 by objcopy --change-addresses=-0x10000
        begin
            string dmem_hex;
            if ($value$plusargs("DMEM_HEX=%s", dmem_hex))
                $readmemh(dmem_hex, u_soc.u_dmem.mem);
        end

        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n = 1;
    end

    // ── EBREAK detection → dump signature ────────────────────────────────────
    always @(posedge clk_cpu) begin
        if (rst_n && u_soc.wb_ebreak) begin
            integer fd;
            longint unsigned n_words, i;
            longint unsigned dmem_base;
            longint unsigned word_idx;
            logic [31:0] word;

            // DMEM byte address → array index: word_idx = (byte_addr - 0x10000) / 4
            dmem_base = 32'h00010000;
            n_words   = (sig_end_byte - sig_begin_byte) >> 2;

            fd = $fopen(sig_file, "w");
            if (fd == 0) $fatal(1, "[tb_compliance] Cannot open %s", sig_file);

            for (i = 0; i < n_words; i++) begin
                word_idx = (sig_begin_byte - dmem_base) / 4 + i;
                word = u_soc.u_dmem.mem[word_idx];
                // X bits → 0: DMEM is uninitialized (X); reference (Spike) sees 0 for unwritten locations
                if (^word === 1'bx)
                    $fwrite(fd, "00000000\n");
                else
                    $fwrite(fd, "%08x\n", word);
            end

            $fclose(fd);
            $finish;
        end
    end

    // ── Timeout ───────────────────────────────────────────────────────────────
    initial begin
        #5000000;  // 5M ns = 5ms @ 1GHz ≈ 5M cycles — enough for large tests
        $fatal(1, "[TIMEOUT] %s — no EBREAK after 5M cycles", hex_file);
    end

endmodule
