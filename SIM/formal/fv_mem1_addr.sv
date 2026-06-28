// Formal verification: mem1_stage address decode + misaligned detection
//
// Verifies the MEM1 stage decode logic and the newly-added misaligned
// exception detection under all symbolic inputs and FSM states.
//
// Key assumption:
//   assume(~(mem_read_in & mem_write_in)) — decoder guarantee (proved by fv_decoder
//   P_MEM_MUTEX); injecting both simultaneously is not a reachable pipeline state.
//
// Properties proved (6):
//   P_BUS_MUTEX         : at most one bus interface is requested at a time
//                         (dmem_re/we, axi_req_valid, req_fifo_wr_en are mutually exclusive)
//   P_MISALIGN_BLOCK    : misaligned access → ALL bus request signals = 0
//   P_MISALIGN_LOAD_FLAG: misaligned load  → load_misaligned_out = 1
//   P_MISALIGN_STORE_FLAG: misaligned store → store_misaligned_out = 1
//   P_BYTE_ALWAYS_ALIGNED: mem_size=00 (byte) → misaligned never fires
//   P_FAULT_MUTEX       : load_access_fault & store_access_fault never both asserted
//
// Note: "misaligned AND access-fault for the SAME instruction" is a pipeline-level
// invariant (requires knowing which instruction started a bus transaction) and
// cannot be proved at the mem1_stage module boundary alone.  P_MISALIGN_BLOCK
// already proves the causal guarantee: misaligned instructions never start bus
// transactions, so they cannot generate bus errors.

