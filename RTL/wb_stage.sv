// WB Stage: Chọn kết quả ghi về Register File
//
// wb_sel encoding:
//   2'b00 = ALU result
//   2'b01 = MEM read data (load)
//   2'b10 = PC+4 (JAL/JALR link)
//   2'b11 = CSR read data
//
// CSR read data đến từ Zicsr module (csr_rdata_in).
// rs1_data_in là nguồn dữ liệu CSR WRITE (đã forward ở EX), không phải WB output.

module wb_stage (
    //----------------- TỪ MEM2/WB REGISTER -----------------
    input  logic [31:0] pc_in,
    input  logic [31:0] alu_result_in,
    input  logic [31:0] mem_rdata_in,
    input  logic [4:0]  rd_addr_in,
    input  logic        reg_write_in,
    input  logic [1:0]  wb_sel_in,

    //----------------- TỪ ZICSR (CSR Read Data) -----------------
    input  logic [31:0] csr_rdata_in,

    //----------------- SANG REGISTER FILE -----------------
    output logic [4:0]  rf_rd_addr,
    output logic        rf_we,
    output logic [31:0] rf_wr_data
);

    // PC+4: tính combinational từ PC của lệnh JAL/JALR
    logic [31:0] pc_plus4;
    assign pc_plus4 = pc_in + 32'd4;

    always_comb begin
        case (wb_sel_in)
            2'b00:   rf_wr_data = alu_result_in;
            2'b01:   rf_wr_data = mem_rdata_in;
            2'b10:   rf_wr_data = pc_plus4;
            default: rf_wr_data = csr_rdata_in;  // 2'b11
        endcase
    end

    assign rf_rd_addr = rd_addr_in;
    assign rf_we      = reg_write_in;

endmodule
