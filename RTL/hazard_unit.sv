// Hazard Unit: Phát hiện hazard và tạo tín hiệu stall/flush cho toàn pipeline
//
// Pipeline: IF1 → IF2 → ID → EX → MEM1 → MEM2 → WB
// Registers: IF1/IF2, IF2/ID, ID/EX, EX/MEM1, MEM1/MEM2, MEM2/WB
//
// Các loại hazard:
//   1. Load-Use hazard: lệnh Load ở EX, lệnh kế cần kết quả → stall 1 chu kỳ
//   2. CSR-Use hazard: lệnh CSR (wb_sel==11) ở EX/MEM1/MEM2 (kết quả csr_old chỉ
//                      sẵn ở WB) → stall 3/2/1 chu kỳ, giải phóng khi CSR vào WB
//   3. Bus stall: AXI/AHB transaction chưa xong → stall toàn pipeline
//   4. Branch/Jump flush: nhánh được lấy hoặc jump → flush IF1/IF2 và IF2/ID
//   5. Zicsr flush: exception/interrupt → flush toàn pipeline từ IF1 đến MEM2/WB
//
// Stall logic:
//   - bus_stall_req stall toàn pipeline (mọi stage)
//   - load_use_stall stall IF1..ID (chèn bubble vào EX)
//   - csr_use_stall: tương tự — stall IF1..ID khi CSR ở EX, MEM1, hoặc MEM2
//     (CSR ở EX → stall 1 chu kỳ trước khi lệnh kế vào EX với forwarding sai)
//
// Flush logic (ưu tiên cao hơn stall):
//   - branch/jump flush: IF1/IF2 và IF2/ID
//   - load_use/csr_use: flush ID/EX (bubble) — bị suppress khi bus_stall_req=1
//     (load/CSR đang ở EX không được cancel; bubble sẽ fire khi bus_stall thoả)
//   - zicsr_flush: toàn bộ pipeline

module hazard_unit (
    //----------------- BUS STALL (từ MEM1 stage) -----------------
    input  logic       bus_stall_req,

    //----------------- LOAD-USE HAZARD DETECTION -----------------
    // Từ ID/EX register (lệnh đang ở EX)
    input  logic       ex_mem_read,     // 1 nếu là lệnh Load
    input  logic [4:0] ex_rd_addr,      // rd của lệnh Load tại EX

    //----------------- CSR-USE HAZARD DETECTION -----------------
    // CSR rd value (old CSR) chỉ sẵn ở WB qua csr_rdata/wb_stage.
    // Phải stall khi CSR ở EX (→ stall id), MEM1 (→ stall id), MEM2 (→ stall id).
    input  logic [1:0] ex_wb_sel,       // wb_sel của lệnh tại EX (idex_wb_sel)
    input  logic       ex_reg_write,    // reg_write của lệnh tại EX
    input  logic [1:0] mem1_wb_sel,     // wb_sel của lệnh tại MEM1 (exmem1_wb_sel)
    input  logic [4:0] mem1_rd_addr,    // rd  của lệnh tại MEM1
    input  logic       mem1_reg_write,  // reg_write của lệnh tại MEM1
    input  logic [1:0] mem2_wb_sel,     // wb_sel của lệnh tại MEM2 (mem1mem2_wb_sel)
    input  logic [4:0] mem2_rd_addr,    // rd  của lệnh tại MEM2
    input  logic       mem2_reg_write,  // reg_write của lệnh tại MEM2

    // Từ IF2/ID register (lệnh đang ở ID)
    input  logic [4:0] id_rs1_addr,
    input  logic [4:0] id_rs2_addr,

    //----------------- BRANCH/JUMP (từ EX stage) -----------------
    input  logic       branch_taken,
    input  logic       jump,

    //----------------- ZICSR FLUSH -----------------
    input  logic       zicsr_flush,

    //----------------- STALL SIGNALS -----------------
    output logic       stall_if1_if2,
    output logic       stall_if2_id,
    output logic       stall_id_ex,
    output logic       stall_ex_mem1,
    output logic       stall_mem1_mem2,
    output logic       stall_mem2_wb,

    //----------------- FLUSH SIGNALS -----------------
    output logic       flush_if1_if2,
    output logic       flush_if2_id,
    output logic       flush_id_ex,
    output logic       flush_ex_mem1,
    output logic       flush_mem1_mem2,
    output logic       flush_mem2_wb,

    output logic       stall_pc,
    output logic       flush_pc
);

    // Load-use
    logic load_use_stall;
    assign load_use_stall = ex_mem_read &&
                            (ex_rd_addr != 5'd0) &&
                            ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr));

    // CSR-use: stall when CSR instruction is in EX, MEM1, or MEM2 and the
    // instruction in ID reads its rd.  wb_sel==2'b11 identifies CSR instructions.
    // We must intercept at EX stage (before the dependent enters EX with wrong
    // MEM1 forwarding data); subsequent cycles hold it in ID while CSR advances.
    logic csr_stall_ex, csr_stall_mem1, csr_stall_mem2, csr_use_stall;
    assign csr_stall_ex  = (ex_wb_sel  == 2'b11) && ex_reg_write &&
                           (ex_rd_addr != 5'd0) &&
                           ((ex_rd_addr  == id_rs1_addr) || (ex_rd_addr  == id_rs2_addr));
    assign csr_stall_mem1 = (mem1_wb_sel == 2'b11) && mem1_reg_write &&
                            (mem1_rd_addr != 5'd0) &&
                            ((mem1_rd_addr == id_rs1_addr) || (mem1_rd_addr == id_rs2_addr));
    assign csr_stall_mem2 = (mem2_wb_sel == 2'b11) && mem2_reg_write &&
                            (mem2_rd_addr != 5'd0) &&
                            ((mem2_rd_addr == id_rs1_addr) || (mem2_rd_addr == id_rs2_addr));
    assign csr_use_stall  = csr_stall_ex | csr_stall_mem1 | csr_stall_mem2;

    // Branch/jump flush
    logic ctrl_flush;
    assign ctrl_flush = branch_taken | jump;

    // Combined fetch stall (load-use or csr-use)
    logic fetch_stall;
    assign fetch_stall = load_use_stall | csr_use_stall;

    //=========================================================
    // Stall signals
    //=========================================================
    assign stall_pc        = bus_stall_req | fetch_stall;
    assign stall_if1_if2   = bus_stall_req | fetch_stall;
    assign stall_if2_id    = bus_stall_req | fetch_stall;
    assign stall_id_ex     = bus_stall_req;
    assign stall_ex_mem1   = bus_stall_req;
    assign stall_mem1_mem2 = bus_stall_req;
    assign stall_mem2_wb   = bus_stall_req;

    //=========================================================
    // Flush signals
    //=========================================================
    assign flush_pc        = zicsr_flush;
    assign flush_if1_if2   = zicsr_flush | ctrl_flush;
    assign flush_if2_id    = zicsr_flush | ctrl_flush;
    assign flush_id_ex     = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush;
    assign flush_ex_mem1   = zicsr_flush;
    assign flush_mem1_mem2 = zicsr_flush;
    assign flush_mem2_wb   = zicsr_flush;

endmodule
