// Zicsr Module: CSR Register File + Exception/Interrupt Controller
//
// CSR registers (M-mode only):
//   mstatus (0x300): MIE[3], MPIE[7], MPP[12:11] (always 11)
//   mie     (0x304): MSIE[3], MTIE[7], MEIE[11]
//   mtvec   (0x305): BASE[31:2], MODE[1:0] (0=Direct, 1=Vectored)
//   mepc    (0x341): Exception PC (IALIGN: bits [1:0] always 0 for RV32)
//   mcause  (0x342): Interrupt[31], Cause[30:0]
//   mip     (0x344): MSIP[3](rw), MTIP[7](ro=hw-driven), MEIP[11](ro=hw-driven)
//
// Exception handling (at WB stage, precise):
//   mepc   = wb_pc
//   mcause = exception code
//   mstatus: MPIE=MIE, MIE=0, MPP=11
//   PC     = mtvec base (exceptions always use base, even in vectored mode)
//
// Interrupt handling:
//   mepc   = wb_pc (instruction that would have executed next)
//   mcause = {1'b1, cause_code}
//   mstatus: MPIE=MIE, MIE=0
//   PC     = base (direct) or base+4*cause (vectored)
//
// mret:
//   MIE=MPIE, MPIE=1, PC=mepc
//
// Interrupt priority: MEI (11) > MTI (7) > MSI (3)
// Exception priority: exceptions take priority over interrupts
// Exception cause codes: illegal=2, breakpoint=3, load_misaligned=4, load_fault=5,
//                        store_misaligned=6, store_fault=7, ecall=11
//
// 2-FF Synchronizer for AHB interrupt included in this module.
//
// Icarus constraint: ALL constant part-selects of registers extracted with assign.

