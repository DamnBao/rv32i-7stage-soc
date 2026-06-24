`timescale 1ns/1ps
module tb_ahb_interface;
    // ── Clocks / Resets ──────────────────────────────────────────
    logic clk_1g, clk_ahb;
    logic rst_1g_n, rst_ahb_n;

    initial clk_1g = 0;
    always #0.5 clk_1g = ~clk_1g;                           // 1GHz

    initial begin clk_ahb = 0; #0.7; forever #1.0 clk_ahb = ~clk_ahb; end  // 500MHz

    // ── Request FIFO (1GHz write → 500MHz read) ──────────────────
    // Payload: {addr[31:0], wdata[31:0], write[0], size[1:0]} = 67 bits
    logic        req_wr_en;
    logic [66:0] req_wr_data;
    logic        req_rd_en, req_rd_empty;
    logic [66:0] req_rd_data;

    async_fifo_depth2 #(.DATA_WIDTH(67)) u_req_fifo (
        .wr_clk  (clk_1g),    .wr_rst_n(rst_1g_n),
        .wr_en   (req_wr_en), .wr_data (req_wr_data),
        .rd_clk  (clk_ahb),   .rd_rst_n(rst_ahb_n),
        .rd_en   (req_rd_en), .rd_data (req_rd_data),
        .rd_empty(req_rd_empty)
    );

    // ── Response FIFO (500MHz write → 1GHz read) ─────────────────
    // Payload: {HRESP[0], HRDATA[31:0]} = 33 bits
    logic        resp_wr_en;
    logic [32:0] resp_wr_data;
    logic        resp_rd_en, resp_rd_empty;
    logic [32:0] resp_rd_data;

    async_fifo_depth2 #(.DATA_WIDTH(33)) u_resp_fifo (
        .wr_clk  (clk_ahb),    .wr_rst_n(rst_ahb_n),
        .wr_en   (resp_wr_en), .wr_data (resp_wr_data),
        .rd_clk  (clk_1g),    .rd_rst_n(rst_1g_n),
        .rd_en   (resp_rd_en), .rd_data (resp_rd_data),
        .rd_empty(resp_rd_empty)
    );

    // ── AHB bus wires ─────────────────────────────────────────────
    logic [31:0] HADDR, HWDATA, HRDATA;
    logic [2:0]  HSIZE;
    logic [1:0]  HTRANS;
    logic        HWRITE, HREADY, HRESP;

    // ── AHB Interface DUT ─────────────────────────────────────────
    ahb_interface u_dut (
        .clk_ahb    (clk_ahb),
        .rst_ahb_n  (rst_ahb_n),
        .req_empty  (req_rd_empty),
        .req_rd_en  (req_rd_en),
        .req_rd_data(req_rd_data),
        .resp_wr_en  (resp_wr_en),
        .resp_wr_data(resp_wr_data),
        .HADDR (HADDR), .HSIZE (HSIZE), .HTRANS(HTRANS),
        .HWRITE(HWRITE),.HWDATA(HWDATA),
        .HREADY(HREADY),.HRDATA(HRDATA),.HRESP (HRESP)
    );

    // ── AHB Slave Model ───────────────────────────────────────────
    logic inject_err, insert_wait;
    ahb_slave_model u_slave (
        .clk_ahb   (clk_ahb),
        .rst_ahb_n (rst_ahb_n),
        .HADDR (HADDR), .HSIZE (HSIZE), .HTRANS(HTRANS),
        .HWRITE(HWRITE),.HWDATA(HWDATA),
        .HREADY(HREADY),.HRDATA(HRDATA),.HRESP (HRESP),
        .inject_err(inject_err),
        .insert_wait(insert_wait)
    );

    // ── Scoreboard ────────────────────────────────────────────────
    int pass_cnt, fail_cnt;

    task chk(input string tag, input logic got, exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got %b, exp %b", tag, got, exp);
            fail_cnt = fail_cnt + 1;
        end else pass_cnt = pass_cnt + 1;
    endtask

    task chk3(input string tag, input logic [2:0] got, exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got %0d, exp %0d", tag, got, exp);
            fail_cnt = fail_cnt + 1;
        end else pass_cnt = pass_cnt + 1;
    endtask

    task chk32(input string tag, input logic [31:0] got, exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got %08X, exp %08X", tag, got, exp);
            fail_cnt = fail_cnt + 1;
        end else pass_cnt = pass_cnt + 1;
    endtask

    // ── AHB signal capture (500MHz domain) ───────────────────────
    // Captured at address-phase (HTRANS=NONSEQ) and data-phase completion
    logic [2:0]  cap_hsize;
    logic        cap_hwrite;
    logic [31:0] cap_haddr, cap_hwdata;

    always @(posedge clk_ahb) begin
        if (HTRANS == 2'b10) begin                    // address phase
            cap_hsize  <= HSIZE;
            cap_hwrite <= HWRITE;
            cap_haddr  <= HADDR;
        end
        if (u_dut.state == 1'b1 && HREADY)           // data phase complete (HREADY=1)
            cap_hwdata <= HWDATA;
    end

    // ── Tasks ─────────────────────────────────────────────────────
    // Push one request into req FIFO from 1GHz side (1-cycle write pulse)
    task push_req(input [31:0] addr, wdata, input write, input [1:0] size);
        @(negedge clk_1g);
        req_wr_en   = 1;
        req_wr_data = {addr, wdata, write, size};
        @(posedge clk_1g);
        @(negedge clk_1g);
        req_wr_en   = 0;
    endtask

    // Poll resp FIFO on 1GHz side, latch data before advancing pointer
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

    // Full transaction: push + wait for response
    task do_txn(
        input  [31:0] addr, wdata,
        input         write,
        input  [1:0]  size,
        output [31:0] rdata,
        output        err
    );
        logic [31:0] r;
        logic e;
        push_req(addr, wdata, write, size);
        wait_resp(r, e);
        rdata = r; err = e;
    endtask

    // ── Main ──────────────────────────────────────────────────────
    logic [31:0] rdata;
    logic        err;

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        req_wr_en = 0; req_wr_data = 0;
        resp_rd_en = 0;
        inject_err = 0; insert_wait = 0;
        rst_1g_n = 0; rst_ahb_n = 0;
        repeat(10) @(posedge clk_1g);
        @(negedge clk_1g);
        rst_1g_n = 1; rst_ahb_n = 1;
        repeat(4) @(posedge clk_1g);

        // ── Group 1: Basic transactions ───────────────────────────

        // T1-T4: Word write — err, HSIZE, HWRITE, HWDATA
        do_txn(32'h3000_0000, 32'hAABB_CCDD, 1'b1, 2'b10, rdata, err);
        chk  ("T1 err",    err,       1'b0);
        chk3 ("T2 HSIZE",  cap_hsize, 3'd2);
        chk  ("T3 HWRITE", cap_hwrite,1'b1);
        chk32("T4 HWDATA", cap_hwdata,32'hAABB_CCDD);
        @(posedge clk_1g);

        // T5-T7: Word read-back — err, RDATA, HWRITE=0
        do_txn(32'h3000_0000, 32'd0, 1'b0, 2'b10, rdata, err);
        chk  ("T5 err",    err,       1'b0);
        chk32("T6 RDATA",  rdata,     32'hAABB_CCDD);
        chk  ("T7 HWRITE", cap_hwrite,1'b0);
        @(posedge clk_1g);

        // T8-T9: Half-word write — err, HSIZE=1
        do_txn(32'h3000_0004, 32'h0000_1234, 1'b1, 2'b01, rdata, err);
        chk ("T8 err",   err,       1'b0);
        chk3("T9 HSIZE", cap_hsize, 3'd1);
        @(posedge clk_1g);

        // T10-T11: Byte write — err, HSIZE=0
        do_txn(32'h3000_0008, 32'h0000_00AB, 1'b1, 2'b00, rdata, err);
        chk ("T10 err",   err,       1'b0);
        chk3("T11 HSIZE", cap_hsize, 3'd0);
        @(posedge clk_1g);

        // T12: HRESP error propagates to response FIFO
        inject_err = 1;
        do_txn(32'h3000_000C, 32'd0, 1'b0, 2'b10, rdata, err);
        chk("T12 hresp_err", err, 1'b1);
        inject_err = 0;
        @(posedge clk_1g);

        // T13-T15: Write to addr 0x04, read-back
        do_txn(32'h3000_0004, 32'hDEAD_1234, 1'b1, 2'b10, rdata, err);
        chk("T13 err", err, 1'b0);
        do_txn(32'h3000_0004, 32'd0, 1'b0, 2'b10, rdata, err);
        chk  ("T14 err",   err,   1'b0);
        chk32("T15 RDATA", rdata, 32'hDEAD_1234);
        @(posedge clk_1g);

        // ── Group 2: Wait state (HREADY=0 for 1 cycle) ───────────

        // T16-T18: Word write with wait state
        insert_wait = 1;
        do_txn(32'h3000_0010, 32'hCAFE_BABE, 1'b1, 2'b10, rdata, err);
        chk  ("T16 wait_wr err",    err,        1'b0);
        chk3 ("T17 wait_wr HSIZE",  cap_hsize,  3'd2);
        chk32("T18 wait_wr HWDATA", cap_hwdata, 32'hCAFE_BABE);
        insert_wait = 0;
        @(posedge clk_1g);

        // T19-T20: Read back data written with wait state
        do_txn(32'h3000_0010, 32'd0, 1'b0, 2'b10, rdata, err);
        chk  ("T19 wait_rb err",   err,   1'b0);
        chk32("T20 wait_rb RDATA", rdata, 32'hCAFE_BABE);
        @(posedge clk_1g);

        // T21-T22: Read with wait state
        insert_wait = 1;
        do_txn(32'h3000_0000, 32'd0, 1'b0, 2'b10, rdata, err);
        chk  ("T21 wait_rd err",   err,   1'b0);
        chk32("T22 wait_rd RDATA", rdata, 32'hAABB_CCDD);  // from T1
        insert_wait = 0;
        @(posedge clk_1g);

        // T23: HADDR captured at address phase matches request address
        chk32("T23 HADDR", cap_haddr, 32'h3000_0000);
        @(posedge clk_1g);

        // T24: HRESP error + wait state (err must still propagate correctly)
        inject_err = 1; insert_wait = 1;
        do_txn(32'h3000_0014, 32'd0, 1'b0, 2'b10, rdata, err);
        chk("T24 err+wait", err, 1'b1);
        inject_err = 0; insert_wait = 0;
        @(posedge clk_1g);

        // ── Group 3: Sequential back-to-back transactions ─────────

        // T25-T28: 2 sequential writes, verify both complete independently
        do_txn(32'h3000_0018, 32'h1111_2222, 1'b1, 2'b10, rdata, err);
        chk("T25 seq_w1 err", err, 1'b0);
        do_txn(32'h3000_001C, 32'h3333_4444, 1'b1, 2'b10, rdata, err);
        chk("T26 seq_w2 err", err, 1'b0);
        do_txn(32'h3000_0018, 32'd0, 1'b0, 2'b10, rdata, err);
        chk32("T27 seq_r1", rdata, 32'h1111_2222);
        do_txn(32'h3000_001C, 32'd0, 1'b0, 2'b10, rdata, err);
        chk32("T28 seq_r2", rdata, 32'h3333_4444);
        @(posedge clk_1g);

        // T29: req_rd_en: verify it pulses only when req is available
        //      After last transaction, FIFO should be empty → req_rd_en=0
        repeat(5) @(posedge clk_ahb);
        chk("T29 req_rd_en_idle", req_rd_en, 1'b0);
        @(posedge clk_1g);

        $display("=== tb_ahb_interface: %0d/%0d PASS ===",
                 pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) $display("ALL PASS");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $fatal(1, "tb_ahb_interface TIMEOUT");
    end
endmodule
