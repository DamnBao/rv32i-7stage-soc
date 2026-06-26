// SoC Top-Level Integration
//
// RV32I + Zicsr, 7-stage pipeline @ 1GHz
// AXI-Lite peripherals @ 1GHz (direct, synchronous)
// AHB-Lite peripherals @ 500MHz (via Dual Async FIFO CDC)
//
// Pipeline stages: IF1 → IF2 → ID → EX → MEM1 → MEM2 → WB
//
// Module instances:
//   Fetch      : if1_stage, imem, if1_if2_reg, if2_stage, if2_id_reg
//   Decode     : id_decoder, register_file, id_ex_reg
//   Execute    : ex_stage  (wraps forwarding_unit + alu + branch_comp + addr_adder)
//   Memory     : ex_mem1_reg, mem1_stage, dmem, mem1_mem2_reg, mem2_stage
//   Write-back : mem2_wb_reg, wb_stage
//   Control    : hazard_unit, zicsr, plic
//   AXI group  : axi_interface, axi_interconnect
//   AHB group  : reset_sync ×2, irq_sync2ff ×3, async_fifo ×2, ahb_interface, ahb_interconnect
//
// Chip boundary: AXI slave ports (×3) and AHB slave ports (×3) are exposed as
// module I/O. Any peripheral implementing the SFR standard register map may be
// plugged in externally without modifying this file.