module zicsr (
    input  logic        clk,
    input  logic        rst_n,

    //----------------- TỪ WB STAGE (qua mem2_wb_reg) -----------------
    input  logic [31:0] wb_pc,
    input  logic [31:0] wb_rs1_data,    // CSR write source (rs1, đã forward)
    input  logic [31:0] wb_imm,         // zimm (bits [4:0] used cho CSR-immediate)
    input  logic [11:0] wb_csr_addr,
    input  logic        wb_csr_we,      // 1 nếu có ghi CSR
    input  logic [1:0]  wb_csr_op,      // 00=RW, 01=RS, 10=RC
    input  logic        wb_csr_imm_sel, // 0=rs1, 1=zimm
    input  logic        wb_ecall,
    input  logic        wb_ebreak,
    input  logic        wb_mret,
    input  logic        wb_illegal_instr,
    input  logic        wb_load_fault,
    input  logic        wb_store_fault,

    //----------------- FAULT TỪ MEM PIPELINE -----------------
    input  logic        wb_load_misaligned,   // mcause=4: Load Address Misaligned
    input  logic        wb_store_misaligned,  // mcause=6: Store Address Misaligned

    //----------------- NGẮT NGOÀI -----------------
    input  logic        meip_in,        // Từ PLIC (đã arbiter priority, đã sync) → MEIP
    input  logic        mtip_in,        // Timer interrupt pending (direct from timer, HW-driven)

    //----------------- TỪ HAZARD UNIT -----------------
    input  logic        bus_stall_req,  // Không flush khi đang có bus transaction

    //----------------- SANG WB STAGE (kết quả đọc CSR) -----------------
    output logic [31:0] csr_rdata,

    //----------------- SANG HAZARD UNIT + IF1 STAGE -----------------
    output logic        zicsr_flush,    // Flush toàn pipeline
    output logic [31:0] zicsr_pc        // PC mới khi trap/mret
);

    //=========================================================
    // 1. CSR Register File
    // (2-FF sync cho AHB IRQ đã chuyển sang soc_top — PLIC nhận các source riêng)
    //=========================================================
    logic [31:0] mstatus, mie, mtvec, mepc, mcause;
    logic        mip_msip;   // Software interrupt pending (writable)

    // Pre-extract các field thường dùng (tránh part-select trong always)
    logic mstatus_mie, mstatus_mpie;
    assign mstatus_mie  = mstatus[3];
    assign mstatus_mpie = mstatus[7];

    logic mie_msie, mie_mtie, mie_meie;
    assign mie_msie = mie[3];
    assign mie_mtie = mie[7];
    assign mie_meie = mie[11];

    logic [1:0] mtvec_mode;
    logic [31:0] mtvec_base;
    assign mtvec_mode = mtvec[1:0];
    assign mtvec_base = {mtvec[31:2], 2'b00};

    // mip: MEIP[11] and MTIP[7] are read-only, hardware-driven (Privileged Spec §3.1.9)
    logic mip_meip, mip_mtip;
    assign mip_meip = meip_in;
    assign mip_mtip = mtip_in;

    logic [31:0] mip_val;
    assign mip_val = {20'b0, mip_meip, 3'b0, mip_mtip, 3'b0, mip_msip, 3'b0};

    //=========================================================
    // 3. CSR Read (Combinational)
    //=========================================================
    logic [31:0] csr_rdata_mux;
    always_comb begin
        case (wb_csr_addr)
            12'h300: csr_rdata_mux = mstatus;
            12'h304: csr_rdata_mux = mie;
            12'h305: csr_rdata_mux = mtvec;
            12'h341: csr_rdata_mux = mepc;
            12'h342: csr_rdata_mux = mcause;
            12'h344: csr_rdata_mux = mip_val;
            default: csr_rdata_mux = 32'd0;
        endcase
    end
    assign csr_rdata = csr_rdata_mux;

    //=========================================================
    // 4. CSR Write Data Computation (Combinational)
    //=========================================================
    logic [4:0]  wb_imm_4_0;
    assign wb_imm_4_0 = wb_imm[4:0];

    logic [31:0] csr_src;
    assign csr_src = wb_csr_imm_sel ? {27'd0, wb_imm_4_0} : wb_rs1_data;

    logic [31:0] csr_write_val;
    always_comb begin
        case (wb_csr_op)
            2'b01:   csr_write_val = csr_src;                      // CSRRW/I  — direct write
            2'b10:   csr_write_val = csr_rdata_mux | csr_src;     // CSRRS/I  — set bits
            2'b11:   csr_write_val = csr_rdata_mux & ~csr_src;    // CSRRC/I  — clear bits
            default: csr_write_val = csr_src;                      // fallback
        endcase
    end

    //=========================================================
    // 5. Interrupt / Exception Detection
    //=========================================================
    logic int_mei, int_mti, int_msi;
    assign int_mei = mip_meip & mie_meie;  // Machine External Interrupt
    assign int_mti = mip_mtip & mie_mtie;  // Machine Timer Interrupt
    assign int_msi = mip_msip & mie_msie;  // Machine Software Interrupt

    logic any_exception;
    assign any_exception = wb_ecall | wb_ebreak | wb_illegal_instr |
                           wb_load_fault  | wb_store_fault |
                           wb_load_misaligned | wb_store_misaligned;

    logic take_exception, take_interrupt;
    assign take_exception = any_exception & ~bus_stall_req;
    assign take_interrupt = ~any_exception & mstatus_mie & (int_mei | int_mti | int_msi) & ~bus_stall_req;

    //=========================================================
    // 6. mcause Value (Combinational)
    //=========================================================
    logic [31:0] next_mcause;
    always_comb begin
        if (take_exception) begin
            if      (wb_illegal_instr)   next_mcause = 32'd2;   // Illegal instruction
            else if (wb_ebreak)          next_mcause = 32'd3;   // Breakpoint
            else if (wb_load_misaligned) next_mcause = 32'd4;   // Load address misaligned
            else if (wb_load_fault)      next_mcause = 32'd5;   // Load access fault
            else if (wb_store_misaligned)next_mcause = 32'd6;   // Store address misaligned
            else if (wb_store_fault)     next_mcause = 32'd7;   // Store access fault
            else                         next_mcause = 32'd11;  // ecall from M-mode
        end else begin
            // Interrupt cause: bit31=1, priority MEI > MTI > MSI
            if      (int_mei) next_mcause = {1'b1, 31'd11};    // Machine external
            else if (int_mti) next_mcause = {1'b1, 31'd7};     // Machine timer
            else              next_mcause = {1'b1, 31'd3};     // Machine software
        end
    end

    //=========================================================
    // 7. Trap Vector (Combinational)
    //=========================================================
    // mtvec_mode[0]=0: Direct, mtvec_mode[0]=1: Vectored
    // Exceptions always go to BASE regardless of mode.
    // Vectored interrupts: BASE + 4*cause
    logic [31:0] int_vec_addr;
    always_comb begin
        if      (int_mei) int_vec_addr = mtvec_base + 32'd44;  // 4*11
        else if (int_mti) int_vec_addr = mtvec_base + 32'd28;  // 4*7
        else              int_vec_addr = mtvec_base + 32'd12;  // 4*3
    end

    logic mtvec_mode0;
    assign mtvec_mode0 = mtvec_mode[0];

    always_comb begin
        if (wb_mret)
            zicsr_pc = mepc;
        else if (take_exception)
            zicsr_pc = mtvec_base;
        else if (take_interrupt)
            zicsr_pc = mtvec_mode0 ? int_vec_addr : mtvec_base;
        else
            zicsr_pc = 32'd0;   // Don't care (flush=0)
    end

    assign zicsr_flush = take_exception | take_interrupt | wb_mret;

    //=========================================================
    // 8. mstatus Templates (Combinational, Icarus-safe)
    //=========================================================
    // On trap: MPIE=MIE, MIE=0, MPP=11(M-mode)
    logic [31:0] mstatus_trap;
    assign mstatus_trap = {19'd0, 2'b11, 3'd0, mstatus_mie, 3'd0, 1'b0, 3'd0};

    // On mret: MIE=MPIE, MPIE=1, MPP=11 (stays M-mode)
    logic [31:0] mstatus_mret_val;
    assign mstatus_mret_val = {19'd0, 2'b11, 3'd0, 1'b1, 3'd0, mstatus_mpie, 3'd0};

    //=========================================================
    // 9. CSR Register Updates (Sequential)
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 32'h0000_1800;  // MPP=11 (M-mode), MIE=0
            mie      <= 32'd0;
            mtvec    <= 32'd0;
            mepc     <= 32'd0;
            mcause   <= 32'd0;
            mip_msip <= 1'b0;

        end else if (take_exception || take_interrupt) begin
            // Trap: update mstatus, mepc, mcause
            mstatus <= mstatus_trap;
            // Exceptions: mepc = faulting instruction (WB hasn't committed yet for control flow)
            // Interrupts:  WB instruction commits at this rising edge → resume at PC+4
            mepc    <= take_interrupt ? (wb_pc + 32'd4) : wb_pc;
            mcause  <= next_mcause;
            // Other CSRs unchanged

        end else if (wb_mret) begin
            mstatus <= mstatus_mret_val;
            // PC restored via zicsr_pc = mepc

        end else if (wb_csr_we) begin
            // Normal CSR write
            case (wb_csr_addr)
                12'h300: mstatus  <= csr_write_val;
                12'h304: mie      <= csr_write_val;
                12'h305: mtvec    <= csr_write_val;
                12'h341: mepc     <= {csr_write_val[31:2], 2'b00};
                12'h342: mcause   <= csr_write_val;
                12'h344: mip_msip <= csr_write_val[3];  // Only MSIP writable
                default: ;
            endcase
        end
    end

endmodule
