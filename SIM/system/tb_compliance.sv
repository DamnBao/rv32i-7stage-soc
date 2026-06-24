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

    // ── AHB Slaves ───────────────────────────────────────────────────────
    logic        ahb_S0_HSEL_o, ahb_S0_HREADY_o;
    logic        ahb_S0_HREADYOUT_i, ahb_S0_HRESP_i, ahb_S0_irq_i;
    logic [31:0] ahb_S0_HRDATA_i;
    logic        ahb_S1_HSEL_o, ahb_S1_HREADY_o;
    logic        ahb_S1_HREADYOUT_i, ahb_S1_HRESP_i, ahb_S1_irq_i;
    logic [31:0] ahb_S1_HRDATA_i;
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

    // ── External SFR peripherals ──────────────────────────────────────────
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

    // ── Clocks ───────────────────────────────────────────────────────────
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;
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

    initial begin
        #200000;
        $display("TEST_FAIL  TIMEOUT — no EBREAK after 200000 cycles");
        $finish(1);
    end

endmodule
