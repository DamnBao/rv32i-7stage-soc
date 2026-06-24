`timescale 1ns/1ps
// Phase 4c: axi_interface → axi_interconnect → 3 × axi_sfr (standard register map)
// Tests: address decode, write-read-back, IRQ via INTR_ENABLE+INTR_TEST+W1C,
//        multi-reg in one slave, cross-slave isolation, PERIPH_ID read.
module tb_axi_full;
    logic clk, rst_n;
    initial clk = 0;
    always #0.5 clk = ~clk;

    // ── CPU-side ─────────────────────────────────────────────────
    logic        req_valid, req_we;
    logic [31:0] req_addr, req_wdata;
    logic [1:0]  req_size;
    logic        resp_valid;
    logic [31:0] resp_rdata;
    logic        resp_err;

    // ── AXI Master bus (interface → interconnect) ─────────────────
    logic [31:0] M_AWADDR, M_WDATA, M_ARADDR, M_RDATA;
    logic [2:0]  M_AWPROT, M_ARPROT;
    logic [3:0]  M_WSTRB;
    logic        M_AWVALID, M_AWREADY, M_WVALID, M_WREADY;
    logic [1:0]  M_BRESP; logic M_BVALID, M_BREADY;
    logic        M_ARVALID, M_ARREADY;
    logic [1:0]  M_RRESP;  logic M_RVALID, M_RREADY;

    // ── Slave 0 bus ───────────────────────────────────────────────
    logic [31:0] S0_AWADDR, S0_WDATA, S0_ARADDR, S0_RDATA;
    logic [2:0]  S0_AWPROT, S0_ARPROT;
    logic [3:0]  S0_WSTRB;
    logic        S0_AWVALID, S0_AWREADY, S0_WVALID, S0_WREADY;
    logic [1:0]  S0_BRESP; logic S0_BVALID, S0_BREADY;
    logic        S0_ARVALID, S0_ARREADY;
    logic [1:0]  S0_RRESP;  logic S0_RVALID, S0_RREADY;
    logic        irq0;

    // ── Slave 1 bus ───────────────────────────────────────────────
    logic [31:0] S1_AWADDR, S1_WDATA, S1_ARADDR, S1_RDATA;
    logic [2:0]  S1_AWPROT, S1_ARPROT;
    logic [3:0]  S1_WSTRB;
    logic        S1_AWVALID, S1_AWREADY, S1_WVALID, S1_WREADY;
    logic [1:0]  S1_BRESP; logic S1_BVALID, S1_BREADY;
    logic        S1_ARVALID, S1_ARREADY;
    logic [1:0]  S1_RRESP;  logic S1_RVALID, S1_RREADY;
    logic        irq1;

    // ── Slave 2 bus ───────────────────────────────────────────────
    logic [31:0] S2_AWADDR, S2_WDATA, S2_ARADDR, S2_RDATA;
    logic [2:0]  S2_AWPROT, S2_ARPROT;
    logic [3:0]  S2_WSTRB;
    logic        S2_AWVALID, S2_AWREADY, S2_WVALID, S2_WREADY;
    logic [1:0]  S2_BRESP; logic S2_BVALID, S2_BREADY;
    logic        S2_ARVALID, S2_ARREADY;
    logic [1:0]  S2_RRESP;  logic S2_RVALID, S2_RREADY;
    logic        irq2;

    logic axi_irq;

    // ── DUT instantiations ────────────────────────────────────────
    axi_interface u_iface (
        .clk(clk), .rst_n(rst_n),
        .axi_req_valid(req_valid), .axi_req_addr(req_addr),
        .axi_req_we(req_we), .axi_req_wdata(req_wdata), .axi_req_size(req_size),
        .axi_resp_valid(resp_valid), .axi_resp_rdata(resp_rdata), .axi_resp_err(resp_err),
        .AWADDR(M_AWADDR), .AWPROT(M_AWPROT), .AWVALID(M_AWVALID), .AWREADY(M_AWREADY),
        .WDATA(M_WDATA),   .WSTRB(M_WSTRB),   .WVALID(M_WVALID),   .WREADY(M_WREADY),
        .BRESP(M_BRESP),   .BVALID(M_BVALID),  .BREADY(M_BREADY),
        .ARADDR(M_ARADDR), .ARPROT(M_ARPROT), .ARVALID(M_ARVALID), .ARREADY(M_ARREADY),
        .RDATA(M_RDATA),   .RRESP(M_RRESP),   .RVALID(M_RVALID),   .RREADY(M_RREADY)
    );

    axi_interconnect u_intc (
        .clk(clk), .rst_n(rst_n),
        .M_AWADDR(M_AWADDR), .M_AWPROT(M_AWPROT), .M_AWVALID(M_AWVALID), .M_AWREADY(M_AWREADY),
        .M_WDATA(M_WDATA),   .M_WSTRB(M_WSTRB),   .M_WVALID(M_WVALID),   .M_WREADY(M_WREADY),
        .M_BRESP(M_BRESP),   .M_BVALID(M_BVALID),  .M_BREADY(M_BREADY),
        .M_ARADDR(M_ARADDR), .M_ARPROT(M_ARPROT), .M_ARVALID(M_ARVALID), .M_ARREADY(M_ARREADY),
        .M_RDATA(M_RDATA),   .M_RRESP(M_RRESP),   .M_RVALID(M_RVALID),   .M_RREADY(M_RREADY),
        .S0_AWADDR(S0_AWADDR),.S0_AWPROT(S0_AWPROT),.S0_AWVALID(S0_AWVALID),.S0_AWREADY(S0_AWREADY),
        .S0_WDATA(S0_WDATA),  .S0_WSTRB(S0_WSTRB),  .S0_WVALID(S0_WVALID), .S0_WREADY(S0_WREADY),
        .S0_BRESP(S0_BRESP),  .S0_BVALID(S0_BVALID), .S0_BREADY(S0_BREADY),
        .S0_ARADDR(S0_ARADDR),.S0_ARPROT(S0_ARPROT),.S0_ARVALID(S0_ARVALID),.S0_ARREADY(S0_ARREADY),
        .S0_RDATA(S0_RDATA),  .S0_RRESP(S0_RRESP),  .S0_RVALID(S0_RVALID), .S0_RREADY(S0_RREADY),
        .irq0(irq0),
        .S1_AWADDR(S1_AWADDR),.S1_AWPROT(S1_AWPROT),.S1_AWVALID(S1_AWVALID),.S1_AWREADY(S1_AWREADY),
        .S1_WDATA(S1_WDATA),  .S1_WSTRB(S1_WSTRB),  .S1_WVALID(S1_WVALID), .S1_WREADY(S1_WREADY),
        .S1_BRESP(S1_BRESP),  .S1_BVALID(S1_BVALID), .S1_BREADY(S1_BREADY),
        .S1_ARADDR(S1_ARADDR),.S1_ARPROT(S1_ARPROT),.S1_ARVALID(S1_ARVALID),.S1_ARREADY(S1_ARREADY),
        .S1_RDATA(S1_RDATA),  .S1_RRESP(S1_RRESP),  .S1_RVALID(S1_RVALID), .S1_RREADY(S1_RREADY),
        .irq1(irq1),
        .S2_AWADDR(S2_AWADDR),.S2_AWPROT(S2_AWPROT),.S2_AWVALID(S2_AWVALID),.S2_AWREADY(S2_AWREADY),
        .S2_WDATA(S2_WDATA),  .S2_WSTRB(S2_WSTRB),  .S2_WVALID(S2_WVALID), .S2_WREADY(S2_WREADY),
        .S2_BRESP(S2_BRESP),  .S2_BVALID(S2_BVALID), .S2_BREADY(S2_BREADY),
        .S2_ARADDR(S2_ARADDR),.S2_ARPROT(S2_ARPROT),.S2_ARVALID(S2_ARVALID),.S2_ARREADY(S2_ARREADY),
        .S2_RDATA(S2_RDATA),  .S2_RRESP(S2_RRESP),  .S2_RVALID(S2_RVALID), .S2_RREADY(S2_RREADY),
        .irq2(irq2),
        .axi_irq(axi_irq)
    );

    axi_sfr u_sfr0 (
        .clk(clk), .rst_n(rst_n),
        .AWADDR(S0_AWADDR),.AWPROT(S0_AWPROT),.AWVALID(S0_AWVALID),.AWREADY(S0_AWREADY),
        .WDATA(S0_WDATA),  .WSTRB(S0_WSTRB),  .WVALID(S0_WVALID), .WREADY(S0_WREADY),
        .BRESP(S0_BRESP),  .BVALID(S0_BVALID), .BREADY(S0_BREADY),
        .ARADDR(S0_ARADDR),.ARPROT(S0_ARPROT),.ARVALID(S0_ARVALID),.ARREADY(S0_ARREADY),
        .RDATA(S0_RDATA),  .RRESP(S0_RRESP),  .RVALID(S0_RVALID), .RREADY(S0_RREADY),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(irq0)
    );

    axi_sfr u_sfr1 (
        .clk(clk), .rst_n(rst_n),
        .AWADDR(S1_AWADDR),.AWPROT(S1_AWPROT),.AWVALID(S1_AWVALID),.AWREADY(S1_AWREADY),
        .WDATA(S1_WDATA),  .WSTRB(S1_WSTRB),  .WVALID(S1_WVALID), .WREADY(S1_WREADY),
        .BRESP(S1_BRESP),  .BVALID(S1_BVALID), .BREADY(S1_BREADY),
        .ARADDR(S1_ARADDR),.ARPROT(S1_ARPROT),.ARVALID(S1_ARVALID),.ARREADY(S1_ARREADY),
        .RDATA(S1_RDATA),  .RRESP(S1_RRESP),  .RVALID(S1_RVALID), .RREADY(S1_RREADY),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(irq1)
    );

    axi_sfr u_sfr2 (
        .clk(clk), .rst_n(rst_n),
        .AWADDR(S2_AWADDR),.AWPROT(S2_AWPROT),.AWVALID(S2_AWVALID),.AWREADY(S2_AWREADY),
        .WDATA(S2_WDATA),  .WSTRB(S2_WSTRB),  .WVALID(S2_WVALID), .WREADY(S2_WREADY),
        .BRESP(S2_BRESP),  .BVALID(S2_BVALID), .BREADY(S2_BREADY),
        .ARADDR(S2_ARADDR),.ARPROT(S2_ARPROT),.ARVALID(S2_ARVALID),.ARREADY(S2_ARREADY),
        .RDATA(S2_RDATA),  .RRESP(S2_RRESP),  .RVALID(S2_RVALID), .RREADY(S2_RREADY),
        .status_in(32'd0), .irq_src(1'b0),
        .data0_out(), .data1_out(), .data2_out(), .irq(irq2)
    );

    // ── Scoreboard ────────────────────────────────────────────────
    int pass_cnt, fail_cnt, tnum;

    task pass_if(input logic ok);
        if (!ok) begin $display("FAIL T%0d", tnum); fail_cnt=fail_cnt+1; end
        else pass_cnt=pass_cnt+1;
    endtask

    task do_write(input [31:0] addr, wdata, input [1:0] size, input [3:0] exp_wstrb);
        @(negedge clk);
        req_valid=1; req_we=1; req_addr=addr; req_wdata=wdata; req_size=size;
        @(posedge clk);
        while (!resp_valid) @(posedge clk);
        tnum=tnum+1; pass_if(resp_err === 1'b0);
        @(negedge clk); req_valid=0; req_we=0;
        @(posedge clk);
    endtask

    task do_read(input [31:0] addr, exp_rdata);
        @(negedge clk);
        req_valid=1; req_we=0; req_addr=addr; req_size=2'b10;
        @(posedge clk);
        while (!resp_valid) @(posedge clk);
        tnum=tnum+1; pass_if(resp_rdata === exp_rdata);
        tnum=tnum+1; pass_if(resp_err   === 1'b0);
        @(negedge clk); req_valid=0;
        @(posedge clk);
    endtask

    // ── Main ─────────────────────────────────────────────────────
    initial begin
        pass_cnt=0; fail_cnt=0; tnum=0;
        req_valid=0; req_we=0; req_addr=0; req_wdata=0; req_size=2'b10;
        rst_n=0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;

        // ── Group 1: Address decode — CTRL (0x00) in each slave ──
        // Slave 0 (addr[27:12]=0x0000, base=0x2000_0000)
        do_write(32'h2000_0000, 32'hAABB_1100, 2'b10, 4'b1111); // write CTRL
        do_read (32'h2000_0000, 32'hAABB_1100);                   // read CTRL back

        // Slave 1 (addr[27:12]=0x0001, base=0x2000_1000)
        do_write(32'h2000_1000, 32'hCCDD_2200, 2'b10, 4'b1111);
        do_read (32'h2000_1000, 32'hCCDD_2200);

        // Slave 2 (addr[27:12]=0x0002, base=0x2000_2000)
        do_write(32'h2000_2000, 32'hEEFF_3300, 2'b10, 4'b1111);
        do_read (32'h2000_2000, 32'hEEFF_3300);

        // ── Group 2: IRQ — INTR_ENABLE (0x08) + INTR_TEST (0x10) ──
        // S0: enable bit0, trigger via INTR_TEST → irq0=1 → axi_irq=1
        do_write(32'h2000_0008, 32'h0000_0001, 2'b10, 4'b1111); // INTR_ENABLE[0]=1
        do_write(32'h2000_0010, 32'h0000_0001, 2'b10, 4'b1111); // INTR_TEST[0]=1 → set INTR_STATE[0]
        tnum=tnum+1; pass_if(axi_irq === 1'b1);

        // S1: same → axi_irq still 1 (OR)
        do_write(32'h2000_1008, 32'h0000_0001, 2'b10, 4'b1111);
        do_write(32'h2000_1010, 32'h0000_0001, 2'b10, 4'b1111);
        tnum=tnum+1; pass_if(axi_irq === 1'b1);

        // W1C clear S0: write 1 to INTR_STATE → irq0 clears; axi_irq=1 (S1 still set)
        do_write(32'h2000_000C, 32'h0000_0001, 2'b10, 4'b1111); // INTR_STATE W1C
        tnum=tnum+1; pass_if(axi_irq === 1'b1);

        // W1C clear S1 → axi_irq=0
        do_write(32'h2000_100C, 32'h0000_0001, 2'b10, 4'b1111);
        tnum=tnum+1; pass_if(axi_irq === 1'b0);

        // S2: trigger → axi_irq=1
        do_write(32'h2000_2008, 32'h0000_0001, 2'b10, 4'b1111);
        do_write(32'h2000_2010, 32'h0000_0001, 2'b10, 4'b1111);
        tnum=tnum+1; pass_if(axi_irq === 1'b1);

        // W1C clear S2 → axi_irq=0
        do_write(32'h2000_200C, 32'h0000_0001, 2'b10, 4'b1111);
        tnum=tnum+1; pass_if(axi_irq === 1'b0);

        // ── Group 3: Multiple standard regs in Slave 0 ────────────
        // DATA0 (0x14), DATA1 (0x18), DATA2 (0x1C)
        do_write(32'h2000_0014, 32'h1111_AAAA, 2'b10, 4'b1111);
        do_write(32'h2000_0018, 32'h2222_BBBB, 2'b10, 4'b1111);
        do_write(32'h2000_001C, 32'h3333_CCCC, 2'b10, 4'b1111);
        do_read (32'h2000_0014, 32'h1111_AAAA);
        do_read (32'h2000_0018, 32'h2222_BBBB);
        do_read (32'h2000_001C, 32'h3333_CCCC);

        // ── Group 4: Cross-slave isolation ───────────────────────
        // Write DATA0 to S0 and S2 with different values
        do_write(32'h2000_0014, 32'hF0F0_AAAA, 2'b10, 4'b1111); // S0 DATA0
        do_write(32'h2000_2014, 32'h0F0F_BBBB, 2'b10, 4'b1111); // S2 DATA0
        do_read (32'h2000_0014, 32'hF0F0_AAAA); // S0 not affected by S2 write
        do_read (32'h2000_2014, 32'h0F0F_BBBB); // S2 holds own value
        do_read (32'h2000_1014, 32'h0000_0000); // S1 DATA0 never written → 0
        // S0 CTRL still from Group 1
        do_read (32'h2000_0000, 32'hAABB_1100);
        do_read (32'h2000_2000, 32'hEEFF_3300);

        // ── Bonus: PERIPH_ID read (offset 0xFC = idx 63) ─────────
        do_read (32'h2000_00FC, 32'h5346_5230); // default PERIPH_ID_VAL

        $display("=== tb_axi_full: %0d/%0d PASS ===", pass_cnt, pass_cnt+fail_cnt);
        if (fail_cnt==0) $display("ALL PASS");
        $finish;
    end

    initial begin #20000; $display("TIMEOUT"); $fatal(1,"tb_axi_full TIMEOUT"); end
endmodule
