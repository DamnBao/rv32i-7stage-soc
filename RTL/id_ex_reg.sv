module id_ex_reg (
    input  logic        clk,
    input  logic        rst_n,
    
    // Tín hiệu điều khiển pipeline từ Hazard Unit
    input  logic        stall,
    input  logic        flush,
    
    //----------------- INPUTS TỪ TẦNG ID -----------------
    input  logic [31:0] pc_in,
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] rs2_data_in,
    input  logic [31:0] imm_in,
    input  logic [4:0]  rs1_addr_in,
    input  logic [4:0]  rs2_addr_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [11:0] csr_addr_in,
    input  logic [2:0]  funct3_in,
    
    // Tín hiệu điều khiển EX
    input  logic [3:0]  alu_op_in,
    input  logic        alu_src_a_in,
    input  logic        alu_src_b_in,
    input  logic        branch_in,
    input  logic        jump_in,
    input  logic        jump_reg_in,
    
    // Tín hiệu điều khiển MEM
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    input  logic [1:0]  mem_size_in,
    input  logic        mem_ext_in,
    
    // Tín hiệu điều khiển WB & Zicsr
    input  logic        reg_write_in,
    input  logic [1:0]  wb_sel_in,
    input  logic        csr_we_in,
    input  logic [1:0]  csr_op_in,
    input  logic        csr_imm_sel_in,
    input  logic        ecall_in,
    input  logic        ebreak_in,
    input  logic        mret_in,
    input  logic        illegal_instr_in,

    //----------------- OUTPUTS SANG TẦNG EX -----------------
    output logic [31:0] pc_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] rs2_data_out,
    output logic [31:0] imm_out,
    output logic [4:0]  rs1_addr_out,
    output logic [4:0]  rs2_addr_out,
    output logic [4:0]  rd_addr_out,
    output logic [11:0] csr_addr_out,
    output logic [2:0]  funct3_out,
    
    output logic [3:0]  alu_op_out,
    output logic        alu_src_a_out,
    output logic        alu_src_b_out,
    output logic        branch_out,
    output logic        jump_out,
    output logic        jump_reg_out,
    
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
            // Reset toàn bộ về 0
            pc_out            <= '0;
            rs1_data_out      <= '0;
            rs2_data_out      <= '0;
            imm_out           <= '0;
            rs1_addr_out      <= '0;
            rs2_addr_out      <= '0;
            rd_addr_out       <= '0;
            csr_addr_out      <= '0;
            funct3_out        <= '0;
            
            alu_op_out        <= '0;
            alu_src_a_out     <= 1'b0;
            alu_src_b_out     <= 1'b0;
            branch_out        <= 1'b0;
            jump_out          <= 1'b0;
            jump_reg_out      <= 1'b0;
            
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
            // Chỉ xóa các tín hiệu Control gây tác động, để nó biến thành NOP
            // Dữ liệu rác có trôi đi cũng không sao vì không có we/write
            pc_out            <= '0;
            branch_out        <= 1'b0;
            jump_out          <= 1'b0;
            mem_read_out      <= 1'b0;
            mem_write_out     <= 1'b0;
            reg_write_out     <= 1'b0;
            csr_we_out        <= 1'b0;
            ecall_out         <= 1'b0;
            ebreak_out        <= 1'b0;
            mret_out          <= 1'b0;
            illegal_instr_out <= 1'b0;
            
        end else if (!stall) begin
            // Khi không bị đóng băng, lấy tín hiệu từ tầng ID đi vào
            pc_out            <= pc_in;
            rs1_data_out      <= rs1_data_in;
            rs2_data_out      <= rs2_data_in;
            imm_out           <= imm_in;
            rs1_addr_out      <= rs1_addr_in;
            rs2_addr_out      <= rs2_addr_in;
            rd_addr_out       <= rd_addr_in;
            csr_addr_out      <= csr_addr_in;
            funct3_out        <= funct3_in;
            
            alu_op_out        <= alu_op_in;
            alu_src_a_out     <= alu_src_a_in;
            alu_src_b_out     <= alu_src_b_in;
            branch_out        <= branch_in;
            jump_out          <= jump_in;
            jump_reg_out      <= jump_reg_in;
            
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
    end

endmodule
