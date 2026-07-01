// tb_periph — System testbench with real Timer (AXI S1) and GPIO (AHB S0) peripherals
//
// Peripheral connections:
//   AXI Slave 0: axi_sfr   (generic placeholder, 0x2000_0000)
//   AXI Slave 1: timer_axi  (real timer, 0x2000_1000)
//   AXI Slave 2: axi_sfr   (generic placeholder, 0x2000_2000)
//   AHB Slave 0: gpio_ahb   (real GPIO, 0x3000_0000; gpio_out looped back to gpio_in)
//   AHB Slave 1: ahb_sfr   (generic placeholder, 0x3000_1000)
//   AHB Slave 2: ahb_sfr   (generic placeholder, 0x3000_2000)
//
// Usage: vvp system/tb_periph.vvp +HEX=programs/bin/prog_timer.hex
//        vvp system/tb_periph.vvp +HEX=programs/bin/prog_gpio_ahb.hex

`timescale 1ns/1ps

module tb_periph;

    logic clk_cpu, clk_ahb, rst_n;
    logic rst_cpu_n_o, rst_ahb_n_o;

    // ── AXI Slave signals ─────────────────────────────────────────
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

    // ── AHB shared bus ────────────────────────────────────────────
    logic [31:0] ahb_HADDR_o, ahb_HWDATA_o;
    logic [2:0]  ahb_HSIZE_o;
    logic [1:0]  ahb_HTRANS_o;
    logic        ahb_HWRITE_o;

    // ── AHB Slave signals ─────────────────────────────────────────
    logic        ahb_S0_HSEL_o, ahb_S0_HREADY_o;
    logic        ahb_S0_HREADYOUT_i, ahb_S0_HRESP_i, ahb_S0_irq_i;
    logic [31:0] ahb_S0_HRDATA_i;

    logic        ahb_S1_HSEL_o, ahb_S1_HREADY_o;
    logic        ahb_S1_HREADYOUT_i, ahb_S1_HRESP_i, ahb_S1_irq_i;
    logic [31:0] ahb_S1_HRDATA_i;

    logic        ahb_S2_HSEL_o, ahb_S2_HREADY_o;
    logic        ahb_S2_HREADYOUT_i, ahb_S2_HRESP_i, ahb_S2_irq_i;
    logic [31:0] ahb_S2_HRDATA_i;

    // ── GPIO loopback signals ─────────────────────────────────────
    logic [31:0] gpio_out_0;  // gpio_ahb output → looped back to gpio_in

    // ── SoC Top ───────────────────────────────────────────────────
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

    // ── AXI Slave 0: generic SFR (placeholder) ───────────────────
    axi_sfr u_axi_sfr0 (.clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S0_AWADDR), .AWPROT(axi_S0_AWPROT), .AWVALID(axi_S0_AWVALID), .AWREADY(axi_S0_AWREADY),
        .WDATA(axi_S0_WDATA), .WSTRB(axi_S0_WSTRB), .WVALID(axi_S0_WVALID), .WREADY(axi_S0_WREADY),
        .BRESP(axi_S0_BRESP), .BVALID(axi_S0_BVALID), .BREADY(axi_S0_BREADY),
        .ARADDR(axi_S0_ARADDR), .ARPROT(axi_S0_ARPROT), .ARVALID(axi_S0_ARVALID), .ARREADY(axi_S0_ARREADY),
        .RDATA(axi_S0_RDATA), .RRESP(axi_S0_RRESP), .RVALID(axi_S0_RVALID), .RREADY(axi_S0_RREADY),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(axi_S0_irq));

    // ── AXI Slave 1: timer_axi (real Timer peripheral) ───────────
    timer_axi u_timer (
        .clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S1_AWADDR), .AWPROT(axi_S1_AWPROT), .AWVALID(axi_S1_AWVALID), .AWREADY(axi_S1_AWREADY),
        .WDATA(axi_S1_WDATA), .WSTRB(axi_S1_WSTRB), .WVALID(axi_S1_WVALID), .WREADY(axi_S1_WREADY),
        .BRESP(axi_S1_BRESP), .BVALID(axi_S1_BVALID), .BREADY(axi_S1_BREADY),
        .ARADDR(axi_S1_ARADDR), .ARPROT(axi_S1_ARPROT), .ARVALID(axi_S1_ARVALID), .ARREADY(axi_S1_ARREADY),
        .RDATA(axi_S1_RDATA), .RRESP(axi_S1_RRESP), .RVALID(axi_S1_RVALID), .RREADY(axi_S1_RREADY),
        .irq(axi_S1_irq)
    );

    // ── AXI Slave 2: uart_axi (real UART peripheral, TX→RX loopback)
    logic uart_tx_w;   // loopback wire: uart_tx output feeds uart_rx input
    uart_axi u_uart (
        .clk(clk_cpu), .rst_n(rst_cpu_n_o),
        .AWADDR(axi_S2_AWADDR), .AWPROT(axi_S2_AWPROT), .AWVALID(axi_S2_AWVALID), .AWREADY(axi_S2_AWREADY),
        .WDATA(axi_S2_WDATA), .WSTRB(axi_S2_WSTRB), .WVALID(axi_S2_WVALID), .WREADY(axi_S2_WREADY),
        .BRESP(axi_S2_BRESP), .BVALID(axi_S2_BVALID), .BREADY(axi_S2_BREADY),
        .ARADDR(axi_S2_ARADDR), .ARPROT(axi_S2_ARPROT), .ARVALID(axi_S2_ARVALID), .ARREADY(axi_S2_ARREADY),
        .RDATA(axi_S2_RDATA), .RRESP(axi_S2_RRESP), .RVALID(axi_S2_RVALID), .RREADY(axi_S2_RREADY),
        .uart_rx(uart_tx_w),   // loopback
        .uart_tx(uart_tx_w),
        .irq(axi_S2_irq)
    );

    // ── AHB Slave 0: gpio_ahb (real GPIO peripheral, loopback) ───
    gpio_ahb u_gpio (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S0_HSEL_o), .HREADY(ahb_S0_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S0_HRDATA_i), .HREADYOUT(ahb_S0_HREADYOUT_i), .HRESP(ahb_S0_HRESP_i),
        .gpio_in(gpio_out_0),    // loopback: gpio_out → gpio_in
        .gpio_out(gpio_out_0),
        .irq(ahb_S0_irq_i)
    );

    // ── AHB Slave 1: generic SFR (placeholder) ───────────────────
    ahb_sfr u_ahb_sfr1 (.clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S1_HSEL_o), .HREADY(ahb_S1_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S1_HRDATA_i), .HREADYOUT(ahb_S1_HREADYOUT_i), .HRESP(ahb_S1_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S1_irq_i));

    // ── AHB Slave 2: generic SFR (placeholder) ───────────────────
    ahb_sfr u_ahb_sfr2 (.clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n_o),
        .HSEL(ahb_S2_HSEL_o), .HREADY(ahb_S2_HREADY_o),
        .HADDR(ahb_HADDR_o), .HTRANS(ahb_HTRANS_o), .HWRITE(ahb_HWRITE_o), .HWDATA(ahb_HWDATA_o),
        .HRDATA(ahb_S2_HRDATA_i), .HREADYOUT(ahb_S2_HREADYOUT_i), .HRESP(ahb_S2_HRESP_i),
        .status_in(32'd0), .irq_src(1'b0), .data0_out(), .data1_out(), .data2_out(), .irq(ahb_S2_irq_i));

    // ── Clocks ────────────────────────────────────────────────────
    initial  clk_cpu = 0;
    always  #0.5 clk_cpu = ~clk_cpu;
    initial begin clk_ahb = 0; #0.3; forever #1.0 clk_ahb = ~clk_ahb; end

    // ── Main test ─────────────────────────────────────────────────
    string hex_file;
    int    cycle_cnt;
    logic  done;

    initial begin
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("Usage: vvp tb_periph.vvp +HEX=<hex_file>");
            $finish;
        end

        rst_n = 1'b0;
        for (int j = 0; j < 16384; j++)
            u_soc.u_dmem.mem[j] = 32'd0;
        $readmemh(hex_file, u_soc.u_imem.mem);
        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n = 1'b1;

        done = 1'b0;
        for (cycle_cnt = 0; cycle_cnt < 500000 && !done; cycle_cnt++) begin
            @(posedge clk_cpu);
            if (rst_n && u_soc.wb_ebreak)
                done = 1'b1;
        end

        if (!done) begin
            $display("TIMEOUT  [%s]", hex_file);
            $finish;
        end

        if (u_soc.u_rf.registers[31] == 32'd1) begin
            $display("PASS  [%s]", hex_file);
        end else begin
            $display("FAIL  [%s]  x31=0x%08X", hex_file, u_soc.u_rf.registers[31]);
        end

        $finish;
    end

endmodule
