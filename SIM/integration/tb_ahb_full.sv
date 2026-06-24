`timescale 1ns/1ps
// Phase 4d: ahb_interface (via CDC FIFOs) → ahb_interconnect → 3 × ahb_sfr
// Tests: address decode (addr[27:12]), write-read-back, IRQ aggregation,
//        multi-reg in one slave, cross-slave isolation.
module tb_ahb_full;
    // ── Clocks / Resets ──────────────────────────────────────────
    logic clk_1g, clk_ahb;
    logic rst_1g_n, rst_ahb_n;

    initial clk_1g = 0;
    always #0.5 clk_1g = ~clk_1g;
    initial begin clk_ahb = 0; #0.7; forever #1.0 clk_ahb = ~clk_ahb; end

    // ── Request FIFO (1GHz → 500MHz) — 67 bits ──────────────────
    logic        req_wr_en;
    logic [66:0] req_wr_data;
    logic        req_rd_en, req_rd_empty;
    logic [66:0] req_rd_data;

    async_fifo_depth2 #(.DATA_WIDTH(67)) u_req_fifo (
        .wr_clk(clk_1g), .wr_rst_n(rst_1g_n),
        .wr_en(req_wr_en), .wr_data(req_wr_data),
        .rd_clk(clk_ahb), .rd_rst_n(rst_ahb_n),
        .rd_en(req_rd_en), .rd_data(req_rd_data),
        .rd_empty(req_rd_empty)
    );

    // ── Response FIFO (500MHz → 1GHz) — 33 bits ─────────────────
    logic        resp_wr_en;
    logic [32:0] resp_wr_data;
    logic        resp_rd_en, resp_rd_empty;
    logic [32:0] resp_rd_data;

    async_fifo_depth2 #(.DATA_WIDTH(33)) u_resp_fifo (
        .wr_clk(clk_ahb), .wr_rst_n(rst_ahb_n),
        .wr_en(resp_wr_en), .wr_data(resp_wr_data),
        .rd_clk(clk_1g),  .rd_rst_n(rst_1g_n),
        .rd_en(resp_rd_en), .rd_data(resp_rd_data),
        .rd_empty(resp_rd_empty)
    );

    // ── Shared AHB bus ────────────────────────────────────────────
    logic [31:0] HADDR, HWDATA, HRDATA;
    logic [2:0]  HSIZE;
    logic [1:0]  HTRANS;
    logic        HWRITE, HREADY, HRESP;

    // ── AHB Interface DUT ─────────────────────────────────────────
    ahb_interface u_iface (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n),
        .req_empty(req_rd_empty), .req_rd_en(req_rd_en), .req_rd_data(req_rd_data),
        .resp_wr_en(resp_wr_en), .resp_wr_data(resp_wr_data),
        .HADDR(HADDR), .HSIZE(HSIZE), .HTRANS(HTRANS),
        .HWRITE(HWRITE), .HWDATA(HWDATA),
        .HREADY(HREADY), .HRDATA(HRDATA), .HRESP(HRESP)
    );

    // ── Interconnect outputs to slaves ────────────────────────────
    logic        HSEL0, HREADY0_in, HREADYOUT0, HRESP0;
    logic [31:0] HRDATA0;
    logic        irq0;
    logic        HSEL1, HREADY1_in, HREADYOUT1, HRESP1;
    logic [31:0] HRDATA1;
    logic        irq1;
    logic        HSEL2, HREADY2_in, HREADYOUT2, HRESP2;
    logic [31:0] HRDATA2;
    logic        irq2;
    logic        ahb_irq;

    // ── AHB Interconnect ──────────────────────────────────────────
    ahb_interconnect u_intc (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n),
        .HADDR(HADDR), .HSIZE(HSIZE), .HTRANS(HTRANS),
        .HWRITE(HWRITE), .HWDATA(HWDATA),
        .HREADY(HREADY), .HRDATA(HRDATA), .HRESP(HRESP),
        .HSEL0(HSEL0), .HREADY0_in(HREADY0_in),
        .HREADYOUT0(HREADYOUT0), .HRDATA0(HRDATA0), .HRESP0(HRESP0), .irq0(irq0),
        .HSEL1(HSEL1), .HREADY1_in(HREADY1_in),
        .HREADYOUT1(HREADYOUT1), .HRDATA1(HRDATA1), .HRESP1(HRESP1), .irq1(irq1),
        .HSEL2(HSEL2), .HREADY2_in(HREADY2_in),
        .HREADYOUT2(HREADYOUT2), .HRDATA2(HRDATA2), .HRESP2(HRESP2), .irq2(irq2),
        .ahb_irq(ahb_irq)
    );

    // ── AHB SFR Slaves ────────────────────────────────────────────
    ahb_sfr u_sfr0 (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n),
        .HSEL(HSEL0), .HREADY(HREADY0_in),
        .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE), .HWDATA(HWDATA),
        .HRDATA(HRDATA0), .HREADYOUT(HREADYOUT0), .HRESP(HRESP0), .irq(irq0)
    );

    ahb_sfr u_sfr1 (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n),
        .HSEL(HSEL1), .HREADY(HREADY1_in),
        .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE), .HWDATA(HWDATA),
        .HRDATA(HRDATA1), .HREADYOUT(HREADYOUT1), .HRESP(HRESP1), .irq(irq1)
    );

    ahb_sfr u_sfr2 (
        .clk_ahb(clk_ahb), .rst_ahb_n(rst_ahb_n),
        .HSEL(HSEL2), .HREADY(HREADY2_in),
        .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE), .HWDATA(HWDATA),
        .HRDATA(HRDATA2), .HREADYOUT(HREADYOUT2), .HRESP(HRESP2), .irq(irq2)
    );

    // ── Scoreboard ────────────────────────────────────────────────
    int pass_cnt, fail_cnt, tnum;

    task pass_if(input logic ok);
        if (!ok) begin $display("FAIL T%0d", tnum); fail_cnt=fail_cnt+1; end
        else pass_cnt=pass_cnt+1;
    endtask

    // ── Tasks (same interface as tb_ahb_interface) ────────────────
    task push_req(input [31:0] addr, wdata, input write, input [1:0] size);
        @(negedge clk_1g);
        req_wr_en   = 1;
        req_wr_data = {addr, wdata, write, size};
        @(posedge clk_1g);
        @(negedge clk_1g);
        req_wr_en   = 0;
    endtask

    task wait_resp(output logic [31:0] rdata, output logic err);
        while (resp_rd_empty) @(posedge clk_1g);
        @(negedge clk_1g);
        rdata      = resp_rd_data[31:0];
        err        = resp_rd_data[32];
        resp_rd_en = 1;
        @(posedge clk_1g);
        @(negedge clk_1g);
        resp_rd_en = 0;
    endtask

    task do_txn(
        input  [31:0] addr, wdata,
        input         write,
        input  [1:0]  size,
        output [31:0] rdata,
        output        err
    );
        logic [31:0] r;
        logic        e;
        push_req(addr, wdata, write, size);
        wait_resp(r, e);
        rdata = r; err = e;
    endtask

    // ── Main ──────────────────────────────────────────────────────
    logic [31:0] rdata;
    logic        err;

    initial begin
        pass_cnt=0; fail_cnt=0; tnum=0;
        req_wr_en=0; req_wr_data=0;
        resp_rd_en=0;
        rst_1g_n=0; rst_ahb_n=0;
        repeat(10) @(posedge clk_1g);
        @(negedge clk_1g);
        rst_1g_n=1; rst_ahb_n=1;
        repeat(4) @(posedge clk_1g);

        // ── Group 1: Address decode — each slave independently ───
        // Slave 0 (addr[27:12]=0x0000, base=0x3000_0000)
        tnum=tnum+1;
        do_txn(32'h3000_0000, 32'hAABB_CCDD, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);

        tnum=tnum+1;
        do_txn(32'h3000_0000, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err   === 1'b0);
        tnum=tnum+1;
        pass_if(rdata === 32'hAABB_CCDD);

        // Slave 1 (addr[27:12]=0x0001, base=0x3000_1000)
        tnum=tnum+1;
        do_txn(32'h3000_1000, 32'h1122_3344, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);

        tnum=tnum+1;
        do_txn(32'h3000_1000, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err   === 1'b0);
        tnum=tnum+1;
        pass_if(rdata === 32'h1122_3344);

        // Slave 2 (addr[27:12]=0x0002, base=0x3000_2000)
        tnum=tnum+1;
        do_txn(32'h3000_2000, 32'h5566_7788, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);

        tnum=tnum+1;
        do_txn(32'h3000_2000, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err   === 1'b0);
        tnum=tnum+1;
        pass_if(rdata === 32'h5566_7788);

        // ── Group 2: IRQ path — REG7[0] (offset 0x1C, addr[4:2]=7) ──
        // Write S0 REG7[0]=1
        tnum=tnum+1;
        do_txn(32'h3000_001C, 32'h0000_0001, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        repeat(2) @(posedge clk_ahb);                // settle 500MHz domain
        tnum=tnum+1; pass_if(ahb_irq === 1'b1);

        // Write S1 REG7[0]=1 → ahb_irq still 1 (OR)
        tnum=tnum+1;
        do_txn(32'h3000_101C, 32'h0000_0001, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        repeat(2) @(posedge clk_ahb);
        tnum=tnum+1; pass_if(ahb_irq === 1'b1);

        // Clear S0 → ahb_irq still 1 (S1 still set)
        tnum=tnum+1;
        do_txn(32'h3000_001C, 32'h0000_0000, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        repeat(2) @(posedge clk_ahb);
        tnum=tnum+1; pass_if(ahb_irq === 1'b1);

        // Clear S1 → ahb_irq=0
        tnum=tnum+1;
        do_txn(32'h3000_101C, 32'h0000_0000, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        repeat(2) @(posedge clk_ahb);
        tnum=tnum+1; pass_if(ahb_irq === 1'b0);

        // Write S2 REG7[0]=1 → ahb_irq=1
        tnum=tnum+1;
        do_txn(32'h3000_201C, 32'h0000_0001, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        repeat(2) @(posedge clk_ahb);
        tnum=tnum+1; pass_if(ahb_irq === 1'b1);

        // Clear S2 → ahb_irq=0
        tnum=tnum+1;
        do_txn(32'h3000_201C, 32'h0000_0000, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        repeat(2) @(posedge clk_ahb);
        tnum=tnum+1; pass_if(ahb_irq === 1'b0);

        // ── Group 3: Multiple regs in Slave 1 ────────────────────
        tnum=tnum+1;
        do_txn(32'h3000_1004, 32'hDEAD_BEEF, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1;
        do_txn(32'h3000_1008, 32'hCAFE_BABE, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);

        tnum=tnum+1;
        do_txn(32'h3000_1004, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1; pass_if(rdata === 32'hDEAD_BEEF);

        tnum=tnum+1;
        do_txn(32'h3000_1008, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1; pass_if(rdata === 32'hCAFE_BABE);

        // ── Group 4: Cross-slave isolation ───────────────────────
        // Write same reg index to S0 and S2 with different values
        tnum=tnum+1;
        do_txn(32'h3000_0004, 32'hF0F0_AAAA, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1;
        do_txn(32'h3000_2004, 32'h0F0F_BBBB, 1'b1, 2'b10, rdata, err);
        pass_if(err === 1'b0);

        // Read S0 reg1 — must see F0F0_AAAA
        tnum=tnum+1;
        do_txn(32'h3000_0004, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1; pass_if(rdata === 32'hF0F0_AAAA);

        // Read S2 reg1 — must see 0F0F_BBBB
        tnum=tnum+1;
        do_txn(32'h3000_2004, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1; pass_if(rdata === 32'h0F0F_BBBB);

        // S0 reg0 must still be from Group 1 (no S2 write affected S0)
        tnum=tnum+1;
        do_txn(32'h3000_0000, 32'd0, 1'b0, 2'b10, rdata, err);
        pass_if(err === 1'b0);
        tnum=tnum+1; pass_if(rdata === 32'hAABB_CCDD);

        $display("=== tb_ahb_full: %0d/%0d PASS ===", pass_cnt, pass_cnt+fail_cnt);
        if (fail_cnt==0) $display("ALL PASS");
        $finish;
    end

    initial begin #300000; $display("TIMEOUT"); $fatal(1,"tb_ahb_full TIMEOUT"); end
endmodule
