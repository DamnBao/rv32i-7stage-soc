`timescale 1ns/1ps

// Integration testbench: AHB bus error → Store/Load access fault exception
//
// AHB S0 is replaced by an inline AHB error slave (always returns HRESP=ERROR).
// AHB S1/S2 are standard ahb_sfr (HRESP=OKAY). All AXI slaves are axi_sfr.
//
// AHB-Lite 2-cycle error protocol:
//   Cycle 1 (data phase): HREADYOUT=0, HRESP=1  (extend bus, signal error)
//   Cycle 2:              HREADYOUT=1, HRESP=1  (release bus, error confirmed)
//
// Test programs:
//   prog_ahb_store_err.hex: SW to S0 → HRESP=ERROR → store_access_fault (mcause=7)
//   prog_ahb_load_err.hex:  LW from S0 → HRESP=ERROR → load_access_fault (mcause=5)
//
// Usage: vvp integration/tb_soc_ahb_err.vvp +HEX=programs/bin/prog_ahb_store_err.hex

module tb_soc_ahb_err;

    logic clk_cpu, clk_ahb, rst_n;
    logic rst_cpu_n_o, rst_ahb_n_o;

    // ── AXI Slave 0 ───────────────────────────────────────────────────────
    logic [31:0] axi_S0_AWADDR; logic [2:0] axi_S0_AWPROT;
    logic        axi_S0_AWVALID, axi_S0_AWREADY;
    logic [31:0] axi_S0_WDATA;  logic [3:0] axi_S0_WSTRB;
    logic        axi_S0_WVALID,  axi_S0_WREADY;
    logic [1:0]  axi_S0_BRESP;  logic axi_S0_BVALID, axi_S0_BREADY;
    logic [31:0] axi_S0_ARADDR; logic [2:0] axi_S0_ARPROT;
    logic        axi_S0_ARVALID, axi_S0_ARREADY;
    logic [31:0] axi_S0_RDATA;  logic [1:0] axi_S0_RRESP;
    logic        axi_S0_RVALID,  axi_S0_RREADY, axi_S0_irq;

    // ── AXI Slave 1 ───────────────────────────────────────────────────────
    logic [31:0] axi_S1_AWADDR; logic [2:0] axi_S1_AWPROT;
    logic        axi_S1_AWVALID, axi_S1_AWREADY;
    logic [31:0] axi_S1_WDATA;  logic [3:0] axi_S1_WSTRB;
    logic        axi_S1_WVALID,  axi_S1_WREADY;
    logic [1:0]  axi_S1_BRESP;  logic axi_S1_BVALID, axi_S1_BREADY;
    logic [31:0] axi_S1_ARADDR; logic [2:0] axi_S1_ARPROT;
    logic        axi_S1_ARVALID, axi_S1_ARREADY;
    logic [31:0] axi_S1_RDATA;  logic [1:0] axi_S1_RRESP;
    logic        axi_S1_RVALID,  axi_S1_RREADY, axi_S1_irq;

    // ── AXI Slave 2 ───────────────────────────────────────────────────────
    logic [31:0] axi_S2_AWADDR; logic [2:0] axi_S2_AWPROT;
    logic        axi_S2_AWVALID, axi_S2_AWREADY;
    logic [31:0] axi_S2_WDATA;  logic [3:0] axi_S2_WSTRB;
    logic        axi_S2_WVALID,  axi_S2_WREADY;
    logic [1:0]  axi_S2_BRESP;  logic axi_S2_BVALID, axi_S2_BREADY;
    logic [31:0] axi_S2_ARADDR; logic [2:0] axi_S2_ARPROT;
    logic        axi_S2_ARVALID, axi_S2_ARREADY;
    logic [31:0] axi_S2_RDATA;  logic [1:0] axi_S2_RRESP;
    logic        axi_S2_RVALID,  axi_S2_RREADY, axi_S2_irq;

    // ── AHB shared bus ────────────────────────────────────────────────────
    logic [31:0] ahb_HADDR_o, ahb_HWDATA_o;
    logic [2:0]  ahb_HSIZE_o;
    logic [1:0]  ahb_HTRANS_o;
    logic        ahb_HWRITE_o;

    // ── AHB Slave 0 (error slave) ─────────────────────────────────────────
    logic        ahb_S0_HSEL_o, ahb_S0_HREADY_o;
    logic        ahb_S0_HREADYOUT_i, ahb_S0_HRESP_i, ahb_S0_irq_i;
    logic [31:0] ahb_S0_HRDATA_i;

    // ── AHB Slave 1 ───────────────────────────────────────────────────────
    logic        ahb_S1_HSEL_o, ahb_S1_HREADY_o;
    logic        ahb_S1_HREADYOUT_i, ahb_S1_HRESP_i, ahb_S1_irq_i;
    logic [31:0] ahb_S1_HRDATA_i;

    // ── AHB Slave 2 ───────────────────────────────────────────────────────
    logic        ahb_S2_HSEL_o, ahb_S2_HREADY_o;
    logic        ahb_S2_HREADYOUT_i, ahb_S2_HRESP_i, ahb_S2_irq_i;
    logic [31:0] ahb_S2_HRDATA_i;

    // ── SoC Top ───────────────────────────────────────────────────────────
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

    // ── Normal AXI peripherals (all 3 slaves: no errors) ──────────────────
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

    // ── AHB Error Slave (S0): 2-cycle HRESP=ERROR for every transaction ───
    //
    // State machine tracks the data phase of each AHB transaction and drives
    // the 2-cycle error response required by AHB-Lite spec (ARM IHI0033A):
    //   IDLE   → detect address phase (HSEL & HTRANS[1] & HREADY_in)
    //   ERR_C1 → HREADYOUT=0, HRESP=1  (data phase cycle 1: extend, signal error)
    //   ERR_C2 → HREADYOUT=1, HRESP=1  (data phase cycle 2: release, confirm error)
    //
    // ahb_interface.sv pushes {HRESP, HRDATA} when HREADY=1 (ERR_C2 cycle).
    // mem1_stage reads ahb_resp_err = resp_fifo_rd_data[32] = 1.
    localparam AHB_ERR_IDLE = 2'd0;
    localparam AHB_ERR_C1   = 2'd1;
    localparam AHB_ERR_C2   = 2'd2;

    logic [1:0] ahb_err_state;

    always_ff @(posedge clk_ahb or negedge rst_ahb_n_o) begin
        if (!rst_ahb_n_o) begin
            ahb_err_state <= AHB_ERR_IDLE;
        end else begin
            case (ahb_err_state)
                AHB_ERR_IDLE: begin
                    // Address phase: slave selected, valid transfer, bus ready
                    if (ahb_S0_HSEL_o && ahb_HTRANS_o[1] && ahb_S0_HREADY_o)
                        ahb_err_state <= AHB_ERR_C1;
                end
                AHB_ERR_C1:  ahb_err_state <= AHB_ERR_C2;
                AHB_ERR_C2:  ahb_err_state <= AHB_ERR_IDLE;
                default:     ahb_err_state <= AHB_ERR_IDLE;
            endcase
        end
    end

    assign ahb_S0_HREADYOUT_i = (ahb_err_state != AHB_ERR_C1);  // 0 only in C1
    assign ahb_S0_HRESP_i     = (ahb_err_state == AHB_ERR_C1) || (ahb_err_state == AHB_ERR_C2);
    assign ahb_S0_HRDATA_i    = 32'h0;
    assign ahb_S0_irq_i       = 1'b0;

    // ── Normal AHB peripherals (S1 and S2) ────────────────────────────────
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

    // ── Clocks ────────────────────────────────────────────────────────────
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;
    // clk_ahb: 500MHz, offset 0.3ns to avoid coincident edges with clk_cpu
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    string hex_file;
    string vcd_file;

    initial begin
        if (!$value$plusargs("HEX=%s", hex_file))
            $fatal(1, "[tb_soc_ahb_err] Usage: vvp <vvp> +HEX=<hex_file>");

        if ($value$plusargs("DUMP=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_soc_ahb_err);
        end

        rst_n = 0;
        $readmemh(hex_file, u_soc.u_imem.mem);
        $display("[INFO] Loaded %s", hex_file);

        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n = 1;
    end

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

    initial begin
        #200000;
        $fatal(1, "[TIMEOUT] %s — no EBREAK after 200000 cycles", hex_file);
    end

endmodule
