// Formal verification wrapper: register_file — Write-Before-Read bypass
//
// Properties:
//   P_WBR:    same-cycle bypass: writing to rd_addr (≠0) while reading rs1_addr
//             == rd_addr → rs1_data must equal rd_data immediately (combinational)
//   P_RF_SEQ: next-cycle read: if we wrote rd_data to rd_addr last cycle (≠0),
//             reading rs1_addr == rd_addr this cycle (with no concurrent write to
//             the same address) returns the written value
//
// These two properties together prove full read-after-write consistency for the
// register file: the pipeline never reads a stale value regardless of whether
// the write just happened (gap-0 WBR bypass) or one cycle ago (gap-1 from mem).

`timescale 1ns/1ps
module fv_reg_wbr (
    input logic clk,
    input logic rst_n
);
    // Symbolic inputs
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic        we;
    logic [31:0] rd_data;

    // DUT outputs
    logic [31:0] rs1_data, rs2_data;

    register_file dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .we      (we),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    initial assume(!rst_n);

    // ── P_WBR: same-cycle bypass ─────────────────────────────────────
    // When a write to rd_addr (non-zero) coincides with a read of the same
    // address on rs1, the combinational bypass must forward rd_data.
    always @(posedge clk) begin
        if (rst_n && we && rd_addr != 5'd0 && rs1_addr == rd_addr)
            assert(rs1_data == rd_data);
    end

    // ── P_RF_SEQ: next-cycle read consistency ────────────────────────
    // After a write in cycle N, a read in cycle N+1 to the same address
    // (with no new write in N+1) must return the value written in N.
    always @(posedge clk) begin
        if (rst_n && $past(rst_n) &&
            $past(we) && $past(rd_addr) != 5'd0 &&
            rs1_addr == $past(rd_addr) &&
            !(we && rd_addr == $past(rd_addr))) begin
            assert(rs1_data == $past(rd_data));
        end
    end

    // ── Symmetric check on rs2 port ──────────────────────────────────
    always @(posedge clk) begin
        if (rst_n && we && rd_addr != 5'd0 && rs2_addr == rd_addr)
            assert(rs2_data == rd_data);
    end

    always @(posedge clk) begin
        if (rst_n && $past(rst_n) &&
            $past(we) && $past(rd_addr) != 5'd0 &&
            rs2_addr == $past(rd_addr) &&
            !(we && rd_addr == $past(rd_addr))) begin
            assert(rs2_data == $past(rd_data));
        end
    end

endmodule
