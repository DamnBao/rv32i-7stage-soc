module ex_mem1_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,   // Từ Hazard Unit (bus_stall_req)
    input  logic        flush,   // Từ Zicsr (exception/interrupt)

    //----------------- INPUTS TỪ TẦNG EX -----------------
    // Dữ liệu
    input  logic [31:0] pc_in,
    input  logic [31:0] alu_result_in,  // Kết quả ALU (đồng thời là địa chỉ Load/Store)
    input  logic [31:0] rs2_data_in,    // Dữ liệu ghi Store (đã qua Forwarding MUX)
    input  logic [31:0] rs1_data_in,    // Nguồn dữ liệu CSR (đã qua Forwarding MUX)
    input  logic [31:0] imm_in,         // zimm cho lệnh CSR-immediate
    input  logic [4:0]  rd_addr_in,
    input  logic [11:0] csr_addr_in,

    // Tín hiệu điều khiển MEM
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    input  logic [1:0]  mem_size_in,
    input  logic        mem_ext_in,

    // Tín hiệu điều khiển WB
    input  logic        reg_write_in,
    input  logic [1:0]  wb_sel_in,

    // Tín hiệu điều khiển Zicsr
    input  logic        csr_we_in,
    input  logic [1:0]  csr_op_in,
    input  logic        csr_imm_sel_in,
    input  logic        ecall_in,
    input  logic        ebreak_in,
    input  logic        mret_in,
    input  logic        illegal_instr_in,

    //----------------- OUTPUTS SANG TẦNG MEM1 -----------------
    output logic [31:0] pc_out,
    output logic [31:0] alu_result_out,
    output logic [31:0] rs2_data_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] imm_out,
    output logic [4:0]  rd_addr_out,
    output logic [11:0] csr_addr_out,

    output logic        mem_read_out,
    output logic        mem_write_out,
    output logic [1:0]  mem_size_out,
    output logic        mem_ext_out,

    output logic        reg_write_out,
    output logic [1:0]  wb_sel_out,

    output logic        csr_we_out,
    output logic [1:0]  csr_op_out,
    output logic        csr_imm_sel_out,
    output logic        ecall_out,
    output logic        ebreak_out,
    output logic        mret_out,
    output logic        illegal_instr_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out            <= '0;
            alu_result_out    <= '0;
            rs2_data_out      <= '0;
            rs1_data_out      <= '0;
            imm_out           <= '0;
            rd_addr_out       <= '0;
            csr_addr_out      <= '0;

            mem_read_out      <= 1'b0;
            mem_write_out     <= 1'b0;
            mem_size_out      <= 2'b00;
            mem_ext_out       <= 1'b0;

            reg_write_out     <= 1'b0;
            wb_sel_out        <= 2'b00;

            csr_we_out        <= 1'b0;
            csr_op_out        <= 2'b00;
            csr_imm_sel_out   <= 1'b0;
            ecall_out         <= 1'b0;
            ebreak_out        <= 1'b0;
            mret_out          <= 1'b0;
            illegal_instr_out <= 1'b0;

        end else if (flush) begin
            // Xóa các tín hiệu điều khiển gây tác động, biến lệnh thành NOP
            pc_out            <= '0;
            mem_read_out      <= 1'b0;
            mem_write_out     <= 1'b0;
            reg_write_out     <= 1'b0;
            csr_we_out        <= 1'b0;
            ecall_out         <= 1'b0;
            ebreak_out        <= 1'b0;
            mret_out          <= 1'b0;
            illegal_instr_out <= 1'b0;

        end else if (!stall) begin
            pc_out            <= pc_in;
            alu_result_out    <= alu_result_in;
            rs2_data_out      <= rs2_data_in;
            rs1_data_out      <= rs1_data_in;
            imm_out           <= imm_in;
            rd_addr_out       <= rd_addr_in;
            csr_addr_out      <= csr_addr_in;

            mem_read_out      <= mem_read_in;
            mem_write_out     <= mem_write_in;
            mem_size_out      <= mem_size_in;
            mem_ext_out       <= mem_ext_in;

            reg_write_out     <= reg_write_in;
            wb_sel_out        <= wb_sel_in;

            csr_we_out        <= csr_we_in;
            csr_op_out        <= csr_op_in;
            csr_imm_sel_out   <= csr_imm_sel_in;
            ecall_out         <= ecall_in;
            ebreak_out        <= ebreak_in;
            mret_out          <= mret_in;
            illegal_instr_out <= illegal_instr_in;
        end
        // stall=1, flush=0: giữ nguyên toàn bộ giá trị
    end

endmodule
