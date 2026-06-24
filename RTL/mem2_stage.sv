// MEM2 Stage: Chọn nguồn dữ liệu + Trích xuất byte/half + Sign/Zero Extension
//
// Nguồn dữ liệu đọc:
//   mem_src=2'b00 (DMEM): dùng dmem_rdata (output đã register của DMEM, xuất hiện đúng chu kỳ MEM2)
//   mem_src=2'b01 (AXI) hoặc 2'b10 (AHB): dùng rdata_in (từ MEM1/MEM2 reg, đã capture khi bus xong)
//
// Byte/Half extraction:
//   RISC-V DMEM trả về full 32-bit word — MEM2 trích đúng byte/half dựa trên alu_result[1:0]
//   Tất cả bit-select hằng số dùng assign bên ngoài always (tránh lỗi Icarus)

module mem2_stage (
    //----------------- TỪ MEM1/MEM2 REGISTER -----------------
    input  logic [31:0] pc_in,
    input  logic [31:0] alu_result_in,   // Chứa địa chỉ bộ nhớ, [1:0] là byte offset
    input  logic [31:0] rdata_in,        // AXI/AHB read data
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] imm_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [11:0] csr_addr_in,
    input  logic [1:0]  mem_src_in,      // 2'b00=DMEM, 2'b01=AXI, 2'b10=AHB
    input  logic        mem_ext_in,      // 0=zero-extend, 1=sign-extend
    input  logic [1:0]  mem_size_in,     // 00=byte, 01=half, 10=word
    input  logic        reg_write_in,
    input  logic [1:0]  wb_sel_in,
    input  logic        csr_we_in,
    input  logic [1:0]  csr_op_in,
    input  logic        csr_imm_sel_in,
    input  logic        ecall_in,
    input  logic        ebreak_in,
    input  logic        mret_in,
    input  logic        illegal_instr_in,
    input  logic        load_fault_in,
    input  logic        store_fault_in,

    //----------------- DMEM (kết nối trực tiếp, không qua pipeline reg) -----------------
    input  logic [31:0] dmem_rdata,      // Output đã register của DMEM, valid ở chu kỳ MEM2

    //----------------- SANG MEM2/WB REGISTER -----------------
    output logic [31:0] pc_out,
    output logic [31:0] alu_result_out,
    output logic [31:0] mem_rdata_out,   // Dữ liệu đã xử lý (sign/zero extended)
    output logic [31:0] rs1_data_out,
    output logic [31:0] imm_out,
    output logic [4:0]  rd_addr_out,
    output logic [11:0] csr_addr_out,
    output logic        reg_write_out,
    output logic [1:0]  wb_sel_out,
    output logic        csr_we_out,
    output logic [1:0]  csr_op_out,
    output logic        csr_imm_sel_out,
    output logic        ecall_out,
    output logic        ebreak_out,
    output logic        mret_out,
    output logic        illegal_instr_out,
    output logic        load_fault_out,
    output logic        store_fault_out
);

    //=========================================================
    // 1. Chọn nguồn dữ liệu (Combinational)
    //=========================================================
    logic [31:0] raw_rdata;
    assign raw_rdata = (mem_src_in == 2'b00) ? dmem_rdata : rdata_in;

    //=========================================================
    // 2. Pre-extract byte offset ngoài always (Icarus-safe)
    //=========================================================
    logic [1:0] byte_off;
    logic       half_off;
    assign byte_off = alu_result_in[1:0];
    assign half_off = alu_result_in[1];

    //=========================================================
    // 3. Pre-extract tất cả byte/half lanes ngoài always
    //    để tránh constant part-select bên trong always_comb
    //=========================================================
    logic [7:0]  raw_b0, raw_b1, raw_b2, raw_b3;
    logic [15:0] raw_h0, raw_h1;
    assign raw_b0 = raw_rdata[7:0];
    assign raw_b1 = raw_rdata[15:8];
    assign raw_b2 = raw_rdata[23:16];
    assign raw_b3 = raw_rdata[31:24];
    assign raw_h0 = raw_rdata[15:0];
    assign raw_h1 = raw_rdata[31:16];

    // Pre-extract sign bits
    logic sign_b0, sign_b1, sign_b2, sign_b3;
    logic sign_h0, sign_h1;
    assign sign_b0 = raw_rdata[7];
    assign sign_b1 = raw_rdata[15];
    assign sign_b2 = raw_rdata[23];
    assign sign_b3 = raw_rdata[31];
    assign sign_h0 = raw_rdata[15];
    assign sign_h1 = raw_rdata[31];

    //=========================================================
    // 4. Byte/Half Extraction + Sign/Zero Extension
    //=========================================================
    always_comb begin
        mem_rdata_out = 32'd0;
        case (mem_size_in)
            2'b00: begin // Byte
                case (byte_off)
                    2'b00: mem_rdata_out = mem_ext_in ? {{24{sign_b0}}, raw_b0} : {24'd0, raw_b0};
                    2'b01: mem_rdata_out = mem_ext_in ? {{24{sign_b1}}, raw_b1} : {24'd0, raw_b1};
                    2'b10: mem_rdata_out = mem_ext_in ? {{24{sign_b2}}, raw_b2} : {24'd0, raw_b2};
                    2'b11: mem_rdata_out = mem_ext_in ? {{24{sign_b3}}, raw_b3} : {24'd0, raw_b3};
                endcase
            end
            2'b01: begin // Half-word
                case (half_off)
                    1'b0: mem_rdata_out = mem_ext_in ? {{16{sign_h0}}, raw_h0} : {16'd0, raw_h0};
                    1'b1: mem_rdata_out = mem_ext_in ? {{16{sign_h1}}, raw_h1} : {16'd0, raw_h1};
                endcase
            end
            default: mem_rdata_out = raw_rdata; // Word (2'b10): pass-through
        endcase
    end

    //=========================================================
    // 5. Pass-through sang MEM2/WB Register
    //=========================================================
    assign pc_out          = pc_in;
    assign alu_result_out  = alu_result_in;
    assign rs1_data_out    = rs1_data_in;
    assign imm_out         = imm_in;
    assign rd_addr_out     = rd_addr_in;
    assign csr_addr_out    = csr_addr_in;
    assign reg_write_out   = reg_write_in;
    assign wb_sel_out      = wb_sel_in;
    assign csr_we_out      = csr_we_in;
    assign csr_op_out      = csr_op_in;
    assign csr_imm_sel_out = csr_imm_sel_in;
    assign ecall_out       = ecall_in;
    assign ebreak_out      = ebreak_in;
    assign mret_out        = mret_in;
    assign illegal_instr_out = illegal_instr_in;
    assign load_fault_out  = load_fault_in;
    assign store_fault_out = store_fault_in;

endmodule