module soc_top #(
    parameter PC_RESET_VAL = 32'h0000_0000,
    parameter IMEM_SIZE_KB = 64   // Override to 256 for compliance testbench; production default = 64
)(
    input  logic clk_cpu,   // 1GHz — CPU + AXI domain
    input  logic clk_ahb,   // 500MHz — AHB peripheral domain
    input  logic rst_n,     // Async active-low reset (internally sync-deasserted)

    // ── Synchronized reset outputs (for external peripherals) ──
    output logic rst_cpu_n_o,   // rst_cpu_n exposed for AXI peripheral FFs
    output logic rst_ahb_n_o,   // rst_ahb_n exposed for AHB peripheral FFs

    // ── AXI-Lite Slave ports × 3 (1GHz) ──
    // Slave 0 (base = 0x2000_0000)
    output logic [31:0] axi_S0_AWADDR,  output logic [2:0]  axi_S0_AWPROT,
    output logic        axi_S0_AWVALID, input  logic        axi_S0_AWREADY,
    output logic [31:0] axi_S0_WDATA,   output logic [3:0]  axi_S0_WSTRB,
    output logic        axi_S0_WVALID,  input  logic        axi_S0_WREADY,
    input  logic [1:0]  axi_S0_BRESP,   input  logic        axi_S0_BVALID,
    output logic        axi_S0_BREADY,
    output logic [31:0] axi_S0_ARADDR,  output logic [2:0]  axi_S0_ARPROT,
    output logic        axi_S0_ARVALID, input  logic        axi_S0_ARREADY,
    input  logic [31:0] axi_S0_RDATA,   input  logic [1:0]  axi_S0_RRESP,
    input  logic        axi_S0_RVALID,  output logic        axi_S0_RREADY,
    input  logic        axi_S0_irq,     // IRQ from AXI slave 0 (1GHz, direct to PLIC src 1)

    // Slave 1 (base = 0x2000_1000)
    output logic [31:0] axi_S1_AWADDR,  output logic [2:0]  axi_S1_AWPROT,
    output logic        axi_S1_AWVALID, input  logic        axi_S1_AWREADY,
    output logic [31:0] axi_S1_WDATA,   output logic [3:0]  axi_S1_WSTRB,
    output logic        axi_S1_WVALID,  input  logic        axi_S1_WREADY,
    input  logic [1:0]  axi_S1_BRESP,   input  logic        axi_S1_BVALID,
    output logic        axi_S1_BREADY,
    output logic [31:0] axi_S1_ARADDR,  output logic [2:0]  axi_S1_ARPROT,
    output logic        axi_S1_ARVALID, input  logic        axi_S1_ARREADY,
    input  logic [31:0] axi_S1_RDATA,   input  logic [1:0]  axi_S1_RRESP,
    input  logic        axi_S1_RVALID,  output logic        axi_S1_RREADY,
    input  logic        axi_S1_irq,     // IRQ from AXI slave 1 (PLIC src 2)

    // Slave 2 (base = 0x2000_2000)
    output logic [31:0] axi_S2_AWADDR,  output logic [2:0]  axi_S2_AWPROT,
    output logic        axi_S2_AWVALID, input  logic        axi_S2_AWREADY,
    output logic [31:0] axi_S2_WDATA,   output logic [3:0]  axi_S2_WSTRB,
    output logic        axi_S2_WVALID,  input  logic        axi_S2_WREADY,
    input  logic [1:0]  axi_S2_BRESP,   input  logic        axi_S2_BVALID,
    output logic        axi_S2_BREADY,
    output logic [31:0] axi_S2_ARADDR,  output logic [2:0]  axi_S2_ARPROT,
    output logic        axi_S2_ARVALID, input  logic        axi_S2_ARREADY,
    input  logic [31:0] axi_S2_RDATA,   input  logic [1:0]  axi_S2_RRESP,
    input  logic        axi_S2_RVALID,  output logic        axi_S2_RREADY,
    input  logic        axi_S2_irq,     // IRQ from AXI slave 2 (PLIC src 3)

    // ── AHB-Lite shared bus outputs (500MHz, broadcast to all AHB slaves) ──
    output logic [31:0] ahb_HADDR_o,
    output logic [2:0]  ahb_HSIZE_o,
    output logic [1:0]  ahb_HTRANS_o,
    output logic        ahb_HWRITE_o,
    output logic [31:0] ahb_HWDATA_o,

    // ── AHB-Lite Slave ports × 3 (500MHz) ──
    // Slave 0 (base = 0x3000_0000)
    output logic        ahb_S0_HSEL_o,
    output logic        ahb_S0_HREADY_o,
    input  logic        ahb_S0_HREADYOUT_i,
    input  logic [31:0] ahb_S0_HRDATA_i,
    input  logic        ahb_S0_HRESP_i,
    input  logic        ahb_S0_irq_i,   // IRQ from AHB slave 0 (500MHz, needs 2-FF sync → PLIC src 4)

    // Slave 1 (base = 0x3000_1000)
    output logic        ahb_S1_HSEL_o,
    output logic        ahb_S1_HREADY_o,
    input  logic        ahb_S1_HREADYOUT_i,
    input  logic [31:0] ahb_S1_HRDATA_i,
    input  logic        ahb_S1_HRESP_i,
    input  logic        ahb_S1_irq_i,   // IRQ from AHB slave 1 (→ PLIC src 5)

    // Slave 2 (base = 0x3000_2000)
    output logic        ahb_S2_HSEL_o,
    output logic        ahb_S2_HREADY_o,
    input  logic        ahb_S2_HREADYOUT_i,
    input  logic [31:0] ahb_S2_HRDATA_i,
    input  logic        ahb_S2_HRESP_i,
    input  logic        ahb_S2_irq_i    // IRQ from AHB slave 2 (→ PLIC src 6)
);

    //=========================================================
    // Internal signal declarations
    //=========================================================

    // ── Domain resets ───────────────────────────────────────
    logic rst_cpu_n, rst_ahb_n;

    // ── Branch predictor ────────────────────────────────────
    logic        bp_predict_taken;
    logic [31:0] bp_predict_target;
    logic        bp_update_en;
    logic        ex_actual_redirect;
    logic        bp_mismatch;
    logic [31:0] bp_correct_pc;

    // ── IF1 stage ───────────────────────────────────────────
    logic [31:0] if1_pc;
    logic [31:0] if1_jump_addr;  // Mux: zicsr_pc (trap) or bp_correct_pc (mismatch correction)

    // ── IF1/IF2 pipeline register ───────────────────────────
    logic [31:0] if1if2_pc;
    logic        if1if2_bp_taken;
    logic [31:0] if1if2_bp_target;

    // ── IMEM ────────────────────────────────────────────────
    logic [31:0] imem_instr;

    // ── IF2 stage (pass-through) ────────────────────────────
    logic [31:0] if2_pc, if2_instr;
    logic        if2_bp_taken;
    logic [31:0] if2_bp_target;

    // ── IF2/ID pipeline register ────────────────────────────
    logic [31:0] if2id_pc, if2id_instr;
    logic        if2id_bp_taken;
    logic [31:0] if2id_bp_target;

    // ── ID stage: decoder outputs ───────────────────────────
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

    // ── Register file outputs ────────────────────────────────
    logic [31:0] rf_rs1_data, rf_rs2_data;

    // ── ID/EX pipeline register ──────────────────────────────
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
    logic        idex_bp_taken;
    logic [31:0] idex_bp_target;

    // ── EX stage outputs ────────────────────────────────────
    logic [31:0] ex_rs1_fwd;      // Forwarded rs1 → EX/MEM1 (CSR write source)
    logic [31:0] ex_rs2_fwd;      // Forwarded rs2 → EX/MEM1 (store data)
    logic [31:0] ex_alu_result;
    logic        ex_branch_taken;
    logic [31:0] ex_jump_addr;

    // ── EX/MEM1 pipeline register ────────────────────────────
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

    // ── MEM1 stage outputs ───────────────────────────────────
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

    // ── DMEM interface ───────────────────────────────────────
    logic        dmem_re, dmem_we;
    logic [31:0] dmem_addr, dmem_wdata;
    logic [1:0]  dmem_size;
    logic [31:0] dmem_rdata;

    // ── AXI interface (CPU side) ─────────────────────────────
    logic        axi_req_valid;
    logic [31:0] axi_req_addr;
    logic        axi_req_we;
    logic [31:0] axi_req_wdata;
    logic [1:0]  axi_req_size;
    logic        axi_resp_valid;
    logic [31:0] axi_resp_rdata;
    logic        axi_resp_err;

    // ── AHB Request/Response FIFOs (CPU ↔ AHB domain) ───────
    logic        req_fifo_wr_en;
    logic [66:0] req_fifo_wr_data;
    logic        resp_fifo_rd_empty;
    logic        resp_fifo_rd_en;
    logic [32:0] resp_fifo_rd_data;

    // ── MEM1/MEM2 pipeline register ──────────────────────────
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

    // ── MEM2 stage outputs ───────────────────────────────────
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

    // ── MEM2/WB pipeline register ────────────────────────────
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

    // ── WB stage outputs → register file ────────────────────
    logic [4:0]  rf_wr_addr;
    logic        rf_wr_we;
    logic [31:0] rf_wr_data;

    // ── Zicsr outputs ────────────────────────────────────────
    logic [31:0] csr_rdata;
    logic        zicsr_flush;
    logic [31:0] zicsr_pc;

    // ── PLIC interface (mem1_stage ↔ plic) ──────────────────
    logic        plic_re, plic_we;
    logic [23:0] plic_addr;
    logic [31:0] plic_wdata, plic_rdata;
    logic        plic_meip;

    // ── AHB IRQ lines (synchronized to 1GHz CPU domain) ─────
    logic ahb_irq0_sync, ahb_irq1_sync, ahb_irq2_sync;

    // ── Hazard unit stall/flush controls ─────────────────────
    logic stall_pc, flush_pc;
    logic stall_if1if2,  flush_if1if2;
    logic stall_if2id,   flush_if2id;
    logic stall_idex,    flush_idex;
    logic stall_exmem1,  flush_exmem1;
    logic stall_mem1mem2, flush_mem1mem2;
    logic stall_mem2wb,  flush_mem2wb;

    // ── Branch predictor mismatch: compute actual redirect and correction address ──
    // ex_actual_redirect: 1 when branch IS taken or instruction is an unconditional jump
    // bp_mismatch: prediction was wrong (direction or target differs from actual)
    // bp_correct_pc: the right PC to load on mismatch
    //   - branch taken / jump: use actual target (ex_jump_addr)
    //   - branch not taken:    use sequential PC (idex_pc + 4)
    assign ex_actual_redirect = ex_branch_taken | idex_jump;
    assign bp_mismatch = (idex_branch | idex_jump) &&
                         ((ex_actual_redirect != idex_bp_taken) ||
                          (ex_actual_redirect && (ex_jump_addr != idex_bp_target)));
    assign bp_correct_pc = ex_actual_redirect ? ex_jump_addr : (idex_pc + 32'd4);

    // ── Predictor update enable: one update per branch/jump, suppressed during bus stall ──
    assign bp_update_en = (idex_branch | idex_jump) & ~bus_stall_req;

    // ── PC redirect MUX: trap takes highest priority, then bp_mismatch correction ──
    assign if1_jump_addr = zicsr_flush ? zicsr_pc : bp_correct_pc;

    //=========================================================
    // 0. Domain Reset Synchronizers
    //    Async-assert, sync-deassert — one per clock domain
    //=========================================================
    reset_sync u_rst_cpu (
        .clk        (clk_cpu),   // input:  1GHz clock
        .async_rst_n(rst_n),     // input:  external async reset
        .sync_rst_n (rst_cpu_n)  // output: synchronized reset for CPU domain
    );

    reset_sync u_rst_ahb (
        .clk        (clk_ahb),   // input:  500MHz clock
        .async_rst_n(rst_n),     // input:  external async reset
        .sync_rst_n (rst_ahb_n)  // output: synchronized reset for AHB domain
    );

    //=========================================================
    // 0.5. Branch Predictor — 16-entry 2-bit BHT + BTB
    //      Lookup uses IF1 PC (combinational); update at EX resolution.
    //=========================================================
    branch_predictor u_bp (
        .clk           (clk_cpu),           // input:  1GHz clock
        .rst_n         (rst_cpu_n),         // input:  CPU domain reset
        // ── IF1 lookup ──
        .fetch_pc      (if1_pc),            // input:  current IF1 PC
        .predict_taken (bp_predict_taken),  // output: 1 = speculative redirect
        .predict_target(bp_predict_target), // output: predicted target address
        // ── EX update ──
        .update_en     (bp_update_en),      // input:  branch/jump resolved at EX
        .update_pc     (idex_pc),           // input:  PC of resolved branch/jump
        .update_taken  (ex_actual_redirect),// input:  actual taken / not-taken
        .update_target (ex_jump_addr)       // input:  actual target address
    );

    //=========================================================
    // 1. IF1 Stage — PC register, next-PC select
    //=========================================================
    if1_stage #(.PC_RESET_VAL(PC_RESET_VAL)) u_if1 (
        .clk         (clk_cpu),          // input:  1GHz clock
        .rst_n       (rst_cpu_n),        // input:  CPU domain reset
        .stall       (stall_pc),         // input:  freeze PC (hazard_unit)
        .flush       (flush_if1if2),     // input:  redirect PC (bp_mismatch or trap)
        .jump_addr   (if1_jump_addr),    // input:  correction/trap target address
        .bp_redirect (bp_predict_taken), // input:  speculative redirect from predictor
        .bp_target   (bp_predict_target),// input:  predicted target address
        .pc_out      (if1_pc)            // output: current PC → IMEM + if1_if2_reg
    );

    //=========================================================
    // 2. IMEM — Synchronous instruction memory (1GHz)
    //=========================================================
    imem #(.SIZE_KB(IMEM_SIZE_KB)) u_imem (
        .clk      (clk_cpu),      // input:  1GHz clock
        .stall    (stall_if1if2), // input:  hold output in sync with if1_if2_reg freeze
        .flush    (flush_if1if2), // input:  output NOP to prevent ghost instruction at ID
        .addr     (if1_pc),       // input:  instruction address from if1_stage
        .instr_out(imem_instr)    // output: instruction word → if2_stage
    );

    //=========================================================
    // 3. IF1/IF2 Pipeline Register
    //=========================================================
    if1_if2_reg u_if1if2 (
        .clk          (clk_cpu),           // input:  1GHz clock
        .rst_n        (rst_cpu_n),         // input:  CPU domain reset
        .stall        (stall_if1if2),      // input:  freeze
        .flush        (flush_if1if2),      // input:  clear to bubble
        .pc_in        (if1_pc),            // input:  PC from if1_stage
        .bp_taken_in  (bp_predict_taken),  // input:  prediction for if1_pc
        .bp_target_in (bp_predict_target), // input:  predicted target for if1_pc
        .pc_out       (if1if2_pc),         // output: registered PC → if2_stage
        .bp_taken_out (if1if2_bp_taken),   // output: prediction propagating with instruction
        .bp_target_out(if1if2_bp_target)   // output: predicted target propagating
    );

    //=========================================================
    // 4. IF2 Stage — instruction/PC pass-through
    //    Exists as a named stage so pipeline register naming stays consistent.
    //    Branch prediction or I-cache miss handling would go here.
    //=========================================================
    if2_stage u_if2 (
        .pc_in        (if1if2_pc),       // input:  PC from IF1/IF2 register
        .instr_in     (imem_instr),      // input:  instruction from IMEM
        .bp_taken_in  (if1if2_bp_taken), // input:  prediction metadata
        .bp_target_in (if1if2_bp_target),
        .pc_out       (if2_pc),          // output: PC → if2_id_reg
        .instr_out    (if2_instr),       // output: instruction → if2_id_reg
        .bp_taken_out (if2_bp_taken),    // output: prediction propagating
        .bp_target_out(if2_bp_target)
    );

    //=========================================================
    // 5. IF2/ID Pipeline Register
    //=========================================================
    if2_id_reg u_if2id (
        .clk          (clk_cpu),       // input:  1GHz clock
        .rst_n        (rst_cpu_n),     // input:  CPU domain reset
        .stall        (stall_if2id),   // input:  freeze
        .flush        (flush_if2id),   // input:  clear to NOP bubble
        .pc_in        (if2_pc),        // input:  PC from if2_stage
        .instr_in     (if2_instr),     // input:  instruction from if2_stage
        .bp_taken_in  (if2_bp_taken),  // input:  prediction metadata from if2_stage
        .bp_target_in (if2_bp_target),
        .pc_out       (if2id_pc),      // output: PC → id_decoder + id_ex_reg
        .instr_out    (if2id_instr),   // output: instruction → id_decoder
        .bp_taken_out (if2id_bp_taken),
        .bp_target_out(if2id_bp_target)
    );

    //=========================================================
    // 6. ID Stage — Instruction Decode + Register File Read
    //=========================================================
    id_decoder u_id_dec (
        .instr        (if2id_instr),   // input:  32-bit instruction word
        .rs1_addr     (id_rs1_addr),   // output: rs1 register index → register_file
        .rs2_addr     (id_rs2_addr),   // output: rs2 register index → register_file
        .rd_addr      (id_rd_addr),    // output: rd register index  → id_ex_reg
        .csr_addr     (id_csr_addr),   // output: CSR address [11:0] → id_ex_reg
        .funct3       (id_funct3),     // output: funct3 field       → id_ex_reg
        .imm          (id_imm),        // output: sign-extended immediate
        .alu_op       (id_alu_op),     // output: ALU operation code
        .alu_src_a    (id_alu_src_a),  // output: 0=rs1,  1=PC
        .alu_src_b    (id_alu_src_b),  // output: 0=rs2,  1=imm
        .branch       (id_branch),     // output: 1 if B-type
        .jump         (id_jump),       // output: 1 if JAL/JALR
        .jump_reg     (id_jump_reg),   // output: 1 if JALR
        .mem_read     (id_mem_read),   // output: 1 if load instruction
        .mem_write    (id_mem_write),  // output: 1 if store instruction
        .mem_size     (id_mem_size),   // output: 00=byte 01=half 10=word
        .mem_ext      (id_mem_ext),    // output: 0=zero-ext 1=sign-ext
        .reg_write    (id_reg_write),  // output: 1 if rd is written at WB
        .wb_sel       (id_wb_sel),     // output: 00=ALU 01=MEM 10=PC+4 11=CSR
        .csr_we       (id_csr_we),     // output: CSR write enable
        .csr_op       (id_csr_op),     // output: 01=RW 10=RS 11=RC
        .csr_imm_sel  (id_csr_imm_sel),// output: 0=rs1 source 1=zimm source
        .ecall        (id_ecall),      // output: ECALL detected
        .ebreak       (id_ebreak),     // output: EBREAK detected
        .mret         (id_mret),       // output: MRET detected
        .illegal_instr(id_illegal)     // output: unrecognized opcode
    );

    register_file u_rf (
        .clk     (clk_cpu),     // input:  1GHz clock (write port is synchronous)
        .rst_n   (rst_cpu_n),   // input:  CPU domain reset
        .rs1_addr(id_rs1_addr), // input:  read port 1 address (from id_decoder)
        .rs1_data(rf_rs1_data), // output: read data 1 → id_ex_reg
        .rs2_addr(id_rs2_addr), // input:  read port 2 address
        .rs2_data(rf_rs2_data), // output: read data 2 → id_ex_reg
        .we      (rf_wr_we),    // input:  write enable (from wb_stage)
        .rd_addr (rf_wr_addr),  // input:  write address (from wb_stage)
        .rd_data (rf_wr_data)   // input:  write data   (from wb_stage)
    );

    //=========================================================
    // 7. ID/EX Pipeline Register
    //=========================================================
    id_ex_reg u_idex (
        .clk              (clk_cpu),
        .rst_n            (rst_cpu_n),
        .stall            (stall_idex),       // input:  freeze (load-use / CSR-use / bus stall)
        .flush            (flush_idex),       // input:  insert NOP bubble (load-use / CSR-use)
        // ── Inputs from ID stage ──
        .pc_in            (if2id_pc),         // input:  PC of instruction at ID
        .rs1_data_in      (rf_rs1_data),      // input:  register file read 1
        .rs2_data_in      (rf_rs2_data),      // input:  register file read 2
        .imm_in           (id_imm),
        .rs1_addr_in      (id_rs1_addr),
        .rs2_addr_in      (id_rs2_addr),
        .rd_addr_in       (id_rd_addr),
        .csr_addr_in      (id_csr_addr),
        .funct3_in        (id_funct3),
        .alu_op_in        (id_alu_op),
        .alu_src_a_in     (id_alu_src_a),
        .alu_src_b_in     (id_alu_src_b),
        .branch_in        (id_branch),
        .jump_in          (id_jump),
        .jump_reg_in      (id_jump_reg),
        .mem_read_in      (id_mem_read),
        .mem_write_in     (id_mem_write),
        .mem_size_in      (id_mem_size),
        .mem_ext_in       (id_mem_ext),
        .reg_write_in     (id_reg_write),
        .wb_sel_in        (id_wb_sel),
        .csr_we_in        (id_csr_we),
        .csr_op_in        (id_csr_op),
        .csr_imm_sel_in   (id_csr_imm_sel),
        .ecall_in         (id_ecall),
        .ebreak_in        (id_ebreak),
        .mret_in          (id_mret),
        .illegal_instr_in (id_illegal),
        .bp_taken_in      (if2id_bp_taken),   // input:  prediction from IF2/ID register
        .bp_target_in     (if2id_bp_target),
        // ── Outputs to EX stage ──
        .pc_out           (idex_pc),          // output: registered PC
        .rs1_data_out     (idex_rs1_data),    // output: rs1 (pre-forward; ex_stage resolves)
        .rs2_data_out     (idex_rs2_data),
        .imm_out          (idex_imm),
        .rs1_addr_out     (idex_rs1_addr),
        .rs2_addr_out     (idex_rs2_addr),
        .rd_addr_out      (idex_rd_addr),
        .csr_addr_out     (idex_csr_addr),
        .funct3_out       (idex_funct3),
        .alu_op_out       (idex_alu_op),
        .alu_src_a_out    (idex_alu_src_a),
        .alu_src_b_out    (idex_alu_src_b),
        .branch_out       (idex_branch),
        .jump_out         (idex_jump),
        .jump_reg_out     (idex_jump_reg),
        .mem_read_out     (idex_mem_read),
        .mem_write_out    (idex_mem_write),
        .mem_size_out     (idex_mem_size),
        .mem_ext_out      (idex_mem_ext),
        .reg_write_out    (idex_reg_write),
        .wb_sel_out       (idex_wb_sel),
        .csr_we_out       (idex_csr_we),
        .csr_op_out       (idex_csr_op),
        .csr_imm_sel_out  (idex_csr_imm_sel),
        .ecall_out        (idex_ecall),
        .ebreak_out       (idex_ebreak),
        .mret_out         (idex_mret),
        .illegal_instr_out(idex_illegal),
        .bp_taken_out     (idex_bp_taken),   // output: prediction arriving at EX
        .bp_target_out    (idex_bp_target)
    );

    //=========================================================
    // 8. EX Stage — Forwarding + ALU + Branch + Address
    //    All combinational EX datapath logic is inside ex_stage;
    //    soc_top contains no datapath logic for this stage.
    //=========================================================
    ex_stage u_ex (
        // ── Inputs from ID/EX register ──
        .idex_pc        (idex_pc),           // input:  PC at EX (for AUIPC, JAL, branch)
        .idex_rs1_data  (idex_rs1_data),     // input:  raw rs1 from register file
        .idex_rs2_data  (idex_rs2_data),     // input:  raw rs2 from register file
        .idex_imm       (idex_imm),          // input:  sign-extended immediate
        .idex_rs1_addr  (idex_rs1_addr),     // input:  rs1 address → forwarding_unit
        .idex_rs2_addr  (idex_rs2_addr),     // input:  rs2 address → forwarding_unit
        .idex_alu_op    (idex_alu_op),       // input:  ALU operation
        .idex_alu_src_a (idex_alu_src_a),   // input:  ALU_A select (rs1 or PC)
        .idex_alu_src_b (idex_alu_src_b),   // input:  ALU_B select (rs2 or imm)
        .idex_funct3    (idex_funct3),       // input:  branch type
        .idex_branch    (idex_branch),       // input:  1 if B-type instruction
        .idex_jump      (idex_jump),         // input:  1 if JAL/JALR
        .idex_jump_reg  (idex_jump_reg),     // input:  1 if JALR
        // ── Forwarding source: gap-1 (EX/MEM1 register) ──
        .mem1_rd_addr   (exmem1_rd_addr),    // input:  rd at MEM1
        .mem1_reg_write (exmem1_reg_write),  // input:  MEM1 writes rd
        .mem1_alu_result(exmem1_alu_result), // input:  MEM1 forwarding value
        // ── Forwarding source: gap-2 (MEM1/MEM2 reg + MEM2 stage) ──
        .mem2_rd_addr   (mem1mem2_rd_addr),  // input:  rd at MEM2
        .mem2_reg_write (mem1mem2_reg_write),// input:  MEM2 writes rd
        .mem2_wb_sel    (mem1mem2_wb_sel),   // input:  01=load rdata else alu_result
        .mem2_alu_result(mem2_alu_result),   // input:  MEM2 ALU result
        .mem2_mem_rdata (mem2_mem_rdata),    // input:  MEM2 load data
        // ── Forwarding source: gap-3 (WB stage) ──
        .wb_rd_addr     (wb_rd_addr),        // input:  rd at WB
        .wb_reg_write   (wb_reg_write),      // input:  WB writes rd
        .wb_wr_data     (rf_wr_data),        // input:  WB write-back value
        // ── Outputs ──
        .ex_rs1_fwd     (ex_rs1_fwd),        // output: forwarded rs1 → EX/MEM1 (CSR src)
        .ex_rs2_fwd     (ex_rs2_fwd),        // output: forwarded rs2 → EX/MEM1 (store data)
        .ex_alu_result  (ex_alu_result),     // output: ALU result   → EX/MEM1
        .ex_branch_taken(ex_branch_taken),   // output: branch taken → hazard_unit
        .ex_jump_addr   (ex_jump_addr)       // output: target addr  → if1_jump_addr mux
    );

    //=========================================================
    // 9. EX/MEM1 Pipeline Register
    //=========================================================
    ex_mem1_reg u_exmem1 (
        .clk               (clk_cpu),
        .rst_n             (rst_cpu_n),
        .stall             (stall_exmem1),       // input:  freeze (bus stall)
        .flush             (flush_exmem1),       // input:  clear (trap)
        // ── Inputs from EX stage ──
        .pc_in             (idex_pc),            // input:  PC of instruction at EX
        .alu_result_in     (ex_alu_result),      // input:  ALU result (= mem address for load/store)
        .rs2_data_in       (ex_rs2_fwd),         // input:  store data (forwarded)
        .rs1_data_in       (ex_rs1_fwd),         // input:  CSR write source (forwarded)
        .imm_in            (idex_imm),
        .rd_addr_in        (idex_rd_addr),
        .csr_addr_in       (idex_csr_addr),
        .mem_read_in       (idex_mem_read),
        .mem_write_in      (idex_mem_write),
        .mem_size_in       (idex_mem_size),
        .mem_ext_in        (idex_mem_ext),
        .reg_write_in      (idex_reg_write),
        .wb_sel_in         (idex_wb_sel),
        .csr_we_in         (idex_csr_we),
        .csr_op_in         (idex_csr_op),
        .csr_imm_sel_in    (idex_csr_imm_sel),
        .ecall_in          (idex_ecall),
        .ebreak_in         (idex_ebreak),
        .mret_in           (idex_mret),
        .illegal_instr_in  (idex_illegal),
        // ── Outputs to MEM1 stage ──
        .pc_out            (exmem1_pc),
        .alu_result_out    (exmem1_alu_result),  // output: also forwarding gap-1 source
        .rs2_data_out      (exmem1_rs2_data),
        .rs1_data_out      (exmem1_rs1_data),
        .imm_out           (exmem1_imm),
        .rd_addr_out       (exmem1_rd_addr),     // output: also used by forwarding_unit
        .csr_addr_out      (exmem1_csr_addr),
        .mem_read_out      (exmem1_mem_read),
        .mem_write_out     (exmem1_mem_write),
        .mem_size_out      (exmem1_mem_size),
        .mem_ext_out       (exmem1_mem_ext),
        .reg_write_out     (exmem1_reg_write),   // output: also used by forwarding_unit
        .wb_sel_out        (exmem1_wb_sel),
        .csr_we_out        (exmem1_csr_we),
        .csr_op_out        (exmem1_csr_op),
        .csr_imm_sel_out   (exmem1_csr_imm_sel),
        .ecall_out         (exmem1_ecall),
        .ebreak_out        (exmem1_ebreak),
        .mret_out          (exmem1_mret),
        .illegal_instr_out (exmem1_illegal)
    );

    //=========================================================
    // 10. MEM1 Stage — Address Decode + Bus Transaction FSM
    //=========================================================
    mem1_stage u_mem1 (
        .clk               (clk_cpu),
        .rst_n             (rst_cpu_n),
        // ── Inputs from EX/MEM1 register ──
        .addr_in           (exmem1_alu_result), // input:  memory address (ALU result)
        .wdata_in          (exmem1_rs2_data),   // input:  store write data
        .rs1_data_in       (exmem1_rs1_data),   // input:  CSR write source
        .imm_in            (exmem1_imm),
        .pc_in             (exmem1_pc),
        .rd_addr_in        (exmem1_rd_addr),
        .csr_addr_in       (exmem1_csr_addr),
        .mem_read_in       (exmem1_mem_read),
        .mem_write_in      (exmem1_mem_write),
        .mem_size_in       (exmem1_mem_size),
        .mem_ext_in        (exmem1_mem_ext),
        .reg_write_in      (exmem1_reg_write),
        .wb_sel_in         (exmem1_wb_sel),
        .csr_we_in         (exmem1_csr_we),
        .csr_op_in         (exmem1_csr_op),
        .csr_imm_sel_in    (exmem1_csr_imm_sel),
        .ecall_in          (exmem1_ecall),
        .ebreak_in         (exmem1_ebreak),
        .mret_in           (exmem1_mret),
        .illegal_instr_in  (exmem1_illegal),
        // ── DMEM interface ──
        .dmem_re           (dmem_re),           // output: DMEM read enable
        .dmem_we           (dmem_we),           // output: DMEM write enable
        .dmem_addr         (dmem_addr),         // output: DMEM word address
        .dmem_wdata        (dmem_wdata),        // output: DMEM write data
        .dmem_size         (dmem_size),         // output: access size
        // ── AXI interface (CPU-side simple request/response) ──
        .axi_req_valid     (axi_req_valid),     // output: new AXI transaction
        .axi_req_addr      (axi_req_addr),      // output: AXI address
        .axi_req_we        (axi_req_we),        // output: 1=write 0=read
        .axi_req_wdata     (axi_req_wdata),     // output: AXI write data
        .axi_req_size      (axi_req_size),      // output: AXI size
        .axi_resp_valid    (axi_resp_valid),    // input:  AXI response ready
        .axi_resp_rdata    (axi_resp_rdata),    // input:  AXI read data
        .axi_resp_err      (axi_resp_err),      // input:  AXI error response
        // ── AHB async FIFO interface ──
        .req_fifo_wr_en    (req_fifo_wr_en),    // output: push to Request FIFO
        .req_fifo_wr_data  (req_fifo_wr_data),  // output: 67-bit request payload
        .resp_fifo_rd_empty(resp_fifo_rd_empty),// input:  Response FIFO has data
        .resp_fifo_rd_en   (resp_fifo_rd_en),   // output: pop from Response FIFO
        .resp_fifo_rd_data (resp_fifo_rd_data), // input:  33-bit response payload
        // ── PLIC interface ──
        .plic_re           (plic_re),           // output: PLIC read enable
        .plic_we           (plic_we),           // output: PLIC write enable
        .plic_addr         (plic_addr),         // output: PLIC register address [23:0]
        .plic_wdata        (plic_wdata),        // output: PLIC write data
        // ── Control / Status ──
        .bus_stall_req     (bus_stall_req),     // output: stall pipeline until bus done
        .load_access_fault (mem1_load_fault),   // output: unmapped load → zicsr exception
        .store_access_fault(mem1_store_fault),  // output: unmapped store → zicsr exception
        // ── Outputs to MEM1/MEM2 register ──
        .pc_out            (mem1_pc),
        .alu_result_out    (mem1_alu_result),
        .rdata_out         (mem1_rdata),        // output: AXI/AHB read data (valid when stall=0)
        .rs1_data_out      (mem1_rs1_data),
        .imm_out           (mem1_imm),
        .rd_addr_out       (mem1_rd_addr),
        .csr_addr_out      (mem1_csr_addr),
        .mem_src_out       (mem1_mem_src),      // output: 00=DMEM 01=AXI 10=AHB 11=PLIC
        .mem_ext_out       (mem1_mem_ext),
        .mem_size_out      (mem1_mem_size),
        .reg_write_out     (mem1_reg_write),
        .wb_sel_out        (mem1_wb_sel),
        .csr_we_out        (mem1_csr_we),
        .csr_op_out        (mem1_csr_op),
        .csr_imm_sel_out   (mem1_csr_imm_sel),
        .ecall_out         (mem1_ecall),
        .ebreak_out        (mem1_ebreak),
        .mret_out          (mem1_mret),
        .illegal_instr_out (mem1_illegal)
    );

    //=========================================================
    // 11. DMEM — Synchronous data memory (1GHz)
    //=========================================================
    dmem #(.SIZE_KB(64)) u_dmem (
        .clk   (clk_cpu),   // input:  1GHz clock
        .re    (dmem_re),   // input:  read enable (from mem1_stage)
        .addr  (dmem_addr), // input:  byte address (word-aligned)
        .rdata (dmem_rdata),// output: read data → mem2_stage (1-cycle latency)
        .we    (dmem_we),   // input:  write enable
        .wdata (dmem_wdata),// input:  write data
        .size  (dmem_size)  // input:  access size (00=byte 01=half 10=word)
    );

    //=========================================================
    // 12. MEM1/MEM2 Pipeline Register
    //=========================================================
    mem1_mem2_reg u_mem1mem2 (
        .clk               (clk_cpu),
        .rst_n             (rst_cpu_n),
        .stall             (stall_mem1mem2),      // input:  freeze (bus stall)
        .flush             (flush_mem1mem2),      // input:  clear (trap)
        // ── Inputs from MEM1 stage ──
        .pc_in             (mem1_pc),
        .alu_result_in     (mem1_alu_result),
        .rdata_in          (mem1_rdata),          // input:  AXI/AHB rdata (valid when not stalling)
        .rs1_data_in       (mem1_rs1_data),
        .imm_in            (mem1_imm),
        .rd_addr_in        (mem1_rd_addr),
        .csr_addr_in       (mem1_csr_addr),
        .mem_src_in        (mem1_mem_src),        // input:  00=DMEM 01=AXI 10=AHB 11=PLIC
        .mem_ext_in        (mem1_mem_ext),
        .mem_size_in       (mem1_mem_size),
        .reg_write_in      (mem1_reg_write),
        .wb_sel_in         (mem1_wb_sel),
        .csr_we_in         (mem1_csr_we),
        .csr_op_in         (mem1_csr_op),
        .csr_imm_sel_in    (mem1_csr_imm_sel),
        .ecall_in          (mem1_ecall),
        .ebreak_in         (mem1_ebreak),
        .mret_in           (mem1_mret),
        .illegal_instr_in  (mem1_illegal),
        .load_fault_in     (mem1_load_fault),
        .store_fault_in    (mem1_store_fault),
        // ── Outputs to MEM2 stage ──
        .pc_out            (mem1mem2_pc),
        .alu_result_out    (mem1mem2_alu_result),
        .rdata_out         (mem1mem2_rdata),
        .rs1_data_out      (mem1mem2_rs1_data),
        .imm_out           (mem1mem2_imm),
        .rd_addr_out       (mem1mem2_rd_addr),    // output: also forwarding gap-2 source
        .csr_addr_out      (mem1mem2_csr_addr),
        .mem_src_out       (mem1mem2_mem_src),
        .mem_ext_out       (mem1mem2_mem_ext),
        .mem_size_out      (mem1mem2_mem_size),
        .reg_write_out     (mem1mem2_reg_write),  // output: also forwarding gap-2 source
        .wb_sel_out        (mem1mem2_wb_sel),     // output: also used by ex_stage fwd mux
        .csr_we_out        (mem1mem2_csr_we),
        .csr_op_out        (mem1mem2_csr_op),
        .csr_imm_sel_out   (mem1mem2_csr_imm_sel),
        .ecall_out         (mem1mem2_ecall),
        .ebreak_out        (mem1mem2_ebreak),
        .mret_out          (mem1mem2_mret),
        .illegal_instr_out (mem1mem2_illegal),
        .load_fault_out    (mem1mem2_load_fault),
        .store_fault_out   (mem1mem2_store_fault)
    );

    //=========================================================
    // 13. MEM2 Stage — Data Source Select + Sign Extension
    //=========================================================
    mem2_stage u_mem2 (
        // ── Inputs from MEM1/MEM2 register ──
        .pc_in             (mem1mem2_pc),
        .alu_result_in     (mem1mem2_alu_result),
        .rdata_in          (mem1mem2_rdata),      // input:  AXI/AHB rdata captured at MEM1
        .rs1_data_in       (mem1mem2_rs1_data),
        .imm_in            (mem1mem2_imm),
        .rd_addr_in        (mem1mem2_rd_addr),
        .csr_addr_in       (mem1mem2_csr_addr),
        .mem_src_in        (mem1mem2_mem_src),    // input:  selects which rdata to use
        .mem_ext_in        (mem1mem2_mem_ext),
        .mem_size_in       (mem1mem2_mem_size),
        .reg_write_in      (mem1mem2_reg_write),
        .wb_sel_in         (mem1mem2_wb_sel),
        .csr_we_in         (mem1mem2_csr_we),
        .csr_op_in         (mem1mem2_csr_op),
        .csr_imm_sel_in    (mem1mem2_csr_imm_sel),
        .ecall_in          (mem1mem2_ecall),
        .ebreak_in         (mem1mem2_ebreak),
        .mret_in           (mem1mem2_mret),
        .illegal_instr_in  (mem1mem2_illegal),
        .load_fault_in     (mem1mem2_load_fault),
        .store_fault_in    (mem1mem2_store_fault),
        .dmem_rdata        (dmem_rdata),          // input:  DMEM read data (1-cycle from DMEM)
        .plic_rdata        (plic_rdata),          // input:  PLIC read data (1-cycle from PLIC)
        // ── Outputs to MEM2/WB register ──
        .pc_out            (mem2_pc),
        .alu_result_out    (mem2_alu_result),     // output: also forwarding gap-2 source
        .mem_rdata_out     (mem2_mem_rdata),      // output: sign-ext load data, forwarding gap-2
        .rs1_data_out      (mem2_rs1_data),
        .imm_out           (mem2_imm),
        .rd_addr_out       (mem2_rd_addr),
        .csr_addr_out      (mem2_csr_addr),
        .reg_write_out     (mem2_reg_write),
        .wb_sel_out        (mem2_wb_sel),
        .csr_we_out        (mem2_csr_we),
        .csr_op_out        (mem2_csr_op),
        .csr_imm_sel_out   (mem2_csr_imm_sel),
        .ecall_out         (mem2_ecall),
        .ebreak_out        (mem2_ebreak),
        .mret_out          (mem2_mret),
        .illegal_instr_out (mem2_illegal),
        .load_fault_out    (mem2_load_fault),
        .store_fault_out   (mem2_store_fault)
    );

    //=========================================================
    // 14. MEM2/WB Pipeline Register
    //=========================================================
    mem2_wb_reg u_mem2wb (
        .clk               (clk_cpu),
        .rst_n             (rst_cpu_n),
        .stall             (stall_mem2wb),        // input:  freeze (bus stall; rare at this stage)
        .flush             (flush_mem2wb),        // input:  clear (trap)
        // ── Inputs from MEM2 stage ──
        .pc_in             (mem2_pc),
        .alu_result_in     (mem2_alu_result),
        .mem_rdata_in      (mem2_mem_rdata),
        .rs1_data_in       (mem2_rs1_data),
        .imm_in            (mem2_imm),
        .rd_addr_in        (mem2_rd_addr),
        .csr_addr_in       (mem2_csr_addr),
        .reg_write_in      (mem2_reg_write),
        .wb_sel_in         (mem2_wb_sel),
        .csr_we_in         (mem2_csr_we),
        .csr_op_in         (mem2_csr_op),
        .csr_imm_sel_in    (mem2_csr_imm_sel),
        .ecall_in          (mem2_ecall),
        .ebreak_in         (mem2_ebreak),
        .mret_in           (mem2_mret),
        .illegal_instr_in  (mem2_illegal),
        .load_fault_in     (mem2_load_fault),
        .store_fault_in    (mem2_store_fault),
        // ── Outputs to WB stage + Zicsr ──
        .pc_out            (wb_pc),               // output: PC of retiring instruction
        .alu_result_out    (wb_alu_result),
        .mem_rdata_out     (wb_mem_rdata),
        .rs1_data_out      (wb_rs1_data),         // output: CSR write source → zicsr
        .imm_out           (wb_imm),              // output: zimm → zicsr
        .rd_addr_out       (wb_rd_addr),          // output: forwarding gap-3 source
        .csr_addr_out      (wb_csr_addr),
        .reg_write_out     (wb_reg_write),        // output: forwarding gap-3 enable
        .wb_sel_out        (wb_sel),
        .csr_we_out        (wb_csr_we),
        .csr_op_out        (wb_csr_op),
        .csr_imm_sel_out   (wb_csr_imm_sel),
        .ecall_out         (wb_ecall),
        .ebreak_out        (wb_ebreak),
        .mret_out          (wb_mret),
        .illegal_instr_out (wb_illegal),
        .load_fault_out    (wb_load_fault),
        .store_fault_out   (wb_store_fault)
    );

    //=========================================================
    // 15. WB Stage — Result MUX → Register File Write
    //=========================================================
    wb_stage u_wb (
        // ── Inputs from MEM2/WB register ──
        .pc_in        (wb_pc),          // input:  PC of retiring instruction (for PC+4 / JAL)
        .alu_result_in(wb_alu_result),  // input:  ALU result
        .mem_rdata_in (wb_mem_rdata),   // input:  load data (sign-extended)
        .rd_addr_in   (wb_rd_addr),     // input:  destination register
        .reg_write_in (wb_reg_write),   // input:  write enable
        .wb_sel_in    (wb_sel),         // input:  00=ALU 01=MEM 10=PC+4 11=CSR
        .csr_rdata_in (csr_rdata),      // input:  CSR read value (from zicsr)
        // ── Outputs to register file + forwarding ──
        .rf_rd_addr   (rf_wr_addr),     // output: write address → register_file
        .rf_we        (rf_wr_we),       // output: write enable  → register_file
        .rf_wr_data   (rf_wr_data)      // output: write data    → register_file + WB forwarding
    );

    //=========================================================
    // 16. Zicsr — CSR Register File + Trap Controller
    //=========================================================
    zicsr u_zicsr (
        .clk              (clk_cpu),          // input:  1GHz clock
        .rst_n            (rst_cpu_n),        // input:  CPU domain reset
        // ── Inputs from WB stage (instruction commits here) ──
        .wb_pc            (wb_pc),            // input:  PC of committing instruction
        .wb_rs1_data      (wb_rs1_data),      // input:  CSR write source (rs1, forwarded)
        .wb_imm           (wb_imm),           // input:  zimm for CSR-immediate instructions
        .wb_csr_addr      (wb_csr_addr),      // input:  CSR register address
        .wb_csr_we        (wb_csr_we),        // input:  CSR write enable
        .wb_csr_op        (wb_csr_op),        // input:  01=RW 10=RS 11=RC
        .wb_csr_imm_sel   (wb_csr_imm_sel),  // input:  0=rs1 1=zimm
        .wb_ecall         (wb_ecall),         // input:  ECALL at WB → environment call exception
        .wb_ebreak        (wb_ebreak),        // input:  EBREAK at WB → breakpoint exception
        .wb_mret          (wb_mret),          // input:  MRET at WB  → return from trap
        .wb_illegal_instr (wb_illegal),       // input:  illegal instruction exception
        .wb_load_fault    (wb_load_fault),    // input:  load access fault from MEM1
        .wb_store_fault   (wb_store_fault),   // input:  store access fault from MEM1
        // ── External interrupt source ──
        .meip_in          (plic_meip),        // input:  MEIP from PLIC (all sources arbitrated)
        // ── Bus stall interlock ──
        .bus_stall_req    (bus_stall_req),    // input:  suppress trap until bus transaction ends
        // ── Outputs ──
        .csr_rdata        (csr_rdata),        // output: CSR read data → wb_stage
        .zicsr_flush      (zicsr_flush),      // output: flush all pipeline stages (trap/mret)
        .zicsr_pc         (zicsr_pc)          // output: new PC (trap vector or mepc) → if1_stage
    );

    //=========================================================
    // 17. AHB IRQ CDC — 3× 2-FF Synchronizers (500MHz → 1GHz)
    //
    // Each AHB IRQ source gets its own synchronizer to prevent the glitch that
    // would occur if sources were OR'd before crossing the clock domain boundary.
    // AXI IRQs are already in the 1GHz domain and connect directly to PLIC.
    //=========================================================
    irq_sync2ff u_ahb_irq0_sync (
        .clk  (clk_cpu),       // input:  destination clock (1GHz)
        .rst_n(rst_cpu_n),     // input:  destination-domain reset
        .d    (ahb_S0_irq_i),  // input:  AHB slave 0 IRQ (500MHz domain)
        .q    (ahb_irq0_sync)  // output: synchronized IRQ → PLIC source 4
    );

    irq_sync2ff u_ahb_irq1_sync (
        .clk  (clk_cpu),
        .rst_n(rst_cpu_n),
        .d    (ahb_S1_irq_i),  // input:  AHB slave 1 IRQ (500MHz domain)
        .q    (ahb_irq1_sync)  // output: synchronized IRQ → PLIC source 5
    );

    irq_sync2ff u_ahb_irq2_sync (
        .clk  (clk_cpu),
        .rst_n(rst_cpu_n),
        .d    (ahb_S2_irq_i),  // input:  AHB slave 2 IRQ (500MHz domain)
        .q    (ahb_irq2_sync)  // output: synchronized IRQ → PLIC source 6
    );

    //=========================================================
    // 18. PLIC — Platform-Level Interrupt Controller
    //
    // Source mapping (irq_src[5:0]):
    //   [0] = axi_S0_irq  (1GHz, direct)          → priority register 1
    //   [1] = axi_S1_irq  (1GHz, direct)          → priority register 2
    //   [2] = axi_S2_irq  (1GHz, direct)          → priority register 3
    //   [3] = ahb_S0_irq  (synchronized to 1GHz)  → priority register 4
    //   [4] = ahb_S1_irq  (synchronized to 1GHz)  → priority register 5
    //   [5] = ahb_S2_irq  (synchronized to 1GHz)  → priority register 6
    //=========================================================
    plic u_plic (
        .clk     (clk_cpu),                    // input:  1GHz clock
        .rst_n   (rst_cpu_n),                  // input:  CPU domain reset
        .irq_src ({ahb_irq2_sync,              // input [5]: AHB slave 2 (synced)
                   ahb_irq1_sync,              // input [4]: AHB slave 1 (synced)
                   ahb_irq0_sync,              // input [3]: AHB slave 0 (synced)
                   axi_S2_irq,                 // input [2]: AXI slave 2 (direct 1GHz)
                   axi_S1_irq,                 // input [1]: AXI slave 1 (direct 1GHz)
                   axi_S0_irq}),               // input [0]: AXI slave 0 (direct 1GHz)
        .re      (plic_re),                    // input:  read enable (from mem1_stage)
        .we      (plic_we),                    // input:  write enable (from mem1_stage)
        .addr    (plic_addr),                  // input:  register address [23:0]
        .wdata   (plic_wdata),                 // input:  write data
        .rdata   (plic_rdata),                 // output: read data → mem2_stage (1-cycle latency)
        .meip    (plic_meip)                   // output: highest-priority IRQ pending → zicsr
    );

    //=========================================================
    // 20. Hazard Unit — Stall / Flush generation
    //=========================================================
    hazard_unit u_haz (
        // ── Bus stall ──
        .bus_stall_req  (bus_stall_req),     // input:  AXI/AHB transaction in progress
        // ── Load-use hazard detection ──
        .ex_mem_read    (idex_mem_read),     // input:  load instruction at EX
        .ex_rd_addr     (idex_rd_addr),      // input:  load destination register
        .ex_wb_sel      (idex_wb_sel),       // input:  confirms mem-result writeback
        .ex_reg_write   (idex_reg_write),
        // ── CSR-use hazard detection ──
        .mem1_wb_sel    (exmem1_wb_sel),     // input:  CSR instruction at MEM1
        .mem1_rd_addr   (exmem1_rd_addr),
        .mem1_reg_write (exmem1_reg_write),
        .mem2_wb_sel    (mem1mem2_wb_sel),   // input:  CSR instruction at MEM2
        .mem2_rd_addr   (mem1mem2_rd_addr),
        .mem2_reg_write (mem1mem2_reg_write),
        // ── Source register addresses at ID (for hazard check) ──
        .id_rs1_addr    (id_rs1_addr),       // input:  rs1 of instruction at ID
        .id_rs2_addr    (id_rs2_addr),       // input:  rs2 of instruction at ID
        // ── Branch predictor mismatch ──
        .bp_mismatch    (bp_mismatch),       // input:  predicted outcome ≠ actual outcome at EX
        // ── Zicsr trap/mret redirect ──
        .zicsr_flush    (zicsr_flush),       // input:  trap or mret fired
        // ── Stall outputs (per pipeline register) ──
        .stall_if1_if2  (stall_if1if2),     // output: freeze IF1/IF2 register
        .stall_if2_id   (stall_if2id),      // output: freeze IF2/ID register
        .stall_id_ex    (stall_idex),       // output: freeze ID/EX register
        .stall_ex_mem1  (stall_exmem1),     // output: freeze EX/MEM1 register
        .stall_mem1_mem2(stall_mem1mem2),   // output: freeze MEM1/MEM2 register
        .stall_mem2_wb  (stall_mem2wb),     // output: freeze MEM2/WB register
        .stall_pc       (stall_pc),         // output: freeze PC register in if1_stage
        // ── Flush outputs (per pipeline register) ──
        .flush_if1_if2  (flush_if1if2),    // output: clear IF1/IF2 to bubble
        .flush_if2_id   (flush_if2id),     // output: clear IF2/ID to bubble
        .flush_id_ex    (flush_idex),      // output: clear ID/EX to NOP (load-use / CSR-use)
        .flush_ex_mem1  (flush_exmem1),    // output: clear EX/MEM1 to NOP (trap)
        .flush_mem1_mem2(flush_mem1mem2),  // output: clear MEM1/MEM2 to NOP (trap)
        .flush_mem2_wb  (flush_mem2wb),    // output: clear MEM2/WB to NOP (trap)
        .flush_pc       (flush_pc)         // output: redirect PC (subsumed by flush_if1if2)
    );

    //=========================================================
    // 21. AXI Group (1GHz domain)
    //     axi_interface: simple req/resp CPU side ↔ full AXI-Lite bus
    //     axi_interconnect: 1-master 3-slave address router + IRQ OR
    //=========================================================

    // AXI master ↔ interconnect internal buses
    logic [31:0] axi_M_AWADDR; logic [2:0] axi_M_AWPROT; logic axi_M_AWVALID, axi_M_AWREADY;
    logic [31:0] axi_M_WDATA;  logic [3:0] axi_M_WSTRB;  logic axi_M_WVALID,  axi_M_WREADY;
    logic [1:0]  axi_M_BRESP;  logic axi_M_BVALID, axi_M_BREADY;
    logic [31:0] axi_M_ARADDR; logic [2:0] axi_M_ARPROT; logic axi_M_ARVALID, axi_M_ARREADY;
    logic [31:0] axi_M_RDATA;  logic [1:0] axi_M_RRESP;  logic axi_M_RVALID,  axi_M_RREADY;

    // OR'd AXI IRQ (kept for interconnect port; individual IRQs feed PLIC directly)
    logic axi_irq_or;

    axi_interface u_axi_if (
        .clk           (clk_cpu),          // input:  1GHz clock
        .rst_n         (rst_cpu_n),        // input:  CPU domain reset
        // ── CPU-side request/response (from mem1_stage) ──
        .axi_req_valid (axi_req_valid),    // input:  start a transaction
        .axi_req_addr  (axi_req_addr),     // input:  transaction address
        .axi_req_we    (axi_req_we),       // input:  1=write 0=read
        .axi_req_wdata (axi_req_wdata),    // input:  write data
        .axi_req_size  (axi_req_size),     // input:  access size
        .axi_resp_valid(axi_resp_valid),   // output: response ready → mem1_stage
        .axi_resp_rdata(axi_resp_rdata),   // output: read data      → mem1_stage
        .axi_resp_err  (axi_resp_err),     // output: BRESP/RRESP error
        // ── AXI-Lite master bus (to interconnect) ──
        .AWADDR (axi_M_AWADDR), .AWPROT(axi_M_AWPROT), .AWVALID(axi_M_AWVALID), .AWREADY(axi_M_AWREADY),
        .WDATA  (axi_M_WDATA),  .WSTRB (axi_M_WSTRB),  .WVALID (axi_M_WVALID),  .WREADY (axi_M_WREADY),
        .BRESP  (axi_M_BRESP),  .BVALID(axi_M_BVALID), .BREADY (axi_M_BREADY),
        .ARADDR (axi_M_ARADDR), .ARPROT(axi_M_ARPROT), .ARVALID(axi_M_ARVALID), .ARREADY(axi_M_ARREADY),
        .RDATA  (axi_M_RDATA),  .RRESP (axi_M_RRESP),  .RVALID (axi_M_RVALID),  .RREADY (axi_M_RREADY)
    );

    axi_interconnect u_axi_xbar (
        .clk(clk_cpu), .rst_n(rst_cpu_n),
        // ── Master port (from axi_interface) ──
        .M_AWADDR(axi_M_AWADDR), .M_AWPROT(axi_M_AWPROT), .M_AWVALID(axi_M_AWVALID), .M_AWREADY(axi_M_AWREADY),
        .M_WDATA (axi_M_WDATA),  .M_WSTRB (axi_M_WSTRB),  .M_WVALID (axi_M_WVALID),  .M_WREADY (axi_M_WREADY),
        .M_BRESP (axi_M_BRESP),  .M_BVALID(axi_M_BVALID), .M_BREADY (axi_M_BREADY),
        .M_ARADDR(axi_M_ARADDR), .M_ARPROT(axi_M_ARPROT), .M_ARVALID(axi_M_ARVALID), .M_ARREADY(axi_M_ARREADY),
        .M_RDATA (axi_M_RDATA),  .M_RRESP (axi_M_RRESP),  .M_RVALID (axi_M_RVALID),  .M_RREADY (axi_M_RREADY),
        // ── Slave 0 port (routed to chip boundary) ──
        .S0_AWADDR(axi_S0_AWADDR),.S0_AWPROT(axi_S0_AWPROT),.S0_AWVALID(axi_S0_AWVALID),.S0_AWREADY(axi_S0_AWREADY),
        .S0_WDATA (axi_S0_WDATA), .S0_WSTRB (axi_S0_WSTRB), .S0_WVALID (axi_S0_WVALID), .S0_WREADY (axi_S0_WREADY),
        .S0_BRESP (axi_S0_BRESP), .S0_BVALID(axi_S0_BVALID),.S0_BREADY (axi_S0_BREADY),
        .S0_ARADDR(axi_S0_ARADDR),.S0_ARPROT(axi_S0_ARPROT),.S0_ARVALID(axi_S0_ARVALID),.S0_ARREADY(axi_S0_ARREADY),
        .S0_RDATA (axi_S0_RDATA), .S0_RRESP (axi_S0_RRESP), .S0_RVALID (axi_S0_RVALID), .S0_RREADY (axi_S0_RREADY),
        .irq0(axi_S0_irq),
        // ── Slave 1 port ──
        .S1_AWADDR(axi_S1_AWADDR),.S1_AWPROT(axi_S1_AWPROT),.S1_AWVALID(axi_S1_AWVALID),.S1_AWREADY(axi_S1_AWREADY),
        .S1_WDATA (axi_S1_WDATA), .S1_WSTRB (axi_S1_WSTRB), .S1_WVALID (axi_S1_WVALID), .S1_WREADY (axi_S1_WREADY),
        .S1_BRESP (axi_S1_BRESP), .S1_BVALID(axi_S1_BVALID),.S1_BREADY (axi_S1_BREADY),
        .S1_ARADDR(axi_S1_ARADDR),.S1_ARPROT(axi_S1_ARPROT),.S1_ARVALID(axi_S1_ARVALID),.S1_ARREADY(axi_S1_ARREADY),
        .S1_RDATA (axi_S1_RDATA), .S1_RRESP (axi_S1_RRESP), .S1_RVALID (axi_S1_RVALID), .S1_RREADY (axi_S1_RREADY),
        .irq1(axi_S1_irq),
        // ── Slave 2 port ──
        .S2_AWADDR(axi_S2_AWADDR),.S2_AWPROT(axi_S2_AWPROT),.S2_AWVALID(axi_S2_AWVALID),.S2_AWREADY(axi_S2_AWREADY),
        .S2_WDATA (axi_S2_WDATA), .S2_WSTRB (axi_S2_WSTRB), .S2_WVALID (axi_S2_WVALID), .S2_WREADY (axi_S2_WREADY),
        .S2_BRESP (axi_S2_BRESP), .S2_BVALID(axi_S2_BVALID),.S2_BREADY (axi_S2_BREADY),
        .S2_ARADDR(axi_S2_ARADDR),.S2_ARPROT(axi_S2_ARPROT),.S2_ARVALID(axi_S2_ARVALID),.S2_ARREADY(axi_S2_ARREADY),
        .S2_RDATA (axi_S2_RDATA), .S2_RRESP (axi_S2_RRESP), .S2_RVALID (axi_S2_RVALID), .S2_RREADY (axi_S2_RREADY),
        .irq2(axi_S2_irq),
        .axi_irq(axi_irq_or)    // output: OR of all slave IRQs (unused; each src feeds PLIC directly)
    );

    //=========================================================
    // 22. AHB Group — CDC FIFOs + Interface + Interconnect
    //     Request FIFO : CPU (1GHz write) → AHB (500MHz read), 67-bit wide
    //     Response FIFO: AHB (500MHz write) → CPU (1GHz read), 33-bit wide
    //=========================================================

    // Request FIFO: 1GHz write side (from mem1_stage) → 500MHz read side (to ahb_interface)
    logic        req_fifo_rd_en;
    logic [66:0] req_fifo_rd_data;
    logic        req_fifo_rd_empty;

    async_fifo_depth2 #(.DATA_WIDTH(67)) u_req_fifo (
        .wr_clk  (clk_cpu),          // input:  write clock (1GHz, CPU domain)
        .wr_rst_n(rst_cpu_n),        // input:  write-side reset
        .wr_en   (req_fifo_wr_en),   // input:  push (from mem1_stage)
        .wr_data (req_fifo_wr_data), // input:  67-bit payload: addr+wdata+ctrl
        .rd_clk  (clk_ahb),          // input:  read clock (500MHz, AHB domain)
        .rd_rst_n(rst_ahb_n),        // input:  read-side reset
        .rd_en   (req_fifo_rd_en),   // input:  pop (from ahb_interface)
        .rd_data (req_fifo_rd_data), // output: request payload → ahb_interface
        .rd_empty(req_fifo_rd_empty) // output: no pending request
    );

    // Response FIFO: 500MHz write side (from ahb_interface) → 1GHz read side (to mem1_stage)
    logic        resp_fifo_wr_en;
    logic [32:0] resp_fifo_wr_data;

    async_fifo_depth2 #(.DATA_WIDTH(33)) u_resp_fifo (
        .wr_clk  (clk_ahb),           // input:  write clock (500MHz, AHB domain)
        .wr_rst_n(rst_ahb_n),         // input:  write-side reset
        .wr_en   (resp_fifo_wr_en),   // input:  push (from ahb_interface)
        .wr_data (resp_fifo_wr_data), // input:  33-bit payload: HRESP + rdata
        .rd_clk  (clk_cpu),           // input:  read clock (1GHz, CPU domain)
        .rd_rst_n(rst_cpu_n),         // input:  read-side reset
        .rd_en   (resp_fifo_rd_en),   // input:  pop (from mem1_stage)
        .rd_data (resp_fifo_rd_data), // output: response payload → mem1_stage
        .rd_empty(resp_fifo_rd_empty) // output: no response ready → mem1_stage (keep stall)
    );

    // AHB master ↔ interconnect internal buses
    logic [31:0] ahb_HADDR;  logic [2:0] ahb_HSIZE;  logic [1:0] ahb_HTRANS;
    logic        ahb_HWRITE; logic [31:0] ahb_HWDATA;
    logic        ahb_HREADY; logic [31:0] ahb_HRDATA; logic ahb_HRESP;

    ahb_interface u_ahb_if (
        .clk_ahb    (clk_ahb),           // input:  500MHz AHB clock
        .rst_ahb_n  (rst_ahb_n),         // input:  AHB domain reset
        // ── Request FIFO interface (pop side) ──
        .req_empty  (req_fifo_rd_empty), // input:  no pending request
        .req_rd_en  (req_fifo_rd_en),    // output: pop one request
        .req_rd_data(req_fifo_rd_data),  // input:  67-bit request payload
        // ── Response FIFO interface (push side) ──
        .resp_wr_en  (resp_fifo_wr_en),  // output: push response
        .resp_wr_data(resp_fifo_wr_data),// output: 33-bit response payload
        // ── AHB master bus (to interconnect) ──
        .HADDR  (ahb_HADDR),   // output: address phase address
        .HSIZE  (ahb_HSIZE),   // output: transfer size
        .HTRANS (ahb_HTRANS),  // output: transfer type (IDLE/NONSEQ)
        .HWRITE (ahb_HWRITE),  // output: 1=write 0=read
        .HWDATA (ahb_HWDATA),  // output: write data (data phase)
        .HREADY (ahb_HREADY),  // input:  slave ready
        .HRDATA (ahb_HRDATA),  // input:  read data from interconnect mux
        .HRESP  (ahb_HRESP)   // input:  slave error response
    );

    // Interconnect ↔ Slave signal bundles
    logic        ahb_HSEL0, ahb_HREADY0_in, ahb_HREADYOUT0, ahb_HRESP0; logic [31:0] ahb_HRDATA0; logic ahb_irq0;
    logic        ahb_HSEL1, ahb_HREADY1_in, ahb_HREADYOUT1, ahb_HRESP1; logic [31:0] ahb_HRDATA1; logic ahb_irq1;
    logic        ahb_HSEL2, ahb_HREADY2_in, ahb_HREADYOUT2, ahb_HRESP2; logic [31:0] ahb_HRDATA2; logic ahb_irq2;
    logic        ahb_irq_or; // OR of all AHB slave IRQs (unused; each feeds irq_sync2ff directly)

    ahb_interconnect u_ahb_xbar (
        .clk_ahb    (clk_ahb),    // input:  500MHz clock
        .rst_ahb_n  (rst_ahb_n),  // input:  AHB domain reset
        // ── Master bus (from ahb_interface) ──
        .HADDR  (ahb_HADDR),   // input:  address
        .HSIZE  (ahb_HSIZE),   // input:  size
        .HTRANS (ahb_HTRANS),  // input:  transfer type
        .HWRITE (ahb_HWRITE),  // input:  write enable
        .HWDATA (ahb_HWDATA),  // input:  write data
        .HREADY (ahb_HREADY),  // output: global HREADY (mux of all slave HREADYOUT)
        .HRDATA (ahb_HRDATA),  // output: mux of slave HRDATA
        .HRESP  (ahb_HRESP),   // output: mux of slave HRESP
        // ── Slave 0 ──
        .HSEL0      (ahb_HSEL0),       .HREADY0_in (ahb_HREADY0_in),  // output: select + HREADY to S0
        .HREADYOUT0 (ahb_HREADYOUT0),  .HRDATA0    (ahb_HRDATA0),     // input:  S0 response
        .HRESP0     (ahb_HRESP0),      .irq0       (ahb_irq0),        // input:  S0 IRQ
        // ── Slave 1 ──
        .HSEL1      (ahb_HSEL1),       .HREADY1_in (ahb_HREADY1_in),
        .HREADYOUT1 (ahb_HREADYOUT1),  .HRDATA1    (ahb_HRDATA1),
        .HRESP1     (ahb_HRESP1),      .irq1       (ahb_irq1),
        // ── Slave 2 ──
        .HSEL2      (ahb_HSEL2),       .HREADY2_in (ahb_HREADY2_in),
        .HREADYOUT2 (ahb_HREADYOUT2),  .HRDATA2    (ahb_HRDATA2),
        .HRESP2     (ahb_HRESP2),      .irq2       (ahb_irq2),
        .ahb_irq    (ahb_irq_or)       // output: OR of slave IRQs (unused)
    );

    //=========================================================
    // 23. External Peripheral Interface — chip boundary routing
    //     Wire internal signals to module ports so external
    //     peripherals can connect without opening this file.
    //=========================================================

    // Synchronized resets for external peripheral FFs
    assign rst_cpu_n_o = rst_cpu_n;
    assign rst_ahb_n_o = rst_ahb_n;

    // AHB shared bus broadcast to all external AHB slaves
    assign ahb_HADDR_o  = ahb_HADDR;
    assign ahb_HSIZE_o  = ahb_HSIZE;
    assign ahb_HTRANS_o = ahb_HTRANS;
    assign ahb_HWRITE_o = ahb_HWRITE;
    assign ahb_HWDATA_o = ahb_HWDATA;

    // AHB Slave 0 — select, ready, and response routing
    assign ahb_S0_HSEL_o    = ahb_HSEL0;
    assign ahb_S0_HREADY_o  = ahb_HREADY0_in;
    assign ahb_HREADYOUT0   = ahb_S0_HREADYOUT_i;
    assign ahb_HRDATA0      = ahb_S0_HRDATA_i;
    assign ahb_HRESP0       = ahb_S0_HRESP_i;
    assign ahb_irq0         = ahb_S0_irq_i;   // → irq_sync2ff u_ahb_irq0_sync

    // AHB Slave 1
    assign ahb_S1_HSEL_o    = ahb_HSEL1;
    assign ahb_S1_HREADY_o  = ahb_HREADY1_in;
    assign ahb_HREADYOUT1   = ahb_S1_HREADYOUT_i;
    assign ahb_HRDATA1      = ahb_S1_HRDATA_i;
    assign ahb_HRESP1       = ahb_S1_HRESP_i;
    assign ahb_irq1         = ahb_S1_irq_i;   // → irq_sync2ff u_ahb_irq1_sync

    // AHB Slave 2
    assign ahb_S2_HSEL_o    = ahb_HSEL2;
    assign ahb_S2_HREADY_o  = ahb_HREADY2_in;
    assign ahb_HREADYOUT2   = ahb_S2_HREADYOUT_i;
    assign ahb_HRDATA2      = ahb_S2_HRDATA_i;
    assign ahb_HRESP2       = ahb_S2_HRESP_i;
    assign ahb_irq2         = ahb_S2_irq_i;   // → irq_sync2ff u_ahb_irq2_sync

endmodule
