// SoC Top-Level Integration
//
// RV32I + Zicsr, 7-stage pipeline @ 1GHz
// AXI-Lite peripherals @ 1GHz (đồng bộ trực tiếp)
// AHB-Lite peripherals @ 500MHz (qua Dual Async FIFO CDC)
//
// Instances:
//   CPU pipeline : if1_stage, if1_if2_reg, if2_stage, if2_id_reg,
//                  id_decoder, register_file, id_ex_reg,
//                  [EX combinational: alu, branch_comp, addr_adder],
//                  ex_mem1_reg, mem1_stage, dmem,
//                  mem1_mem2_reg, mem2_stage, mem2_wb_reg, wb_stage
//   Control      : hazard_unit, forwarding_unit, zicsr
//   AXI group    : axi_interface, axi_interconnect, 3x axi_sfr
//   AHB group    : 2x reset_sync (cpu+ahb), 2x async_fifo_depth2,
//                  ahb_interface, ahb_interconnect, 3x ahb_sfr

module soc_top #(
    parameter PC_RESET_VAL = 32'h0000_0000
)(
    input  logic clk_cpu,   // 1GHz — CPU + AXI
    input  logic clk_ahb,   // 500MHz — AHB peripherals
    input  logic rst_n      // Async active-low reset
);

    //=========================================================
    // 0. Domain Reset Synchronizers
    //=========================================================
    logic rst_cpu_n;
    logic rst_ahb_n;

    reset_sync u_rst_cpu (
        .clk        (clk_cpu),
        .async_rst_n(rst_n),
        .sync_rst_n (rst_cpu_n)
    );

    reset_sync u_rst_ahb (
        .clk        (clk_ahb),
        .async_rst_n(rst_n),
        .sync_rst_n (rst_ahb_n)
    );

    //=========================================================
    // Intermediate signal declarations
    //=========================================================

    // --- IF1 ---
    logic [31:0] if1_pc;

    // --- IF1/IF2 reg ---
    logic [31:0] if1if2_pc;

    // --- IF2 stage (pass-through) ---
    logic [31:0] if2_pc, if2_instr;

    // --- IF2/ID reg ---
    logic [31:0] if2id_pc, if2id_instr;

    // --- IMEM ---
    logic [31:0] imem_instr;

    // --- ID: id_decoder ---
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [11:0] id_csr_addr;
    logic [2:0]  id_funct3;
    logic [31:0] id_imm;
    logic [3:0]  id_alu_op;
    logic        id_alu_src_a, id_alu_src_b;
    logic        id_branch, id_jump, id_jump_reg;
    logic        id_mem_read, id_mem_write;
    logic [1:0]  id_mem_size;
    logic        id_mem_ext, id_reg_write;
    logic [1:0]  id_wb_sel;
    logic        id_csr_we;
    logic [1:0]  id_csr_op;
    logic        id_csr_imm_sel;
    logic        id_ecall, id_ebreak, id_mret, id_illegal;

    // --- Register File ---
    logic [31:0] rf_rs1_data, rf_rs2_data;

    // --- ID/EX reg ---
    logic [31:0] idex_pc, idex_rs1_data, idex_rs2_data, idex_imm;
    logic [4:0]  idex_rs1_addr, idex_rs2_addr, idex_rd_addr;
    logic [11:0] idex_csr_addr;
    logic [2:0]  idex_funct3;
    logic [3:0]  idex_alu_op;
    logic        idex_alu_src_a, idex_alu_src_b;
    logic        idex_branch, idex_jump, idex_jump_reg;
    logic        idex_mem_read, idex_mem_write;
    logic [1:0]  idex_mem_size;
    logic        idex_mem_ext, idex_reg_write;
    logic [1:0]  idex_wb_sel;
    logic        idex_csr_we;
    logic [1:0]  idex_csr_op;
    logic        idex_csr_imm_sel;
    logic        idex_ecall, idex_ebreak, idex_mret, idex_illegal;

    // --- EX stage (combinational) ---
    logic [1:0]  fwd_sel_a, fwd_sel_b;
    logic [31:0] ex_rs1_fwd, ex_rs2_fwd;   // Forwarded operands
    logic [31:0] ex_alu_a, ex_alu_b;        // ALU inputs
    logic [31:0] ex_alu_result;
    logic        ex_branch_taken;
    logic [31:0] ex_jump_addr;              // From addr_adder (branch/jump target)

    // --- Forward data sources ---
    logic [31:0] fwd_data_mem1;   // From EX/MEM1 reg (alu_result)
    logic [31:0] fwd_data_mem2;   // From MEM2 stage (alu or mem_rdata)
    logic [31:0] fwd_data_wb;     // From WB stage (rf_wr_data)

    // --- EX/MEM1 reg ---
    logic [31:0] exmem1_pc, exmem1_alu_result, exmem1_rs2_data;
    logic [31:0] exmem1_rs1_data, exmem1_imm;
    logic [4:0]  exmem1_rd_addr;
    logic [11:0] exmem1_csr_addr;
    logic        exmem1_mem_read, exmem1_mem_write;
    logic [1:0]  exmem1_mem_size;
    logic        exmem1_mem_ext, exmem1_reg_write;
    logic [1:0]  exmem1_wb_sel;
    logic        exmem1_csr_we;
    logic [1:0]  exmem1_csr_op;
    logic        exmem1_csr_imm_sel;
    logic        exmem1_ecall, exmem1_ebreak, exmem1_mret, exmem1_illegal;

    // --- MEM1 stage ---
    logic [31:0] mem1_pc, mem1_alu_result, mem1_rdata;
    logic [31:0] mem1_rs1_data, mem1_imm;
    logic [4:0]  mem1_rd_addr;
    logic [11:0] mem1_csr_addr;
    logic [1:0]  mem1_mem_src;
    logic        mem1_mem_ext;
    logic [1:0]  mem1_mem_size;
    logic        mem1_reg_write;
    logic [1:0]  mem1_wb_sel;
    logic        mem1_csr_we;
    logic [1:0]  mem1_csr_op;
    logic        mem1_csr_imm_sel;
    logic        mem1_ecall, mem1_ebreak, mem1_mret, mem1_illegal;
    logic        mem1_load_fault, mem1_store_fault;
    logic        bus_stall_req;

    // --- DMEM ---
    logic        dmem_re, dmem_we;
    logic [31:0] dmem_addr, dmem_wdata;
    logic [1:0]  dmem_size;
    logic [31:0] dmem_rdata;

    // --- AXI interface (CPU side) ---
    logic        axi_req_valid;
    logic [31:0] axi_req_addr;
    logic        axi_req_we;
    logic [31:0] axi_req_wdata;
    logic [1:0]  axi_req_size;
    logic        axi_resp_valid;
    logic [31:0] axi_resp_rdata;
    logic        axi_resp_err;

    // --- AHB FIFO (CPU side) ---
    logic        req_fifo_wr_en;
    logic [66:0] req_fifo_wr_data;
    logic        resp_fifo_rd_empty;
    logic        resp_fifo_rd_en;
    logic [32:0] resp_fifo_rd_data;

    // --- MEM1/MEM2 reg ---
    logic [31:0] mem1mem2_pc, mem1mem2_alu_result, mem1mem2_rdata;
    logic [31:0] mem1mem2_rs1_data, mem1mem2_imm;
    logic [4:0]  mem1mem2_rd_addr;
    logic [11:0] mem1mem2_csr_addr;
    logic [1:0]  mem1mem2_mem_src;
    logic        mem1mem2_mem_ext;
    logic [1:0]  mem1mem2_mem_size;
    logic        mem1mem2_reg_write;
    logic [1:0]  mem1mem2_wb_sel;
    logic        mem1mem2_csr_we;
    logic [1:0]  mem1mem2_csr_op;
    logic        mem1mem2_csr_imm_sel;
    logic        mem1mem2_ecall, mem1mem2_ebreak, mem1mem2_mret, mem1mem2_illegal;
    logic        mem1mem2_load_fault, mem1mem2_store_fault;

    // --- MEM2 stage ---
    logic [31:0] mem2_pc, mem2_alu_result, mem2_mem_rdata;
    logic [31:0] mem2_rs1_data, mem2_imm;
    logic [4:0]  mem2_rd_addr;
    logic [11:0] mem2_csr_addr;
    logic        mem2_reg_write;
    logic [1:0]  mem2_wb_sel;
    logic        mem2_csr_we;
    logic [1:0]  mem2_csr_op;
    logic        mem2_csr_imm_sel;
    logic        mem2_ecall, mem2_ebreak, mem2_mret, mem2_illegal;
    logic        mem2_load_fault, mem2_store_fault;

    // --- MEM2/WB reg ---
    logic [31:0] wb_pc, wb_alu_result, wb_mem_rdata;
    logic [31:0] wb_rs1_data, wb_imm;
    logic [4:0]  wb_rd_addr;
    logic [11:0] wb_csr_addr;
    logic        wb_reg_write;
    logic [1:0]  wb_sel;
    logic        wb_csr_we;
    logic [1:0]  wb_csr_op;
    logic        wb_csr_imm_sel;
    logic        wb_ecall, wb_ebreak, wb_mret, wb_illegal;
    logic        wb_load_fault, wb_store_fault;

    // --- WB stage ---
    logic [4:0]  rf_wr_addr;
    logic        rf_wr_we;
    logic [31:0] rf_wr_data;

    // --- Zicsr ---
    logic [31:0] csr_rdata;
    logic        zicsr_flush;
    logic [31:0] zicsr_pc;

    // --- Hazard unit ---
    logic stall_pc;
    logic flush_pc; // Driven by hazard_unit (=zicsr_flush); subsumed by flush_if1if2
    logic stall_if1if2, flush_if1if2;
    logic stall_if2id,  flush_if2id;
    logic stall_idex,   flush_idex;
    logic stall_exmem1, flush_exmem1;
    logic stall_mem1mem2, flush_mem1mem2;
    logic stall_mem2wb, flush_mem2wb;

    // --- Muxed IF1 jump address ---
    logic [31:0] if1_jump_addr;
    assign if1_jump_addr = zicsr_flush ? zicsr_pc : ex_jump_addr;

    // --- MEM2 forwarding mux ---
    //    wb_sel for instruction at MEM2: mem1mem2_wb_sel
    assign fwd_data_mem2 = (mem1mem2_wb_sel == 2'b01) ? mem2_mem_rdata : mem2_alu_result;

    // --- MEM1 forwarding source ---
    assign fwd_data_mem1 = exmem1_alu_result;

    // --- WB forwarding source (rf_wr_data computed in wb_stage) ---
    assign fwd_data_wb = rf_wr_data;

    //=========================================================
    // 1. IF1 Stage — PC Register
    //=========================================================
    if1_stage #(.PC_RESET_VAL(PC_RESET_VAL)) u_if1 (
        .clk       (clk_cpu),
        .rst_n     (rst_cpu_n),
        .stall     (stall_pc),
        .flush     (flush_if1if2),    // zicsr_flush | ctrl_flush
        .jump_addr (if1_jump_addr),
        .pc_out    (if1_pc)
    );

    //=========================================================
    // 2. IMEM — Synchronous (1GHz, address = if1_pc)
    //=========================================================
    imem #(.SIZE_KB(64)) u_imem (
        .clk      (clk_cpu),
        .stall    (stall_if1if2),
        .flush    (flush_if1if2),
        .addr     (if1_pc),
        .instr_out(imem_instr)
    );

    //=========================================================
    // 3. IF1/IF2 Pipeline Register
    //=========================================================
    if1_if2_reg u_if1if2 (
        .clk   (clk_cpu),
        .rst_n (rst_cpu_n),
        .stall (stall_if1if2),
        .flush (flush_if1if2),
        .pc_in (if1_pc),
        .pc_out(if1if2_pc)
    );

    //=========================================================
    // 4. IF2 Stage — Pass-through
    //=========================================================
    if2_stage u_if2 (
        .pc_in    (if1if2_pc),
        .instr_in (imem_instr),
        .pc_out   (if2_pc),
        .instr_out(if2_instr)
    );

    //=========================================================
    // 5. IF2/ID Pipeline Register
    //=========================================================
    if2_id_reg u_if2id (
        .clk      (clk_cpu),
        .rst_n    (rst_cpu_n),
        .stall    (stall_if2id),
        .flush    (flush_if2id),
        .pc_in    (if2_pc),
        .instr_in (if2_instr),
        .pc_out   (if2id_pc),
        .instr_out(if2id_instr)
    );

    //=========================================================
    // 6. ID Stage — Decoder + Register File
    //=========================================================
    id_decoder u_id_dec (
        .instr        (if2id_instr),
        .rs1_addr     (id_rs1_addr),
        .rs2_addr     (id_rs2_addr),
        .rd_addr      (id_rd_addr),
        .csr_addr     (id_csr_addr),
        .funct3       (id_funct3),
        .imm          (id_imm),
        .alu_op       (id_alu_op),
        .alu_src_a    (id_alu_src_a),
        .alu_src_b    (id_alu_src_b),
        .branch       (id_branch),
        .jump         (id_jump),
        .jump_reg     (id_jump_reg),
        .mem_read     (id_mem_read),
        .mem_write    (id_mem_write),
        .mem_size     (id_mem_size),
        .mem_ext      (id_mem_ext),
        .reg_write    (id_reg_write),
        .wb_sel       (id_wb_sel),
        .csr_we       (id_csr_we),
        .csr_op       (id_csr_op),
        .csr_imm_sel  (id_csr_imm_sel),
        .ecall        (id_ecall),
        .ebreak       (id_ebreak),
        .mret         (id_mret),
        .illegal_instr(id_illegal)
    );

    register_file u_rf (
        .clk     (clk_cpu),
        .rst_n   (rst_cpu_n),
        .rs1_addr(id_rs1_addr),
        .rs1_data(rf_rs1_data),
        .rs2_addr(id_rs2_addr),
        .rs2_data(rf_rs2_data),
        .we      (rf_wr_we),
        .rd_addr (rf_wr_addr),
        .rd_data (rf_wr_data)
    );

    //=========================================================
    // 7. ID/EX Pipeline Register
    //=========================================================
    id_ex_reg u_idex (
        .clk             (clk_cpu),
        .rst_n           (rst_cpu_n),
        .stall           (stall_idex),
        .flush           (flush_idex),
        .pc_in           (if2id_pc),
        .rs1_data_in     (rf_rs1_data),
        .rs2_data_in     (rf_rs2_data),
        .imm_in          (id_imm),
        .rs1_addr_in     (id_rs1_addr),
        .rs2_addr_in     (id_rs2_addr),
        .rd_addr_in      (id_rd_addr),
        .csr_addr_in     (id_csr_addr),
        .funct3_in       (id_funct3),
        .alu_op_in       (id_alu_op),
        .alu_src_a_in    (id_alu_src_a),
        .alu_src_b_in    (id_alu_src_b),
        .branch_in       (id_branch),
        .jump_in         (id_jump),
        .jump_reg_in     (id_jump_reg),
        .mem_read_in     (id_mem_read),
        .mem_write_in    (id_mem_write),
        .mem_size_in     (id_mem_size),
        .mem_ext_in      (id_mem_ext),
        .reg_write_in    (id_reg_write),
        .wb_sel_in       (id_wb_sel),
        .csr_we_in       (id_csr_we),
        .csr_op_in       (id_csr_op),
        .csr_imm_sel_in  (id_csr_imm_sel),
        .ecall_in        (id_ecall),
        .ebreak_in       (id_ebreak),
        .mret_in         (id_mret),
        .illegal_instr_in(id_illegal),
        .pc_out          (idex_pc),
        .rs1_data_out    (idex_rs1_data),
        .rs2_data_out    (idex_rs2_data),
        .imm_out         (idex_imm),
        .rs1_addr_out    (idex_rs1_addr),
        .rs2_addr_out    (idex_rs2_addr),
        .rd_addr_out     (idex_rd_addr),
        .csr_addr_out    (idex_csr_addr),
        .funct3_out      (idex_funct3),
        .alu_op_out      (idex_alu_op),
        .alu_src_a_out   (idex_alu_src_a),
        .alu_src_b_out   (idex_alu_src_b),
        .branch_out      (idex_branch),
        .jump_out        (idex_jump),
        .jump_reg_out    (idex_jump_reg),
        .mem_read_out    (idex_mem_read),
        .mem_write_out   (idex_mem_write),
        .mem_size_out    (idex_mem_size),
        .mem_ext_out     (idex_mem_ext),
        .reg_write_out   (idex_reg_write),
        .wb_sel_out      (idex_wb_sel),
        .csr_we_out      (idex_csr_we),
        .csr_op_out      (idex_csr_op),
        .csr_imm_sel_out (idex_csr_imm_sel),
        .ecall_out       (idex_ecall),
        .ebreak_out      (idex_ebreak),
        .mret_out        (idex_mret),
        .illegal_instr_out(idex_illegal)
    );

    //=========================================================
    // 8. EX Stage — Forwarding MUX + ALU + Branch + Addr
    //=========================================================

    // --- Forwarding Unit ---
    forwarding_unit u_fwd (
        .ex_rs1_addr    (idex_rs1_addr),
        .ex_rs2_addr    (idex_rs2_addr),
        .mem1_rd_addr   (exmem1_rd_addr),
        .mem1_reg_write (exmem1_reg_write),
        .mem2_rd_addr   (mem1mem2_rd_addr),
        .mem2_reg_write (mem1mem2_reg_write),
        .wb_rd_addr     (wb_rd_addr),
        .wb_reg_write   (wb_reg_write),
        .fwd_sel_a      (fwd_sel_a),
        .fwd_sel_b      (fwd_sel_b)
    );

    // --- Forwarding MUX for rs1 ---
    always_comb begin
        case (fwd_sel_a)
            2'b01:   ex_rs1_fwd = fwd_data_mem1;
            2'b10:   ex_rs1_fwd = fwd_data_mem2;
            2'b11:   ex_rs1_fwd = fwd_data_wb;
            default: ex_rs1_fwd = idex_rs1_data;
        endcase
    end

    // --- Forwarding MUX for rs2 ---
    always_comb begin
        case (fwd_sel_b)
            2'b01:   ex_rs2_fwd = fwd_data_mem1;
            2'b10:   ex_rs2_fwd = fwd_data_mem2;
            2'b11:   ex_rs2_fwd = fwd_data_wb;
            default: ex_rs2_fwd = idex_rs2_data;
        endcase
    end

    // --- ALU input MUX ---
    assign ex_alu_a = idex_alu_src_a ? idex_pc      : ex_rs1_fwd;
    assign ex_alu_b = idex_alu_src_b ? idex_imm     : ex_rs2_fwd;

    // --- ALU ---
    alu u_alu (
        .operand_a (ex_alu_a),
        .operand_b (ex_alu_b),
        .alu_op    (idex_alu_op),
        .alu_result(ex_alu_result)
    );

    // --- Branch Comparator ---
    branch_comp u_bcomp (
        .rs1_data    (ex_rs1_fwd),
        .rs2_data    (ex_rs2_fwd),
        .funct3      (idex_funct3),
        .branch      (idex_branch),
        .branch_taken(ex_branch_taken)
    );

    // --- Address Adder (branch/jump target) ---
    addr_adder u_aadd (
        .pc      (idex_pc),
        .rs1_data(ex_rs1_fwd),
        .imm     (idex_imm),
        .branch  (idex_branch),
        .jump    (idex_jump),
        .jump_reg(idex_jump_reg),
        .addr_out(ex_jump_addr)
    );

    //=========================================================
    // 9. EX/MEM1 Pipeline Register
    //=========================================================
    ex_mem1_reg u_exmem1 (
        .clk              (clk_cpu),
        .rst_n            (rst_cpu_n),
        .stall            (stall_exmem1),
        .flush            (flush_exmem1),
        .pc_in            (idex_pc),
        .alu_result_in    (ex_alu_result),
        .rs2_data_in      (ex_rs2_fwd),    // Store data (forwarded)
        .rs1_data_in      (ex_rs1_fwd),    // CSR write source (forwarded)
        .imm_in           (idex_imm),
        .rd_addr_in       (idex_rd_addr),
        .csr_addr_in      (idex_csr_addr),
        .mem_read_in      (idex_mem_read),
        .mem_write_in     (idex_mem_write),
        .mem_size_in      (idex_mem_size),
        .mem_ext_in       (idex_mem_ext),
        .reg_write_in     (idex_reg_write),
        .wb_sel_in        (idex_wb_sel),
        .csr_we_in        (idex_csr_we),
        .csr_op_in        (idex_csr_op),
        .csr_imm_sel_in   (idex_csr_imm_sel),
        .ecall_in         (idex_ecall),
        .ebreak_in        (idex_ebreak),
        .mret_in          (idex_mret),
        .illegal_instr_in (idex_illegal),
        .pc_out           (exmem1_pc),
        .alu_result_out   (exmem1_alu_result),
        .rs2_data_out     (exmem1_rs2_data),
        .rs1_data_out     (exmem1_rs1_data),
        .imm_out          (exmem1_imm),
        .rd_addr_out      (exmem1_rd_addr),
        .csr_addr_out     (exmem1_csr_addr),
        .mem_read_out     (exmem1_mem_read),
        .mem_write_out    (exmem1_mem_write),
        .mem_size_out     (exmem1_mem_size),
        .mem_ext_out      (exmem1_mem_ext),
        .reg_write_out    (exmem1_reg_write),
        .wb_sel_out       (exmem1_wb_sel),
        .csr_we_out       (exmem1_csr_we),
        .csr_op_out       (exmem1_csr_op),
        .csr_imm_sel_out  (exmem1_csr_imm_sel),
        .ecall_out        (exmem1_ecall),
        .ebreak_out       (exmem1_ebreak),
        .mret_out         (exmem1_mret),
        .illegal_instr_out(exmem1_illegal)
    );

    //=========================================================
    // 10. MEM1 Stage — Address Decode + Bus FSM
    //=========================================================
    mem1_stage u_mem1 (
        .clk              (clk_cpu),
        .rst_n            (rst_cpu_n),
        .addr_in          (exmem1_alu_result),
        .wdata_in         (exmem1_rs2_data),
        .rs1_data_in      (exmem1_rs1_data),
        .imm_in           (exmem1_imm),
        .pc_in            (exmem1_pc),
        .rd_addr_in       (exmem1_rd_addr),
        .csr_addr_in      (exmem1_csr_addr),
        .mem_read_in      (exmem1_mem_read),
        .mem_write_in     (exmem1_mem_write),
        .mem_size_in      (exmem1_mem_size),
        .mem_ext_in       (exmem1_mem_ext),
        .reg_write_in     (exmem1_reg_write),
        .wb_sel_in        (exmem1_wb_sel),
        .csr_we_in        (exmem1_csr_we),
        .csr_op_in        (exmem1_csr_op),
        .csr_imm_sel_in   (exmem1_csr_imm_sel),
        .ecall_in         (exmem1_ecall),
        .ebreak_in        (exmem1_ebreak),
        .mret_in          (exmem1_mret),
        .illegal_instr_in (exmem1_illegal),
        // DMEM
        .dmem_re          (dmem_re),
        .dmem_we          (dmem_we),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_size        (dmem_size),
        // AXI
        .axi_req_valid    (axi_req_valid),
        .axi_req_addr     (axi_req_addr),
        .axi_req_we       (axi_req_we),
        .axi_req_wdata    (axi_req_wdata),
        .axi_req_size     (axi_req_size),
        .axi_resp_valid   (axi_resp_valid),
        .axi_resp_rdata   (axi_resp_rdata),
        .axi_resp_err     (axi_resp_err),
        // AHB FIFOs
        .req_fifo_wr_en   (req_fifo_wr_en),
        .req_fifo_wr_data (req_fifo_wr_data),
        .resp_fifo_rd_empty(resp_fifo_rd_empty),
        .resp_fifo_rd_en  (resp_fifo_rd_en),
        .resp_fifo_rd_data(resp_fifo_rd_data),
        // Hazard
        .bus_stall_req    (bus_stall_req),
        // Faults
        .load_access_fault (mem1_load_fault),
        .store_access_fault(mem1_store_fault),
        // To MEM1/MEM2 reg
        .pc_out           (mem1_pc),
        .alu_result_out   (mem1_alu_result),
        .rdata_out        (mem1_rdata),
        .rs1_data_out     (mem1_rs1_data),
        .imm_out          (mem1_imm),
        .rd_addr_out      (mem1_rd_addr),
        .csr_addr_out     (mem1_csr_addr),
        .mem_src_out      (mem1_mem_src),
        .mem_ext_out      (mem1_mem_ext),
        .mem_size_out     (mem1_mem_size),
        .reg_write_out    (mem1_reg_write),
        .wb_sel_out       (mem1_wb_sel),
        .csr_we_out       (mem1_csr_we),
        .csr_op_out       (mem1_csr_op),
        .csr_imm_sel_out  (mem1_csr_imm_sel),
        .ecall_out        (mem1_ecall),
        .ebreak_out       (mem1_ebreak),
        .mret_out         (mem1_mret),
        .illegal_instr_out(mem1_illegal)
    );

    //=========================================================
    // 11. DMEM — Synchronous (1GHz)
    //=========================================================
    dmem #(.SIZE_KB(64)) u_dmem (
        .clk   (clk_cpu),
        .re    (dmem_re),
        .addr  (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .wdata (dmem_wdata),
        .size  (dmem_size)
    );

    //=========================================================
    // 12. MEM1/MEM2 Pipeline Register
    //=========================================================
    mem1_mem2_reg u_mem1mem2 (
        .clk              (clk_cpu),
        .rst_n            (rst_cpu_n),
        .stall            (stall_mem1mem2),
        .flush            (flush_mem1mem2),
        .pc_in            (mem1_pc),
        .alu_result_in    (mem1_alu_result),
        .rdata_in         (mem1_rdata),
        .rs1_data_in      (mem1_rs1_data),
        .imm_in           (mem1_imm),
        .rd_addr_in       (mem1_rd_addr),
        .csr_addr_in      (mem1_csr_addr),
        .mem_src_in       (mem1_mem_src),
        .mem_ext_in       (mem1_mem_ext),
        .mem_size_in      (mem1_mem_size),
        .reg_write_in     (mem1_reg_write),
        .wb_sel_in        (mem1_wb_sel),
        .csr_we_in        (mem1_csr_we),
        .csr_op_in        (mem1_csr_op),
        .csr_imm_sel_in   (mem1_csr_imm_sel),
        .ecall_in         (mem1_ecall),
        .ebreak_in        (mem1_ebreak),
        .mret_in          (mem1_mret),
        .illegal_instr_in (mem1_illegal),
        .load_fault_in    (mem1_load_fault),
        .store_fault_in   (mem1_store_fault),
        .pc_out           (mem1mem2_pc),
        .alu_result_out   (mem1mem2_alu_result),
        .rdata_out        (mem1mem2_rdata),
        .rs1_data_out     (mem1mem2_rs1_data),
        .imm_out          (mem1mem2_imm),
        .rd_addr_out      (mem1mem2_rd_addr),
        .csr_addr_out     (mem1mem2_csr_addr),
        .mem_src_out      (mem1mem2_mem_src),
        .mem_ext_out      (mem1mem2_mem_ext),
        .mem_size_out     (mem1mem2_mem_size),
        .reg_write_out    (mem1mem2_reg_write),
        .wb_sel_out       (mem1mem2_wb_sel),
        .csr_we_out       (mem1mem2_csr_we),
        .csr_op_out       (mem1mem2_csr_op),
        .csr_imm_sel_out  (mem1mem2_csr_imm_sel),
        .ecall_out        (mem1mem2_ecall),
        .ebreak_out       (mem1mem2_ebreak),
        .mret_out         (mem1mem2_mret),
        .illegal_instr_out(mem1mem2_illegal),
        .load_fault_out   (mem1mem2_load_fault),
        .store_fault_out  (mem1mem2_store_fault)
    );

    //=========================================================
    // 13. MEM2 Stage — Data Source Select + Sign Extension
    //=========================================================
    mem2_stage u_mem2 (
        .pc_in            (mem1mem2_pc),
        .alu_result_in    (mem1mem2_alu_result),
        .rdata_in         (mem1mem2_rdata),
        .rs1_data_in      (mem1mem2_rs1_data),
        .imm_in           (mem1mem2_imm),
        .rd_addr_in       (mem1mem2_rd_addr),
        .csr_addr_in      (mem1mem2_csr_addr),
        .mem_src_in       (mem1mem2_mem_src),
        .mem_ext_in       (mem1mem2_mem_ext),
        .mem_size_in      (mem1mem2_mem_size),
        .reg_write_in     (mem1mem2_reg_write),
        .wb_sel_in        (mem1mem2_wb_sel),
        .csr_we_in        (mem1mem2_csr_we),
        .csr_op_in        (mem1mem2_csr_op),
        .csr_imm_sel_in   (mem1mem2_csr_imm_sel),
        .ecall_in         (mem1mem2_ecall),
        .ebreak_in        (mem1mem2_ebreak),
        .mret_in          (mem1mem2_mret),
        .illegal_instr_in (mem1mem2_illegal),
        .load_fault_in    (mem1mem2_load_fault),
        .store_fault_in   (mem1mem2_store_fault),
        .dmem_rdata       (dmem_rdata),
        .pc_out           (mem2_pc),
        .alu_result_out   (mem2_alu_result),
        .mem_rdata_out    (mem2_mem_rdata),
        .rs1_data_out     (mem2_rs1_data),
        .imm_out          (mem2_imm),
        .rd_addr_out      (mem2_rd_addr),
        .csr_addr_out     (mem2_csr_addr),
        .reg_write_out    (mem2_reg_write),
        .wb_sel_out       (mem2_wb_sel),
        .csr_we_out       (mem2_csr_we),
        .csr_op_out       (mem2_csr_op),
        .csr_imm_sel_out  (mem2_csr_imm_sel),
        .ecall_out        (mem2_ecall),
        .ebreak_out       (mem2_ebreak),
        .mret_out         (mem2_mret),
        .illegal_instr_out(mem2_illegal),
        .load_fault_out   (mem2_load_fault),
        .store_fault_out  (mem2_store_fault)
    );

    //=========================================================
    // 14. MEM2/WB Pipeline Register
    //=========================================================
    mem2_wb_reg u_mem2wb (
        .clk              (clk_cpu),
        .rst_n            (rst_cpu_n),
        .stall            (stall_mem2wb),
        .flush            (flush_mem2wb),
        .pc_in            (mem2_pc),
        .alu_result_in    (mem2_alu_result),
        .mem_rdata_in     (mem2_mem_rdata),
        .rs1_data_in      (mem2_rs1_data),
        .imm_in           (mem2_imm),
        .rd_addr_in       (mem2_rd_addr),
        .csr_addr_in      (mem2_csr_addr),
        .reg_write_in     (mem2_reg_write),
        .wb_sel_in        (mem2_wb_sel),
        .csr_we_in        (mem2_csr_we),
        .csr_op_in        (mem2_csr_op),
        .csr_imm_sel_in   (mem2_csr_imm_sel),
        .ecall_in         (mem2_ecall),
        .ebreak_in        (mem2_ebreak),
        .mret_in          (mem2_mret),
        .illegal_instr_in (mem2_illegal),
        .load_fault_in    (mem2_load_fault),
        .store_fault_in   (mem2_store_fault),
        .pc_out           (wb_pc),
        .alu_result_out   (wb_alu_result),
        .mem_rdata_out    (wb_mem_rdata),
        .rs1_data_out     (wb_rs1_data),
        .imm_out          (wb_imm),
        .rd_addr_out      (wb_rd_addr),
        .csr_addr_out     (wb_csr_addr),
        .reg_write_out    (wb_reg_write),
        .wb_sel_out       (wb_sel),
        .csr_we_out       (wb_csr_we),
        .csr_op_out       (wb_csr_op),
        .csr_imm_sel_out  (wb_csr_imm_sel),
        .ecall_out        (wb_ecall),
        .ebreak_out       (wb_ebreak),
        .mret_out         (wb_mret),
        .illegal_instr_out(wb_illegal),
        .load_fault_out   (wb_load_fault),
        .store_fault_out  (wb_store_fault)
    );

    //=========================================================
    // 15. WB Stage — Result MUX → Register File
    //=========================================================
    wb_stage u_wb (
        .pc_in         (wb_pc),
        .alu_result_in (wb_alu_result),
        .mem_rdata_in  (wb_mem_rdata),
        .rd_addr_in    (wb_rd_addr),
        .reg_write_in  (wb_reg_write),
        .wb_sel_in     (wb_sel),
        .csr_rdata_in  (csr_rdata),
        .rf_rd_addr    (rf_wr_addr),
        .rf_we         (rf_wr_we),
        .rf_wr_data    (rf_wr_data)
    );

    //=========================================================
    // 16. Zicsr — CSR Register File + Exception/Interrupt Controller
    //=========================================================

    // AHB/AXI IRQ wires (declared here for scope)
    logic ahb_irq_raw, axi_irq;

    zicsr u_zicsr (
        .clk              (clk_cpu),
        .rst_n            (rst_cpu_n),
        .wb_pc            (wb_pc),
        .wb_rs1_data      (wb_rs1_data),
        .wb_imm           (wb_imm),
        .wb_csr_addr      (wb_csr_addr),
        .wb_csr_we        (wb_csr_we),
        .wb_csr_op        (wb_csr_op),
        .wb_csr_imm_sel   (wb_csr_imm_sel),
        .wb_ecall         (wb_ecall),
        .wb_ebreak        (wb_ebreak),
        .wb_mret          (wb_mret),
        .wb_illegal_instr (wb_illegal),
        .wb_load_fault    (wb_load_fault),
        .wb_store_fault   (wb_store_fault),
        .ahb_irq          (ahb_irq_raw),
        .axi_irq          (axi_irq),
        .bus_stall_req    (bus_stall_req),
        .csr_rdata        (csr_rdata),
        .zicsr_flush      (zicsr_flush),
        .zicsr_pc         (zicsr_pc)
    );

    //=========================================================
    // 17. Hazard Unit
    //=========================================================
    hazard_unit u_haz (
        .bus_stall_req  (bus_stall_req),
        .ex_mem_read    (idex_mem_read),
        .ex_rd_addr     (idex_rd_addr),
        .ex_wb_sel      (idex_wb_sel),
        .ex_reg_write   (idex_reg_write),
        .mem1_wb_sel    (exmem1_wb_sel),
        .mem1_rd_addr   (exmem1_rd_addr),
        .mem1_reg_write (exmem1_reg_write),
        .mem2_wb_sel    (mem1mem2_wb_sel),
        .mem2_rd_addr   (mem1mem2_rd_addr),
        .mem2_reg_write (mem1mem2_reg_write),
        .id_rs1_addr    (id_rs1_addr),
        .id_rs2_addr    (id_rs2_addr),
        .branch_taken   (ex_branch_taken),
        .jump           (idex_jump),
        .zicsr_flush    (zicsr_flush),
        .stall_if1_if2  (stall_if1if2),
        .stall_if2_id   (stall_if2id),
        .stall_id_ex    (stall_idex),
        .stall_ex_mem1  (stall_exmem1),
        .stall_mem1_mem2(stall_mem1mem2),
        .stall_mem2_wb  (stall_mem2wb),
        .flush_if1_if2  (flush_if1if2),
        .flush_if2_id   (flush_if2id),
        .flush_id_ex    (flush_idex),
        .flush_ex_mem1  (flush_exmem1),
        .flush_mem1_mem2(flush_mem1mem2),
        .flush_mem2_wb  (flush_mem2wb),
        .stall_pc       (stall_pc),
        .flush_pc       (flush_pc)
    );

    //=========================================================
    // 18. AXI Group (1GHz domain)
    //=========================================================

    // AXI master ↔ interconnect buses
    logic [31:0] axi_M_AWADDR; logic [2:0] axi_M_AWPROT; logic axi_M_AWVALID, axi_M_AWREADY;
    logic [31:0] axi_M_WDATA;  logic [3:0] axi_M_WSTRB;  logic axi_M_WVALID,  axi_M_WREADY;
    logic [1:0]  axi_M_BRESP;  logic axi_M_BVALID, axi_M_BREADY;
    logic [31:0] axi_M_ARADDR; logic [2:0] axi_M_ARPROT; logic axi_M_ARVALID, axi_M_ARREADY;
    logic [31:0] axi_M_RDATA;  logic [1:0] axi_M_RRESP;  logic axi_M_RVALID,  axi_M_RREADY;

    // Interconnect ↔ Slave 0
    logic [31:0] axi_S0_AWADDR; logic [2:0] axi_S0_AWPROT; logic axi_S0_AWVALID, axi_S0_AWREADY;
    logic [31:0] axi_S0_WDATA;  logic [3:0] axi_S0_WSTRB;  logic axi_S0_WVALID,  axi_S0_WREADY;
    logic [1:0]  axi_S0_BRESP;  logic axi_S0_BVALID, axi_S0_BREADY;
    logic [31:0] axi_S0_ARADDR; logic [2:0] axi_S0_ARPROT; logic axi_S0_ARVALID, axi_S0_ARREADY;
    logic [31:0] axi_S0_RDATA;  logic [1:0] axi_S0_RRESP;  logic axi_S0_RVALID,  axi_S0_RREADY;
    logic axi_irq0;

    // Interconnect ↔ Slave 1
    logic [31:0] axi_S1_AWADDR; logic [2:0] axi_S1_AWPROT; logic axi_S1_AWVALID, axi_S1_AWREADY;
    logic [31:0] axi_S1_WDATA;  logic [3:0] axi_S1_WSTRB;  logic axi_S1_WVALID,  axi_S1_WREADY;
    logic [1:0]  axi_S1_BRESP;  logic axi_S1_BVALID, axi_S1_BREADY;
    logic [31:0] axi_S1_ARADDR; logic [2:0] axi_S1_ARPROT; logic axi_S1_ARVALID, axi_S1_ARREADY;
    logic [31:0] axi_S1_RDATA;  logic [1:0] axi_S1_RRESP;  logic axi_S1_RVALID,  axi_S1_RREADY;
    logic axi_irq1;

    // Interconnect ↔ Slave 2
    logic [31:0] axi_S2_AWADDR; logic [2:0] axi_S2_AWPROT; logic axi_S2_AWVALID, axi_S2_AWREADY;
    logic [31:0] axi_S2_WDATA;  logic [3:0] axi_S2_WSTRB;  logic axi_S2_WVALID,  axi_S2_WREADY;
    logic [1:0]  axi_S2_BRESP;  logic axi_S2_BVALID, axi_S2_BREADY;
    logic [31:0] axi_S2_ARADDR; logic [2:0] axi_S2_ARPROT; logic axi_S2_ARVALID, axi_S2_ARREADY;
    logic [31:0] axi_S2_RDATA;  logic [1:0] axi_S2_RRESP;  logic axi_S2_RVALID,  axi_S2_RREADY;
    logic axi_irq2;

    axi_interface u_axi_if (
        .clk            (clk_cpu),
        .rst_n          (rst_cpu_n),
        .axi_req_valid  (axi_req_valid),
        .axi_req_addr   (axi_req_addr),
        .axi_req_we     (axi_req_we),
        .axi_req_wdata  (axi_req_wdata),
        .axi_req_size   (axi_req_size),
        .axi_resp_valid (axi_resp_valid),
        .axi_resp_rdata (axi_resp_rdata),
        .axi_resp_err   (axi_resp_err),
        .AWADDR(axi_M_AWADDR), .AWPROT(axi_M_AWPROT), .AWVALID(axi_M_AWVALID), .AWREADY(axi_M_AWREADY),
        .WDATA (axi_M_WDATA),  .WSTRB (axi_M_WSTRB),  .WVALID (axi_M_WVALID),  .WREADY (axi_M_WREADY),
        .BRESP (axi_M_BRESP),  .BVALID(axi_M_BVALID), .BREADY (axi_M_BREADY),
        .ARADDR(axi_M_ARADDR), .ARPROT(axi_M_ARPROT), .ARVALID(axi_M_ARVALID), .ARREADY(axi_M_ARREADY),
        .RDATA (axi_M_RDATA),  .RRESP (axi_M_RRESP),  .RVALID (axi_M_RVALID),  .RREADY (axi_M_RREADY)
    );

    axi_interconnect u_axi_xbar (
        .clk(clk_cpu), .rst_n(rst_cpu_n),
        .M_AWADDR(axi_M_AWADDR), .M_AWPROT(axi_M_AWPROT), .M_AWVALID(axi_M_AWVALID), .M_AWREADY(axi_M_AWREADY),
        .M_WDATA (axi_M_WDATA),  .M_WSTRB (axi_M_WSTRB),  .M_WVALID (axi_M_WVALID),  .M_WREADY (axi_M_WREADY),
        .M_BRESP (axi_M_BRESP),  .M_BVALID(axi_M_BVALID), .M_BREADY (axi_M_BREADY),
        .M_ARADDR(axi_M_ARADDR), .M_ARPROT(axi_M_ARPROT), .M_ARVALID(axi_M_ARVALID), .M_ARREADY(axi_M_ARREADY),
        .M_RDATA (axi_M_RDATA),  .M_RRESP (axi_M_RRESP),  .M_RVALID (axi_M_RVALID),  .M_RREADY (axi_M_RREADY),
        .S0_AWADDR(axi_S0_AWADDR),.S0_AWPROT(axi_S0_AWPROT),.S0_AWVALID(axi_S0_AWVALID),.S0_AWREADY(axi_S0_AWREADY),
        .S0_WDATA (axi_S0_WDATA), .S0_WSTRB (axi_S0_WSTRB), .S0_WVALID (axi_S0_WVALID), .S0_WREADY (axi_S0_WREADY),
        .S0_BRESP (axi_S0_BRESP), .S0_BVALID(axi_S0_BVALID),.S0_BREADY (axi_S0_BREADY),
        .S0_ARADDR(axi_S0_ARADDR),.S0_ARPROT(axi_S0_ARPROT),.S0_ARVALID(axi_S0_ARVALID),.S0_ARREADY(axi_S0_ARREADY),
        .S0_RDATA (axi_S0_RDATA), .S0_RRESP (axi_S0_RRESP), .S0_RVALID (axi_S0_RVALID), .S0_RREADY (axi_S0_RREADY),
        .irq0(axi_irq0),
        .S1_AWADDR(axi_S1_AWADDR),.S1_AWPROT(axi_S1_AWPROT),.S1_AWVALID(axi_S1_AWVALID),.S1_AWREADY(axi_S1_AWREADY),
        .S1_WDATA (axi_S1_WDATA), .S1_WSTRB (axi_S1_WSTRB), .S1_WVALID (axi_S1_WVALID), .S1_WREADY (axi_S1_WREADY),
        .S1_BRESP (axi_S1_BRESP), .S1_BVALID(axi_S1_BVALID),.S1_BREADY (axi_S1_BREADY),
        .S1_ARADDR(axi_S1_ARADDR),.S1_ARPROT(axi_S1_ARPROT),.S1_ARVALID(axi_S1_ARVALID),.S1_ARREADY(axi_S1_ARREADY),
        .S1_RDATA (axi_S1_RDATA), .S1_RRESP (axi_S1_RRESP), .S1_RVALID (axi_S1_RVALID), .S1_RREADY (axi_S1_RREADY),
        .irq1(axi_irq1),
        .S2_AWADDR(axi_S2_AWADDR),.S2_AWPROT(axi_S2_AWPROT),.S2_AWVALID(axi_S2_AWVALID),.S2_AWREADY(axi_S2_AWREADY),
        .S2_WDATA (axi_S2_WDATA), .S2_WSTRB (axi_S2_WSTRB), .S2_WVALID (axi_S2_WVALID), .S2_WREADY (axi_S2_WREADY),
        .S2_BRESP (axi_S2_BRESP), .S2_BVALID(axi_S2_BVALID),.S2_BREADY (axi_S2_BREADY),
        .S2_ARADDR(axi_S2_ARADDR),.S2_ARPROT(axi_S2_ARPROT),.S2_ARVALID(axi_S2_ARVALID),.S2_ARREADY(axi_S2_ARREADY),
        .S2_RDATA (axi_S2_RDATA), .S2_RRESP (axi_S2_RRESP), .S2_RVALID (axi_S2_RVALID), .S2_RREADY (axi_S2_RREADY),
        .irq2(axi_irq2),
        .axi_irq(axi_irq)
    );

    axi_sfr u_axi_sfr0 (.clk(clk_cpu),.rst_n(rst_cpu_n),
        .AWADDR(axi_S0_AWADDR),.AWPROT(axi_S0_AWPROT),.AWVALID(axi_S0_AWVALID),.AWREADY(axi_S0_AWREADY),
        .WDATA (axi_S0_WDATA), .WSTRB (axi_S0_WSTRB), .WVALID (axi_S0_WVALID), .WREADY (axi_S0_WREADY),
        .BRESP (axi_S0_BRESP), .BVALID(axi_S0_BVALID),.BREADY (axi_S0_BREADY),
        .ARADDR(axi_S0_ARADDR),.ARPROT(axi_S0_ARPROT),.ARVALID(axi_S0_ARVALID),.ARREADY(axi_S0_ARREADY),
        .RDATA (axi_S0_RDATA), .RRESP (axi_S0_RRESP), .RVALID (axi_S0_RVALID), .RREADY (axi_S0_RREADY),
        .irq(axi_irq0));

    axi_sfr u_axi_sfr1 (.clk(clk_cpu),.rst_n(rst_cpu_n),
        .AWADDR(axi_S1_AWADDR),.AWPROT(axi_S1_AWPROT),.AWVALID(axi_S1_AWVALID),.AWREADY(axi_S1_AWREADY),
        .WDATA (axi_S1_WDATA), .WSTRB (axi_S1_WSTRB), .WVALID (axi_S1_WVALID), .WREADY (axi_S1_WREADY),
        .BRESP (axi_S1_BRESP), .BVALID(axi_S1_BVALID),.BREADY (axi_S1_BREADY),
        .ARADDR(axi_S1_ARADDR),.ARPROT(axi_S1_ARPROT),.ARVALID(axi_S1_ARVALID),.ARREADY(axi_S1_ARREADY),
        .RDATA (axi_S1_RDATA), .RRESP (axi_S1_RRESP), .RVALID (axi_S1_RVALID), .RREADY (axi_S1_RREADY),
        .irq(axi_irq1));

    axi_sfr u_axi_sfr2 (.clk(clk_cpu),.rst_n(rst_cpu_n),
        .AWADDR(axi_S2_AWADDR),.AWPROT(axi_S2_AWPROT),.AWVALID(axi_S2_AWVALID),.AWREADY(axi_S2_AWREADY),
        .WDATA (axi_S2_WDATA), .WSTRB (axi_S2_WSTRB), .WVALID (axi_S2_WVALID), .WREADY (axi_S2_WREADY),
        .BRESP (axi_S2_BRESP), .BVALID(axi_S2_BVALID),.BREADY (axi_S2_BREADY),
        .ARADDR(axi_S2_ARADDR),.ARPROT(axi_S2_ARPROT),.ARVALID(axi_S2_ARVALID),.ARREADY(axi_S2_ARREADY),
        .RDATA (axi_S2_RDATA), .RRESP (axi_S2_RRESP), .RVALID (axi_S2_RVALID), .RREADY (axi_S2_RREADY),
        .irq(axi_irq2));

    //=========================================================
    // 19. AHB Group — CDC FIFOs + Interface + Interconnect + SFRs
    //=========================================================

    // Request FIFO: CPU (1GHz write) → AHB (500MHz read)
    logic        req_fifo_rd_en;
    logic [66:0] req_fifo_rd_data;
    logic        req_fifo_rd_empty;

    async_fifo_depth2 #(.DATA_WIDTH(67)) u_req_fifo (
        .wr_clk  (clk_cpu),
        .wr_rst_n(rst_cpu_n),
        .wr_en   (req_fifo_wr_en),
        .wr_data (req_fifo_wr_data),
        .rd_clk  (clk_ahb),
        .rd_rst_n(rst_ahb_n),
        .rd_en   (req_fifo_rd_en),
        .rd_data (req_fifo_rd_data),
        .rd_empty(req_fifo_rd_empty)
    );

    // Response FIFO: AHB (500MHz write) → CPU (1GHz read)
    logic        resp_fifo_wr_en;
    logic [32:0] resp_fifo_wr_data;

    async_fifo_depth2 #(.DATA_WIDTH(33)) u_resp_fifo (
        .wr_clk  (clk_ahb),
        .wr_rst_n(rst_ahb_n),
        .wr_en   (resp_fifo_wr_en),
        .wr_data (resp_fifo_wr_data),
        .rd_clk  (clk_cpu),
        .rd_rst_n(rst_cpu_n),
        .rd_en   (resp_fifo_rd_en),
        .rd_data (resp_fifo_rd_data),
        .rd_empty(resp_fifo_rd_empty)
    );

    // AHB master ↔ interconnect
    logic [31:0] ahb_HADDR;  logic [2:0] ahb_HSIZE; logic [1:0] ahb_HTRANS;
    logic        ahb_HWRITE; logic [31:0] ahb_HWDATA;
    logic        ahb_HREADY; logic [31:0] ahb_HRDATA; logic ahb_HRESP;

    ahb_interface u_ahb_if (
        .clk_ahb      (clk_ahb),
        .rst_ahb_n    (rst_ahb_n),
        .req_empty    (req_fifo_rd_empty),
        .req_rd_en    (req_fifo_rd_en),
        .req_rd_data  (req_fifo_rd_data),
        .resp_wr_en   (resp_fifo_wr_en),
        .resp_wr_data (resp_fifo_wr_data),
        .HADDR        (ahb_HADDR),
        .HSIZE        (ahb_HSIZE),
        .HTRANS       (ahb_HTRANS),
        .HWRITE       (ahb_HWRITE),
        .HWDATA       (ahb_HWDATA),
        .HREADY       (ahb_HREADY),
        .HRDATA       (ahb_HRDATA),
        .HRESP        (ahb_HRESP)
    );

    // Interconnect ↔ Slaves
    logic        ahb_HSEL0, ahb_HREADY0_in, ahb_HREADYOUT0, ahb_HRESP0;
    logic [31:0] ahb_HRDATA0; logic ahb_irq0;
    logic        ahb_HSEL1, ahb_HREADY1_in, ahb_HREADYOUT1, ahb_HRESP1;
    logic [31:0] ahb_HRDATA1; logic ahb_irq1;
    logic        ahb_HSEL2, ahb_HREADY2_in, ahb_HREADYOUT2, ahb_HRESP2;
    logic [31:0] ahb_HRDATA2; logic ahb_irq2;

    ahb_interconnect u_ahb_xbar (
        .clk_ahb     (clk_ahb),
        .rst_ahb_n   (rst_ahb_n),
        .HADDR       (ahb_HADDR),
        .HSIZE       (ahb_HSIZE),
        .HTRANS      (ahb_HTRANS),
        .HWRITE      (ahb_HWRITE),
        .HWDATA      (ahb_HWDATA),
        .HREADY      (ahb_HREADY),
        .HRDATA      (ahb_HRDATA),
        .HRESP       (ahb_HRESP),
        .HSEL0       (ahb_HSEL0),     .HREADY0_in(ahb_HREADY0_in),
        .HREADYOUT0  (ahb_HREADYOUT0),.HRDATA0   (ahb_HRDATA0),
        .HRESP0      (ahb_HRESP0),    .irq0      (ahb_irq0),
        .HSEL1       (ahb_HSEL1),     .HREADY1_in(ahb_HREADY1_in),
        .HREADYOUT1  (ahb_HREADYOUT1),.HRDATA1   (ahb_HRDATA1),
        .HRESP1      (ahb_HRESP1),    .irq1      (ahb_irq1),
        .HSEL2       (ahb_HSEL2),     .HREADY2_in(ahb_HREADY2_in),
        .HREADYOUT2  (ahb_HREADYOUT2),.HRDATA2   (ahb_HRDATA2),
        .HRESP2      (ahb_HRESP2),    .irq2      (ahb_irq2),
        .ahb_irq     (ahb_irq_raw)
    );

    ahb_sfr u_ahb_sfr0 (.clk_ahb(clk_ahb),.rst_ahb_n(rst_ahb_n),
        .HSEL(ahb_HSEL0),.HREADY(ahb_HREADY0_in),
        .HADDR(ahb_HADDR),.HTRANS(ahb_HTRANS),.HWRITE(ahb_HWRITE),.HWDATA(ahb_HWDATA),
        .HRDATA(ahb_HRDATA0),.HREADYOUT(ahb_HREADYOUT0),.HRESP(ahb_HRESP0),.irq(ahb_irq0));

    ahb_sfr u_ahb_sfr1 (.clk_ahb(clk_ahb),.rst_ahb_n(rst_ahb_n),
        .HSEL(ahb_HSEL1),.HREADY(ahb_HREADY1_in),
        .HADDR(ahb_HADDR),.HTRANS(ahb_HTRANS),.HWRITE(ahb_HWRITE),.HWDATA(ahb_HWDATA),
        .HRDATA(ahb_HRDATA1),.HREADYOUT(ahb_HREADYOUT1),.HRESP(ahb_HRESP1),.irq(ahb_irq1));

    ahb_sfr u_ahb_sfr2 (.clk_ahb(clk_ahb),.rst_ahb_n(rst_ahb_n),
        .HSEL(ahb_HSEL2),.HREADY(ahb_HREADY2_in),
        .HADDR(ahb_HADDR),.HTRANS(ahb_HTRANS),.HWRITE(ahb_HWRITE),.HWDATA(ahb_HWDATA),
        .HRDATA(ahb_HRDATA2),.HREADYOUT(ahb_HREADYOUT2),.HRESP(ahb_HRESP2),.irq(ahb_irq2));

endmodule
