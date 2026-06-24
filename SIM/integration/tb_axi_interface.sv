`timescale 1ns/1ps
module tb_axi_interface;
    // ── Clocks / Reset ──────────────────────────────────────────
    logic clk, rst_n;
    initial clk = 0;
    always #0.5 clk = ~clk;

    // ── CPU-side signals ────────────────────────────────────────
    logic        req_valid, req_we;
    logic [31:0] req_addr, req_wdata;
    logic [1:0]  req_size;
    logic        resp_valid;
    logic [31:0] resp_rdata;
    logic        resp_err;

    // ── AXI bus ─────────────────────────────────────────────────
    logic [31:0] AWADDR, WDATA, ARADDR, RDATA;
    logic [3:0]  WSTRB;
    logic        AWVALID, AWREADY, WVALID, WREADY;
    logic [1:0]  BRESP;
    logic        BVALID, BREADY;
    logic        ARVALID, ARREADY;
    logic [1:0]  RRESP;
    logic        RVALID, RREADY;
    logic        inject_bresp_err, inject_rresp_err;

    // ── DUT ─────────────────────────────────────────────────────
    axi_interface u_dut (
        .clk(clk), .rst_n(rst_n),
        .axi_req_valid(req_valid), .axi_req_addr(req_addr),
        .axi_req_we(req_we),       .axi_req_wdata(req_wdata),
        .axi_req_size(req_size),
        .axi_resp_valid(resp_valid), .axi_resp_rdata(resp_rdata),
        .axi_resp_err(resp_err),
        .AWADDR(AWADDR), .AWPROT(), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA),   .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP),   .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARPROT(), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA),   .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY)
    );

    // ── Slave ───────────────────────────────────────────────────
    axi_slave_model u_slave (
        .clk(clk), .rst_n(rst_n),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA),   .WSTRB(WSTRB),     .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP),   .BVALID(BVALID),   .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA),   .RRESP(RRESP),     .RVALID(RVALID), .RREADY(RREADY),
        .inject_bresp_err(inject_bresp_err),
        .inject_rresp_err(inject_rresp_err)
    );

    // ── AXI signal capture (synchronous: same clock) ─────────────
    // Latched on posedge when handshake fires; valid when resp_valid is seen
    logic [31:0] cap_wdata, cap_awaddr, cap_araddr;
    always @(posedge clk) begin
        if (AWVALID && AWREADY) cap_awaddr <= AWADDR;
        if (WVALID  && WREADY)  cap_wdata  <= WDATA;
        if (ARVALID && ARREADY) cap_araddr <= ARADDR;
    end

    // ── Scoreboard ───────────────────────────────────────────────
    int pass_cnt, fail_cnt;
    int tnum;

    task pass_if(input logic ok);
        if (!ok) begin
            $display("FAIL T%0d", tnum);
            fail_cnt = fail_cnt + 1;
        end else pass_cnt = pass_cnt + 1;
    endtask

    // ── Write task ───────────────────────────────────────────────
    task do_write(
        input [31:0] addr, wdata,
        input [1:0]  size,
        input [3:0]  exp_wstrb,
        input        exp_err
    );
        @(negedge clk);
        req_valid = 1; req_we = 1;
        req_addr  = addr; req_wdata = wdata; req_size = size;
        @(posedge clk);
        while (!resp_valid) @(posedge clk);
        tnum = tnum + 1;
        pass_if(WSTRB    === exp_wstrb);
        tnum = tnum + 1;
        pass_if(resp_err === exp_err);
        @(negedge clk);
        req_valid = 0; req_we = 0;
        @(posedge clk);
    endtask

    // ── Read task ────────────────────────────────────────────────
    task do_read(
        input [31:0] addr, exp_rdata,
        input        exp_err
    );
        @(negedge clk);
        req_valid = 1; req_we = 0;
        req_addr  = addr; req_size = 2'b10;
        @(posedge clk);
        while (!resp_valid) @(posedge clk);
        tnum = tnum + 1;
        pass_if(resp_rdata === exp_rdata);
        tnum = tnum + 1;
        pass_if(resp_err   === exp_err);
        @(negedge clk);
        req_valid = 0;
        @(posedge clk);
    endtask

    // ── Main ─────────────────────────────────────────────────────
    initial begin
        pass_cnt = 0; fail_cnt = 0; tnum = 0;
        req_valid = 0; req_we = 0; req_addr = 0; req_wdata = 0; req_size = 2'b10;
        inject_bresp_err = 0; inject_rresp_err = 0;
        rst_n = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // T1-T2: Word write → WSTRB=1111, no error
        do_write(32'h2000_0000, 32'hDEAD_BEEF, 2'b10, 4'b1111, 1'b0);

        // T3-T4: Word read-back → RDATA=DEADBEEF
        do_read(32'h2000_0000, 32'hDEAD_BEEF, 1'b0);

        // T5-T6: Second write+read
        do_write(32'h2000_0004, 32'hCAFE_F00D, 2'b10, 4'b1111, 1'b0);
        do_read(32'h2000_0004, 32'hCAFE_F00D, 1'b0);

        // T7-T8: Half-word at byte-offset 0 → WSTRB=0011
        do_write(32'h2000_0008, 32'h0000_ABCD, 2'b01, 4'b0011, 1'b0);

        // T9-T10: Half-word at byte-offset 2 → WSTRB=1100
        do_write(32'h2000_000A, 32'h0000_1234, 2'b01, 4'b1100, 1'b0);

        // T11-T14: Byte writes at offsets 0-3
        do_write(32'h2000_000C, 32'h0000_00AA, 2'b00, 4'b0001, 1'b0);
        do_write(32'h2000_000D, 32'h0000_00BB, 2'b00, 4'b0010, 1'b0);
        do_write(32'h2000_000E, 32'h0000_00CC, 2'b00, 4'b0100, 1'b0);
        do_write(32'h2000_000F, 32'h0000_00DD, 2'b00, 4'b1000, 1'b0);

        // T15-T16: BRESP error → resp_err=1
        inject_bresp_err = 1;
        do_write(32'h2000_0010, 32'h1234_5678, 2'b10, 4'b1111, 1'b1);
        inject_bresp_err = 0;

        // T17-T18: RRESP error → resp_err=1
        inject_rresp_err = 1;
        do_read(32'h2000_0000, 32'hDEAD_BEEF, 1'b1);
        inject_rresp_err = 0;

        // ── Group 2: WDATA alignment (DUT replicates data to fill 32 bits) ──

        // T19: Word write → WDATA = req_wdata unchanged
        do_write(32'h2000_0020, 32'hBEEF_CAFE, 2'b10, 4'b1111, 1'b0);
        tnum = tnum + 1; pass_if(cap_wdata === 32'hBEEF_CAFE);

        // T20: Half-word at byte-offset 0 → WDATA = {wdata[15:0], wdata[15:0]}
        do_write(32'h2000_0024, 32'h0000_FACE, 2'b01, 4'b0011, 1'b0);
        tnum = tnum + 1; pass_if(cap_wdata === 32'hFACE_FACE);

        // T21: Half-word at byte-offset 2 → WDATA = {wdata[15:0], wdata[15:0]} (same replication)
        do_write(32'h2000_0026, 32'h0000_BABE, 2'b01, 4'b1100, 1'b0);
        tnum = tnum + 1; pass_if(cap_wdata === 32'hBABE_BABE);

        // T22: Byte at offset 0 → WDATA = {byte×4}
        do_write(32'h2000_0028, 32'h0000_0042, 2'b00, 4'b0001, 1'b0);
        tnum = tnum + 1; pass_if(cap_wdata === 32'h4242_4242);

        // T23: Byte at offset 1 → WDATA = {byte×4}
        do_write(32'h2000_0029, 32'h0000_00AB, 2'b00, 4'b0010, 1'b0);
        tnum = tnum + 1; pass_if(cap_wdata === 32'hABAB_ABAB);

        // ── Group 3: Address propagation ─────────────────────────

        // T24: AWADDR must equal the request address
        do_write(32'h2000_002C, 32'hDEAD_C0DE, 2'b10, 4'b1111, 1'b0);
        tnum = tnum + 1; pass_if(cap_awaddr === 32'h2000_002C);

        // T25: ARADDR must equal the request address
        do_read(32'h2000_002C, 32'hDEAD_C0DE, 1'b0);
        tnum = tnum + 1; pass_if(cap_araddr === 32'h2000_002C);

        // ── Group 4: Sequential write-then-read ──────────────────

        // T26-T27: Write to reg 8, read back (new slot not touched before)
        do_write(32'h2000_0030, 32'h5A5A_A5A5, 2'b10, 4'b1111, 1'b0);
        do_read(32'h2000_0030, 32'h5A5A_A5A5, 1'b0);

        $display("=== tb_axi_interface: %0d/%0d PASS ===",
                 pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) $display("ALL PASS");
        $finish;
    end

    initial begin
        #5000;
        $display("TIMEOUT");
        $fatal(1, "tb_axi_interface TIMEOUT");
    end
endmodule
