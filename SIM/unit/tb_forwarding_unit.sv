`timescale 1ns/1ps

module tb_forwarding_unit;

    // Address control signals
    logic [4:0]  ex_rs1_addr, ex_rs2_addr;
    logic [4:0]  mem1_rd_addr, mem2_rd_addr, wb_rd_addr;
    logic        mem1_reg_write, mem2_reg_write, wb_reg_write;
    logic [1:0]  mem2_wb_sel;

    // Data signals
    logic [31:0] rs1_data_reg, rs2_data_reg;
    logic [31:0] mem1_alu_result;
    logic [31:0] mem2_alu_result, mem2_mem_rdata;
    logic [31:0] wb_wr_data;

    // Outputs
    logic [31:0] rs1_fwd, rs2_fwd;

    forwarding_unit u_dut (
        .ex_rs1_addr    (ex_rs1_addr),
        .ex_rs2_addr    (ex_rs2_addr),
        .mem1_rd_addr   (mem1_rd_addr),
        .mem1_reg_write (mem1_reg_write),
        .mem1_alu_result(mem1_alu_result),
        .mem2_rd_addr   (mem2_rd_addr),
        .mem2_reg_write (mem2_reg_write),
        .mem2_wb_sel    (mem2_wb_sel),
        .mem2_alu_result(mem2_alu_result),
        .mem2_mem_rdata (mem2_mem_rdata),
        .wb_rd_addr     (wb_rd_addr),
        .wb_reg_write   (wb_reg_write),
        .wb_wr_data     (wb_wr_data),
        .rs1_data_reg   (rs1_data_reg),
        .rs2_data_reg   (rs2_data_reg),
        .rs1_fwd        (rs1_fwd),
        .rs2_fwd        (rs2_fwd)
    );

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk(input string name, input logic [31:0] got, exp);
        if (got === exp) begin
            $display("  PASS  %-52s got=0x%08X", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-52s exp=0x%08X got=0x%08X", name, exp, got);
            fail_cnt++;
        end
    endtask

    // Drive all control + data, wait 1 ns for combinational settle
    task automatic drv(
        input logic [4:0]  rs1, rs2,
        input logic [4:0]  m1_rd, m2_rd, wb_rd,
        input logic        m1_we, m2_we, wb_we,
        input logic [1:0]  m2_sel,
        input logic [31:0] d_reg1, d_reg2,
        input logic [31:0] d_m1, d_m2_alu, d_m2_rdata, d_wb
    );
        ex_rs1_addr     = rs1;   ex_rs2_addr     = rs2;
        mem1_rd_addr    = m1_rd; mem1_reg_write  = m1_we;
        mem2_rd_addr    = m2_rd; mem2_reg_write  = m2_we;
        wb_rd_addr      = wb_rd; wb_reg_write    = wb_we;
        mem2_wb_sel     = m2_sel;
        rs1_data_reg    = d_reg1; rs2_data_reg   = d_reg2;
        mem1_alu_result = d_m1;
        mem2_alu_result = d_m2_alu;
        mem2_mem_rdata  = d_m2_rdata;
        wb_wr_data      = d_wb;
        #1;
    endtask

    // Distinct sentinel values for each forwarding source
    localparam D_REG  = 32'h0000_0001;
    localparam D_M1   = 32'hAAAA_0001;
    localparam D_M2A  = 32'hBBBB_0002;  // mem2 alu_result
    localparam D_M2R  = 32'hCCCC_0003;  // mem2 mem_rdata (load)
    localparam D_WB   = 32'hDDDD_0004;

    initial begin
        $display("======= tb_forwarding_unit =======");

        // ── No forward — register file passthrough ──
        $display("--- No forward (register file) ---");
        drv(5'd1, 5'd2,  5'd5, 5'd6, 5'd7,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("No match rs1 → rs1_data_reg",     rs1_fwd, D_REG);
        chk("No match rs2 → rs2_data_reg",     rs2_fwd, D_REG);

        // ── Forward from MEM1 (gap-1) ──
        $display("--- Forward from MEM1 ---");
        drv(5'd3, 5'd3,  5'd3, 5'd3, 5'd3,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("MEM1 wins over MEM2/WB (rs1)",    rs1_fwd, D_M1);
        chk("MEM1 wins over MEM2/WB (rs2)",    rs2_fwd, D_M1);

        drv(5'd3, 5'd9,  5'd3, 5'd9, 5'd9,  0, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("MEM1 we=0 → register file",       rs1_fwd, D_REG);

        // ── Forward from MEM2 — alu result ──
        $display("--- Forward from MEM2 (alu) ---");
        drv(5'd4, 5'd4,  5'd9, 5'd4, 5'd4,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("MEM2 alu wins over WB (rs1)",     rs1_fwd, D_M2A);
        chk("MEM2 alu wins over WB (rs2)",     rs2_fwd, D_M2A);

        // ── Forward from MEM2 — load rdata ──
        $display("--- Forward from MEM2 (load rdata) ---");
        drv(5'd5, 5'd5,  5'd9, 5'd5, 5'd5,  1, 1, 1,  2'b01,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("MEM2 load rdata (rs1)",           rs1_fwd, D_M2R);
        chk("MEM2 load rdata (rs2)",           rs2_fwd, D_M2R);

        // ── Forward from WB ──
        $display("--- Forward from WB ---");
        drv(5'd6, 5'd6,  5'd9, 5'd9, 5'd6,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("WB fwd (rs1)",                    rs1_fwd, D_WB);
        chk("WB fwd (rs2)",                    rs2_fwd, D_WB);

        drv(5'd6, 5'd9,  5'd9, 5'd9, 5'd6,  1, 1, 0,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("WB we=0 → register file",         rs1_fwd, D_REG);

        // ── x0 is never a forwarding target ──
        $display("--- x0 never forwarded ---");
        drv(5'd0, 5'd0,  5'd0, 5'd0, 5'd0,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("rd=0 never fwd rs1",              rs1_fwd, D_REG);
        chk("rd=0 never fwd rs2",              rs2_fwd, D_REG);

        // ── Independent A and B channels ──
        $display("--- Independent A=MEM1, B=MEM2 ---");
        drv(5'd1, 5'd2,  5'd1, 5'd2, 5'd9,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("A=MEM1 simultaneously",           rs1_fwd, D_M1);
        chk("B=MEM2 simultaneously",           rs2_fwd, D_M2A);

        $display("--- Independent A=MEM2, B=WB ---");
        drv(5'd3, 5'd4,  5'd9, 5'd3, 5'd4,  1, 1, 1,  2'b00,
            D_REG, D_REG,  D_M1, D_M2A, D_M2R, D_WB);
        chk("A=MEM2 simultaneously",           rs1_fwd, D_M2A);
        chk("B=WB simultaneously",             rs2_fwd, D_WB);

        $display("==================================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_forwarding_unit: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_forwarding_unit: ALL PASSED");
        $finish;
    end

endmodule