`timescale 1ns/1ps
module fv_mem1_addr (
    input logic clk,
    input logic rst_n
);

    // ── Symbolic inputs ─────────────────────────────────────────────────
    logic [31:0] addr_in, wdata_in, rs1_data_in, imm_in, pc_in;
    logic [4:0]  rd_addr_in;
    logic [11:0] csr_addr_in;
    logic        mem_read_in, mem_write_in;
    logic [1:0]  mem_size_in;
    logic        mem_ext_in, reg_write_in;
    logic [1:0]  wb_sel_in;
    logic        csr_we_in;
    logic [1:0]  csr_op_in;
    logic        csr_imm_sel_in, ecall_in, ebreak_in, mret_in, illegal_instr_in;

    // AXI response (symbolic)
    logic        axi_resp_valid;
    logic [31:0] axi_resp_rdata;
    logic        axi_resp_err;

    // AHB response FIFO (symbolic)
    logic        resp_fifo_rd_empty;
    logic [32:0] resp_fifo_rd_data;

    // ── DUT outputs ─────────────────────────────────────────────────────
    logic        dmem_re, dmem_we;
    logic [31:0] dmem_addr, dmem_wdata;
    logic [1:0]  dmem_size;
    logic        axi_req_valid;
    logic [31:0] axi_req_addr;
    logic        axi_req_we;
    logic [31:0] axi_req_wdata;
    logic [1:0]  axi_req_size;
    logic        req_fifo_wr_en;
    logic [66:0] req_fifo_wr_data;
    logic        resp_fifo_rd_en;
    logic        plic_re, plic_we;
    logic [23:0] plic_addr;
    logic [31:0] plic_wdata;
    logic        bus_stall_req;
    logic        load_access_fault, store_access_fault;
    logic [31:0] pc_out, alu_result_out, rdata_out, rs1_data_out, imm_out;
    logic [4:0]  rd_addr_out;
    logic [11:0] csr_addr_out;
    logic [1:0]  mem_src_out;
    logic        mem_ext_out;
    logic [1:0]  mem_size_out;
    logic        reg_write_out;
    logic [1:0]  wb_sel_out;
    logic        csr_we_out;
    logic [1:0]  csr_op_out;
    logic        csr_imm_sel_out, ecall_out, ebreak_out, mret_out, illegal_instr_out;
    logic        load_misaligned_out, store_misaligned_out;

    mem1_stage dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .addr_in            (addr_in),
        .wdata_in           (wdata_in),
        .rs1_data_in        (rs1_data_in),
        .imm_in             (imm_in),
        .pc_in              (pc_in),
        .rd_addr_in         (rd_addr_in),
        .csr_addr_in        (csr_addr_in),
        .mem_read_in        (mem_read_in),
        .mem_write_in       (mem_write_in),
        .mem_size_in        (mem_size_in),
        .mem_ext_in         (mem_ext_in),
        .reg_write_in       (reg_write_in),
        .wb_sel_in          (wb_sel_in),
        .csr_we_in          (csr_we_in),
        .csr_op_in          (csr_op_in),
        .csr_imm_sel_in     (csr_imm_sel_in),
        .ecall_in           (ecall_in),
        .ebreak_in          (ebreak_in),
        .mret_in            (mret_in),
        .illegal_instr_in   (illegal_instr_in),
        .dmem_re            (dmem_re),
        .dmem_we            (dmem_we),
        .dmem_addr          (dmem_addr),
        .dmem_wdata         (dmem_wdata),
        .dmem_size          (dmem_size),
        .axi_req_valid      (axi_req_valid),
        .axi_req_addr       (axi_req_addr),
        .axi_req_we         (axi_req_we),
        .axi_req_wdata      (axi_req_wdata),
        .axi_req_size       (axi_req_size),
        .axi_resp_valid     (axi_resp_valid),
        .axi_resp_rdata     (axi_resp_rdata),
        .axi_resp_err       (axi_resp_err),
        .req_fifo_wr_en     (req_fifo_wr_en),
        .req_fifo_wr_data   (req_fifo_wr_data),
        .resp_fifo_rd_empty (resp_fifo_rd_empty),
        .resp_fifo_rd_en    (resp_fifo_rd_en),
        .resp_fifo_rd_data  (resp_fifo_rd_data),
        .plic_re            (plic_re),
        .plic_we            (plic_we),
        .plic_addr          (plic_addr),
        .plic_wdata         (plic_wdata),
        .bus_stall_req      (bus_stall_req),
        .load_access_fault  (load_access_fault),
        .store_access_fault (store_access_fault),
        .pc_out             (pc_out),
        .alu_result_out     (alu_result_out),
        .rdata_out          (rdata_out),
        .rs1_data_out       (rs1_data_out),
        .imm_out            (imm_out),
        .rd_addr_out        (rd_addr_out),
        .csr_addr_out       (csr_addr_out),
        .mem_src_out        (mem_src_out),
        .mem_ext_out        (mem_ext_out),
        .mem_size_out       (mem_size_out),
        .reg_write_out      (reg_write_out),
        .wb_sel_out         (wb_sel_out),
        .csr_we_out         (csr_we_out),
        .csr_op_out         (csr_op_out),
        .csr_imm_sel_out    (csr_imm_sel_out),
        .ecall_out          (ecall_out),
        .ebreak_out         (ebreak_out),
        .mret_out           (mret_out),
        .illegal_instr_out  (illegal_instr_out),
        .load_misaligned_out(load_misaligned_out),
        .store_misaligned_out(store_misaligned_out)
    );

    // Start in reset
    initial assume (!rst_n);

    // Decoder guarantee: an instruction cannot be both a load and a store
    always @(posedge clk)
        assume (~(mem_read_in & mem_write_in));

    // Derived: is this access misaligned?
    logic addr_0, addr_1;
    assign addr_0 = addr_in[0];
    assign addr_1 = addr_in[1];
    logic is_misaligned;
    assign is_misaligned = (mem_size_in == 2'b01) ? addr_0 :
                           (mem_size_in == 2'b10) ? (addr_0 | addr_1) :
                           1'b0;
    logic is_mem_access;
    assign is_mem_access = mem_read_in | mem_write_in;

    // P_BUS_MUTEX: at most one bus interface is active at any time
    // (dmem, AXI, AHB are mutually exclusive — each access goes to exactly one)
    always @(posedge clk) begin
        if (rst_n) begin
            assert (~(dmem_re   & axi_req_valid));
            assert (~(dmem_re   & req_fifo_wr_en));
            assert (~(axi_req_valid & req_fifo_wr_en));
            assert (~(dmem_we   & axi_req_valid));
            assert (~(dmem_we   & req_fifo_wr_en));
        end
    end

    // P_MISALIGN_BLOCK: misaligned access must not reach any bus
    always @(posedge clk) begin
        if (rst_n && is_mem_access && is_misaligned) begin
            assert (dmem_re        == 1'b0);
            assert (dmem_we        == 1'b0);
            assert (axi_req_valid  == 1'b0);
            assert (req_fifo_wr_en == 1'b0);
            assert (plic_re        == 1'b0);
            assert (plic_we        == 1'b0);
        end
    end

    // P_MISALIGN_LOAD_FLAG: misaligned load sets load_misaligned_out
    always @(posedge clk) begin
        if (rst_n && is_misaligned && mem_read_in)
            assert (load_misaligned_out == 1'b1);
    end

    // P_MISALIGN_STORE_FLAG: misaligned store sets store_misaligned_out
    always @(posedge clk) begin
        if (rst_n && is_misaligned && mem_write_in)
            assert (store_misaligned_out == 1'b1);
    end

    // P_BYTE_ALWAYS_ALIGNED: byte access (mem_size=00) is never misaligned
    always @(posedge clk) begin
        if (rst_n && is_mem_access && mem_size_in == 2'b00) begin
            assert (load_misaligned_out  == 1'b0);
            assert (store_misaligned_out == 1'b0);
        end
    end

    // P_FAULT_MUTEX: load and store access faults are mutually exclusive
    // (an instruction cannot be both a load and a store)
    always @(posedge clk) begin
        if (rst_n)
            assert (~(load_access_fault & store_access_fault));
    end


endmodule
