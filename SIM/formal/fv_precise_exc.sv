// Formal verification: Precise Exception — no trap taken during in-flight bus transaction
//
// RISC-V Privileged Spec requires precise exceptions: when a trap is taken,
// the faulting instruction's effect is atomic — no partial side effects exist.
// For bus transactions: a pending exception/interrupt must NOT cause a pipeline
// flush while bus_stall_req=1, because the AXI/AHB transaction is mid-flight
// and the response has not yet been received.
//
// Implementation in zicsr.sv:
//   any_exception  = wb_ecall | wb_ebreak | wb_illegal_instr |
//                    wb_load_fault | wb_store_fault |
//                    wb_load_misaligned | wb_store_misaligned
//   take_exception = any_exception & ~bus_stall_req       ← gated
//   take_interrupt = ~any_exc & mstatus_mie & irq & ~bus_stall_req  ← gated
//   zicsr_flush    = take_exception | take_interrupt | wb_mret
//
// Note: wb_mret is NOT gated by ~bus_stall_req.
// This is safe: MRET is a control instruction with no memory side effect;
// by the time MRET reaches WB, any bus transaction it initiated is done.
//
// Properties proved (6):
//   P_BUS_STALL_GATE  : bus_stall_req → (zicsr_flush == wb_mret)
//   P_MRET_FLUSH      : wb_mret → zicsr_flush (MRET always flushes)
//   P_EXC_FLUSH       : any_exc & !bus_stall_req → zicsr_flush (completeness)
//   P_EXC_HELD        : bus_stall_req & any_exc → !(zicsr_flush & !wb_mret)
//   P_FLUSH_IDLE_BUS  : (zicsr_flush & !wb_mret) → !bus_stall_req (contrapositive)
//   P_NO_DOUBLE_GATE  : bus_stall_req & any_exc & !wb_mret → !zicsr_flush

`timescale 1ns/1ps
module fv_precise_exc (
    input logic clk,
    input logic rst_n
);

    // ── Symbolic inputs (free variables — no driver needed in formal) ─────
    logic [31:0] wb_pc;
    logic [31:0] wb_rs1_data;
    logic [31:0] wb_imm;
    logic [11:0] wb_csr_addr;
    logic        wb_csr_we;
    logic [1:0]  wb_csr_op;
    logic        wb_csr_imm_sel;
    logic        wb_ecall;
    logic        wb_ebreak;
    logic        wb_mret;
    logic        wb_illegal_instr;
    logic        wb_load_fault;
    logic        wb_store_fault;
    logic        wb_load_misaligned;
    logic        wb_store_misaligned;
    logic        meip_in;
    logic        mtip_in;
    logic        bus_stall_req;

    // ── DUT outputs ───────────────────────────────────────────────────────
    logic [31:0] csr_rdata;
    logic        zicsr_flush;
    logic [31:0] zicsr_pc;

    // ── DUT instantiation ─────────────────────────────────────────────────
    zicsr dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .wb_pc             (wb_pc),
        .wb_rs1_data       (wb_rs1_data),
        .wb_imm            (wb_imm),
        .wb_csr_addr       (wb_csr_addr),
        .wb_csr_we         (wb_csr_we),
        .wb_csr_op         (wb_csr_op),
        .wb_csr_imm_sel    (wb_csr_imm_sel),
        .wb_ecall          (wb_ecall),
        .wb_ebreak         (wb_ebreak),
        .wb_mret           (wb_mret),
        .wb_illegal_instr  (wb_illegal_instr),
        .wb_load_fault     (wb_load_fault),
        .wb_store_fault    (wb_store_fault),
        .wb_load_misaligned(wb_load_misaligned),
        .wb_store_misaligned(wb_store_misaligned),
        .meip_in           (meip_in),
        .mtip_in           (mtip_in),
        .bus_stall_req     (bus_stall_req),
        .csr_rdata         (csr_rdata),
        .zicsr_flush       (zicsr_flush),
        .zicsr_pc          (zicsr_pc)
    );

    initial assume (!rst_n);

    // ── Derived wire: mirrors zicsr.sv any_exception assignment ──────────
    // Maintained alongside RTL — if any_exception changes in zicsr.sv, update here.
    wire any_exc = wb_ecall | wb_ebreak | wb_illegal_instr |
                   wb_load_fault | wb_store_fault |
                   wb_load_misaligned | wb_store_misaligned;

    // ── P_BUS_STALL_GATE ─────────────────────────────────────────────────
    // Core invariant: during a bus transaction, zicsr_flush fires ONLY if
    // wb_mret=1. Exceptions and interrupts are suppressed (held pending).
    // Directly encodes: take_exception = any_exc & ~bus_stall_req
    //                   take_interrupt = ... & ~bus_stall_req
    //   →  bus_stall_req → flush iff wb_mret
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(bus_stall_req && (zicsr_flush != wb_mret)));
        end
    end

    // ── P_MRET_FLUSH ─────────────────────────────────────────────────────
    // MRET always causes a flush (redirects PC to mepc).
    // Not gated by bus_stall_req — MRET has no memory side effect.
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(wb_mret && !zicsr_flush));
        end
    end

    // ── P_EXC_FLUSH ──────────────────────────────────────────────────────
    // Completeness: exception when bus is idle always triggers flush.
    // Ensures exceptions are never silently dropped.
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(any_exc && !bus_stall_req && !zicsr_flush));
        end
    end

    // ── P_EXC_HELD ───────────────────────────────────────────────────────
    // When bus is busy AND exception is pending, flush must NOT fire
    // (unless wb_mret coincidentally arrives — MRET path is independent).
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(bus_stall_req && any_exc && zicsr_flush && !wb_mret));
        end
    end

    // ── P_FLUSH_IDLE_BUS ─────────────────────────────────────────────────
    // Contrapositive of P_BUS_STALL_GATE (exception/interrupt direction):
    // any non-MRET flush implies bus is currently idle.
    // Equivalently: no in-flight bus transaction is aborted by exception/interrupt.
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(zicsr_flush && !wb_mret && bus_stall_req));
        end
    end

    // ── P_NO_DOUBLE_GATE ─────────────────────────────────────────────────
    // Strongest form: when bus busy AND exception pending AND no MRET,
    // zicsr_flush is strictly 0.
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!(bus_stall_req && any_exc && !wb_mret && zicsr_flush));
        end
    end

endmodule
