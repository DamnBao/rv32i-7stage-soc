`timescale 1ns/1ps
// Unit test for zicsr.sv — drives WB-stage inputs directly, checks CSR outputs.
// Does not need the full pipeline; tests CSR read/write, exceptions, interrupts, MRET.
module tb_zicsr;

    logic        clk, rst_n;

    // WB-stage inputs
    logic [31:0] wb_pc;
    logic [31:0] wb_rs1_data;
    logic [31:0] wb_imm;
    logic [11:0] wb_csr_addr;
    logic        wb_csr_we;
    logic [1:0]  wb_csr_op;
    logic        wb_csr_imm_sel;
    logic        wb_ecall, wb_ebreak, wb_mret;
    logic        wb_illegal_instr, wb_load_fault, wb_store_fault;

    // External
    logic        meip_in;
    logic        bus_stall_req;

    // Outputs
    logic [31:0] csr_rdata;
    logic        zicsr_flush;
    logic [31:0] zicsr_pc;

    zicsr dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .wb_pc           (wb_pc),
        .wb_rs1_data     (wb_rs1_data),
        .wb_imm          (wb_imm),
        .wb_csr_addr     (wb_csr_addr),
        .wb_csr_we       (wb_csr_we),
        .wb_csr_op       (wb_csr_op),
        .wb_csr_imm_sel  (wb_csr_imm_sel),
        .wb_ecall        (wb_ecall),
        .wb_ebreak       (wb_ebreak),
        .wb_mret         (wb_mret),
        .wb_illegal_instr(wb_illegal_instr),
        .wb_load_fault   (wb_load_fault),
        .wb_store_fault  (wb_store_fault),
        .meip_in         (meip_in),
        .bus_stall_req   (bus_stall_req),
        .csr_rdata       (csr_rdata),
        .zicsr_flush     (zicsr_flush),
        .zicsr_pc        (zicsr_pc)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;

    int pass_cnt = 0, fail_cnt = 0;

    // CSR addresses
    localparam CSR_MSTATUS = 12'h300;
    localparam CSR_MIE     = 12'h304;
    localparam CSR_MTVEC   = 12'h305;
    localparam CSR_MEPC    = 12'h341;
    localparam CSR_MCAUSE  = 12'h342;
    localparam CSR_MIP     = 12'h344;

    task check32(input string msg, input [31:0] exp, got);
        if (got === exp) begin
            $display("  PASS  %-46s exp=%08h got=%08h", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-46s exp=%08h got=%08h", msg, exp, got);
            fail_cnt++;
        end
    endtask

    task check1(input string msg, input logic exp, got);
        if (got === exp) begin
            $display("  PASS  %-46s exp=%b got=%b", msg, exp, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-46s exp=%b got=%b", msg, exp, got);
            fail_cnt++;
        end
    endtask

    // Read a CSR: drive csr_addr for 1 cycle, capture csr_rdata (combinational)
    task csr_read(input [11:0] addr, output [31:0] val);
        wb_csr_addr = addr;
        #0.1;
        val = csr_rdata;
    endtask

    // Write a CSR via CSRRW (op=01) at next posedge
    task csr_write(input [11:0] addr, input [31:0] val);
        @(negedge clk);
        wb_csr_addr = addr;
        wb_rs1_data = val;
        wb_csr_op   = 2'b01;  // CSRRW
        wb_csr_we   = 1'b1;
        wb_csr_imm_sel = 1'b0;
        @(posedge clk); #0.1;
        wb_csr_we = 1'b0;
        @(negedge clk);
    endtask

    // Drive an idle NOP for 1 cycle
    task nop_cycle();
        @(negedge clk);
        wb_csr_we = 0; wb_csr_op = 2'b00;
        wb_ecall = 0; wb_ebreak = 0; wb_mret = 0;
        wb_illegal_instr = 0; wb_load_fault = 0; wb_store_fault = 0;
        @(posedge clk); #0.1;
        @(negedge clk);
    endtask

    logic [31:0] rd;

    initial begin
        $display("=== tb_zicsr ===");

        // Default idle inputs
        wb_pc = 32'd0; wb_rs1_data = 32'd0; wb_imm = 32'd0;
        wb_csr_addr = 12'd0; wb_csr_we = 0; wb_csr_op = 2'b00;
        wb_csr_imm_sel = 0;
        wb_ecall = 0; wb_ebreak = 0; wb_mret = 0;
        wb_illegal_instr = 0; wb_load_fault = 0; wb_store_fault = 0;
        meip_in = 0; bus_stall_req = 0;

        // Reset
        rst_n = 0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(2) @(posedge clk);

        // ------ G1: Reset values ------
        $display("--- G1: Reset state ---");
        csr_read(CSR_MSTATUS, rd);
        check32("T1: mstatus reset=0x1800 (MPP=11)", 32'h0000_1800, rd);
        csr_read(CSR_MIE, rd);
        check32("T2: mie reset=0", 32'd0, rd);
        csr_read(CSR_MTVEC, rd);
        check32("T3: mtvec reset=0", 32'd0, rd);
        csr_read(CSR_MEPC, rd);
        check32("T4: mepc reset=0", 32'd0, rd);
        csr_read(CSR_MCAUSE, rd);
        check32("T5: mcause reset=0", 32'd0, rd);
        check1("T6: flush=0 at reset", 1'b0, zicsr_flush);

        // ------ G2: CSRRW — write mtvec ------
        $display("--- G2: CSRRW write ---");
        csr_write(CSR_MTVEC, 32'hC000_0001);  // vectored (bit0=1)
        csr_read(CSR_MTVEC, rd);
        check32("T7: mtvec written", 32'hC000_0001, rd);

        // ------ G3: CSRRS — set bits in mie ------
        $display("--- G3: CSRRS set bits ---");
        @(negedge clk);
        wb_csr_addr = CSR_MIE;
        wb_rs1_data = 32'h0000_0888;  // set MEIE[11] + MTIE[7] + MSIE[3]
        wb_csr_op   = 2'b10;           // CSRRS
        wb_csr_we   = 1'b1;
        @(posedge clk); #0.1;
        wb_csr_we = 0;
        csr_read(CSR_MIE, rd);
        check32("T8: mie bits set", 32'h0000_0888, rd);
        @(negedge clk);

        // ------ G4: CSRRC — clear bits ------
        $display("--- G4: CSRRC clear bits ---");
        @(negedge clk);
        wb_csr_addr = CSR_MIE;
        wb_rs1_data = 32'h0000_0080;  // clear MTIE[7]
        wb_csr_op   = 2'b11;          // CSRRC
        wb_csr_we   = 1'b1;
        @(posedge clk); #0.1;
        wb_csr_we = 0;
        csr_read(CSR_MIE, rd);
        check32("T9: MTIE cleared (MEIE+MSIE remain)", 32'h0000_0808, rd);
        @(negedge clk);

        // ------ G5: CSRRWI (immediate) ------
        $display("--- G5: CSRRWI immediate ---");
        @(negedge clk);
        wb_csr_addr    = CSR_MIE;
        wb_imm         = 32'd15;    // zimm=15 → {27'd0, 5'd15}
        wb_csr_op      = 2'b01;    // CSRRWI (same op, imm_sel=1)
        wb_csr_imm_sel = 1'b1;
        wb_csr_we      = 1'b1;
        @(posedge clk); #0.1;
        wb_csr_we = 0; wb_csr_imm_sel = 0;
        csr_read(CSR_MIE, rd);
        check32("T10: mie = zimm(15) = 0x0F", 32'h0000_000F, rd);
        @(negedge clk);

        // Restore mie: set MEIE only
        csr_write(CSR_MIE, 32'h0000_0800);

        // ------ G6: ECALL exception ------
        $display("--- G6: ECALL exception ---");
        // Set mtvec first (direct mode, base=0x1000)
        csr_write(CSR_MTVEC, 32'h0000_1000);
        @(negedge clk);
        wb_pc    = 32'h0000_0100;  // faulting PC
        wb_ecall = 1'b1;
        @(posedge clk); #0.1;
        check1("T11: flush on ecall",         1'b1, zicsr_flush);
        check32("T12: trap vector = mtvec_base", 32'h0000_1000, zicsr_pc);
        wb_ecall = 0;
        csr_read(CSR_MEPC,   rd); check32("T13: mepc=wb_pc", 32'h0000_0100, rd);
        csr_read(CSR_MCAUSE, rd); check32("T14: mcause=11 (ecall)", 32'd11, rd);
        csr_read(CSR_MSTATUS,rd); check32("T15: mstatus trap (MIE=0,MPIE=0,MPP=11)", 32'h0000_1800, rd);
        @(negedge clk);

        // ------ G7: MRET ------
        $display("--- G7: MRET ---");
        // Set mepc to known value
        csr_write(CSR_MEPC, 32'h0000_0200);
        // Set mstatus.MPIE=1 (bit7)
        csr_write(CSR_MSTATUS, 32'h0000_1880);  // MPIE=1, MPP=11
        @(negedge clk);
        wb_mret = 1'b1;
        @(posedge clk); #0.1;
        check1("T16: flush on mret", 1'b1, zicsr_flush);
        check32("T17: zicsr_pc = mepc", 32'h0000_0200, zicsr_pc);
        wb_mret = 0;
        // mstatus after mret: MIE=MPIE(1), MPIE=1, MPP=11
        csr_read(CSR_MSTATUS, rd);
        check32("T18: mstatus after mret (MIE=1,MPIE=1,MPP=11)", 32'h0000_1888, rd);
        @(negedge clk);

        // ------ G8: Load fault exception ------
        $display("--- G8: Load fault ---");
        @(negedge clk);
        wb_pc         = 32'h0000_0050;
        wb_load_fault = 1'b1;
        @(posedge clk); #0.1;
        check1("T19: flush on load_fault", 1'b1, zicsr_flush);
        wb_load_fault = 0;
        csr_read(CSR_MCAUSE, rd); check32("T20: mcause=5 (load fault)", 32'd5, rd);
        csr_read(CSR_MEPC,   rd); check32("T21: mepc=faulting pc", 32'h0000_0050, rd);
        @(negedge clk);

        // ------ G9: Store fault ------
        $display("--- G9: Store fault ---");
        @(negedge clk);
        wb_pc          = 32'h0000_0060;
        wb_store_fault = 1'b1;
        @(posedge clk); #0.1;
        check1("T22: flush on store_fault", 1'b1, zicsr_flush);
        wb_store_fault = 0;
        csr_read(CSR_MCAUSE, rd); check32("T23: mcause=7 (store fault)", 32'd7, rd);
        @(negedge clk);

        // ------ G10: Illegal instruction ------
        $display("--- G10: Illegal instruction ---");
        @(negedge clk);
        wb_pc              = 32'h0000_0070;
        wb_illegal_instr   = 1'b1;
        @(posedge clk); #0.1;
        check1("T24: flush on illegal", 1'b1, zicsr_flush);
        wb_illegal_instr = 0;
        csr_read(CSR_MCAUSE, rd); check32("T25: mcause=2 (illegal)", 32'd2, rd);
        @(negedge clk);

        // ------ G11: MEI interrupt (meip_in) ------
        $display("--- G11: MEI interrupt ---");
        csr_write(CSR_MSTATUS, 32'h0000_1808);  // MIE=1, MPP=11
        csr_write(CSR_MIE,     32'h0000_0800);  // MEIE=1
        csr_write(CSR_MTVEC, 32'h0000_2001);    // vectored, base=0x2000
        @(negedge clk);
        wb_pc   = 32'h0000_0080;
        meip_in = 1'b1;  // PLIC asserts meip
        // Check flush BEFORE #0.1 (active region, pre-NBA: mstatus.MIE still 1).
        // After #0.1 NBA commits mstatus.MIE=0 → take_interrupt=0 → flush=0.
        @(posedge clk);
        check1("T26: flush on MEI",                       1'b1, zicsr_flush);
        check32("T27: zicsr_pc = BASE+44 (MEI vectored)", 32'h0000_202C, zicsr_pc);
        #0.1;
        meip_in = 0;
        // NB committed: mepc, mcause, mstatus now reflect trap state
        csr_read(CSR_MEPC,   rd); check32("T28: mepc = wb_pc+4",        32'h0000_0084, rd);
        csr_read(CSR_MCAUSE, rd); check32("T29: mcause=0x8000000B",     32'h8000_000B, rd);
        csr_read(CSR_MSTATUS,rd); check32("T30: mstatus MIE=0 in handler", 32'h0000_1880, rd);
        @(negedge clk);

        // ------ G12: MSI interrupt ------
        $display("--- G12: MSI interrupt ---");
        csr_write(CSR_MSTATUS, 32'h0000_1888);  // MIE=1, MPIE=1, MPP=11
        csr_write(CSR_MIE,     32'h0000_0008);  // MSIE=1 only
        @(negedge clk);
        wb_pc   = 32'h0000_0090;
        // Write mip.MSIP=1: NB commits reg_msip=1 at posedge → combinatorial
        // take_interrupt=1 visible at #0.1 (after NBA, mstatus.MIE still 1 here
        // because the interrupt fires at the NEXT posedge, not this one).
        wb_csr_addr = CSR_MIP;
        wb_rs1_data = 32'h0000_0008;  // MSIP bit3=1
        wb_csr_op   = 2'b01;
        wb_csr_we   = 1'b1;
        @(posedge clk); #0.1;   // P_write: reg_msip←1, mstatus unchanged
        wb_csr_we = 0;
        // Combinatorial take_interrupt=1 now that reg_msip=1
        check1("T31: flush on MSI", 1'b1, zicsr_flush);
        check32("T32: zicsr_pc = mtvec_base+12 (MSI vectored)", 32'h0000_200C, zicsr_pc);
        // Interrupt fires at NEXT posedge (reg_msip=1 at P_write+1 start)
        @(posedge clk); #0.1;   // P_write+1: take_interrupt=1, NB commits trap state
        csr_read(CSR_MCAUSE, rd); check32("T33: mcause=0x80000003", 32'h8000_0003, rd);
        // Clear MSIP (mstatus.MIE already 0 after interrupt, so no re-trigger)
        wb_csr_addr = CSR_MIP;
        wb_rs1_data = 32'd0;
        wb_csr_op   = 2'b01;
        wb_csr_we   = 1'b1;
        @(posedge clk); #0.1;
        wb_csr_we = 0;
        @(negedge clk);

        // ------ G13: bus_stall_req suppresses exception ------
        $display("--- G13: bus_stall_req suppresses trap ---");
        csr_write(CSR_MSTATUS, 32'h0000_1808);  // MIE=1
        @(negedge clk);
        bus_stall_req = 1'b1;
        wb_pc         = 32'h0000_00A0;
        wb_ecall      = 1'b1;
        @(posedge clk); #0.1;
        check1("T34: flush=0 when bus_stall_req", 1'b0, zicsr_flush);
        wb_ecall = 0; bus_stall_req = 0;
        @(negedge clk);

        // ------ G14: Exception priority over interrupt ------
        $display("--- G14: Exception > interrupt priority ---");
        csr_write(CSR_MSTATUS, 32'h0000_1808);  // MIE=1
        csr_write(CSR_MIE,     32'h0000_0800);  // MEIE=1
        @(negedge clk);
        wb_pc     = 32'h0000_00B0;
        wb_ecall  = 1'b1;
        meip_in   = 1'b1;   // both exception and interrupt
        @(posedge clk); #0.1;
        check1("T35: flush fires", 1'b1, zicsr_flush);
        // Exception wins: mcause = 11 (ecall), not 0x8000000B
        csr_read(CSR_MCAUSE, rd);
        check32("T36: ecall wins over MEI (cause=11)", 32'd11, rd);
        wb_ecall = 0; meip_in = 0;
        @(negedge clk);

        // ------ G15: MIP read-back ------
        $display("--- G15: MIP read-back ---");
        // Write mip.MSIP=1
        csr_write(CSR_MIP, 32'h0000_0008);
        csr_read(CSR_MIP, rd);
        // mip_val = {20'b0, meip, 3'b0, 0, 3'b0, msip, 3'b0}
        // meip=0, msip=1 → bit3=1
        check32("T37: mip.MSIP=1 readable", 32'h0000_0008, rd);
        // meip_in=1 → mip.MEIP=1 (read-only)
        meip_in = 1'b1;
        #0.1;
        csr_read(CSR_MIP, rd);
        check32("T38: mip.MEIP=1 from meip_in", 32'h0000_0808, rd);
        meip_in = 0;
        @(negedge clk);

        $display("===========================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("tb_zicsr: ALL PASSED");
        else               $display("tb_zicsr: SOME FAILED");
        $finish;
    end
endmodule
