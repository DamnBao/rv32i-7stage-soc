// Forwarding Unit: Bypass data từ MEM1/MEM2/WB về EX stage
//
// fwd_sel encoding (cho mỗi nguồn ALU):
//   2'b00 = Không forward — dùng dữ liệu từ ID/EX register
//   2'b01 = Forward từ MEM1 (EX/MEM1 register output: alu_result)
//   2'b10 = Forward từ MEM2 (MEM1/MEM2 register output: alu_result hoặc mem_rdata)
//   2'b11 = Forward từ WB  (MEM2/WB register output: rf_wr_data đã tính)
//
// Ưu tiên: MEM1 > MEM2 > WB (gần nhất ưu tiên cao nhất)
//
// Lưu ý: x0 không bao giờ cần forward (rd_addr==0 nghĩa là không ghi)

module forwarding_unit (
    //----------------- RS1/RS2 TẠI EX (từ ID/EX register) -----------------
    input  logic [4:0] ex_rs1_addr,
    input  logic [4:0] ex_rs2_addr,

    //----------------- MEM1 (EX/MEM1 register output) -----------------
    input  logic [4:0] mem1_rd_addr,
    input  logic       mem1_reg_write,

    //----------------- MEM2 (MEM1/MEM2 register output) -----------------
    input  logic [4:0] mem2_rd_addr,
    input  logic       mem2_reg_write,

    //----------------- WB (MEM2/WB register output) -----------------
    input  logic [4:0] wb_rd_addr,
    input  logic       wb_reg_write,

    //----------------- KẾT QUẢ FORWARD SELECT -----------------
    output logic [1:0] fwd_sel_a,   // Cho ALU input A (rs1)
    output logic [1:0] fwd_sel_b    // Cho ALU input B (rs2)
);

    always_comb begin
        // Forward A (rs1)
        if (mem1_reg_write && (mem1_rd_addr != 5'd0) && (mem1_rd_addr == ex_rs1_addr))
            fwd_sel_a = 2'b01;
        else if (mem2_reg_write && (mem2_rd_addr != 5'd0) && (mem2_rd_addr == ex_rs1_addr))
            fwd_sel_a = 2'b10;
        else if (wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == ex_rs1_addr))
            fwd_sel_a = 2'b11;
        else
            fwd_sel_a = 2'b00;
    end

    always_comb begin
        // Forward B (rs2)
        if (mem1_reg_write && (mem1_rd_addr != 5'd0) && (mem1_rd_addr == ex_rs2_addr))
            fwd_sel_b = 2'b01;
        else if (mem2_reg_write && (mem2_rd_addr != 5'd0) && (mem2_rd_addr == ex_rs2_addr))
            fwd_sel_b = 2'b10;
        else if (wb_reg_write && (wb_rd_addr != 5'd0) && (wb_rd_addr == ex_rs2_addr))
            fwd_sel_b = 2'b11;
        else
            fwd_sel_b = 2'b00;
    end

endmodule
