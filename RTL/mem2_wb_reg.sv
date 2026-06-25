// MEM2/WB Pipeline Register — carries MEM2 results to the WB stage.
//
// flush: clears control signals to NOP — fires on zicsr trap/MRET.
// stall: holds register values — fires on bus_stall_req.
// flush wins if both assert simultaneously.

module mem2_wb_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,   // Freeze (bus_stall_req from mem1_stage)
    input  logic        flush,   // Clear to NOP (zicsr trap/MRET)

    //----------------- INPUTS TỪ MEM2 STAGE -----------------
    input  logic [31:0] pc_in,
    input  logic [31:0] alu_result_in,
    input  logic [31:0] mem_rdata_in,
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] imm_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [11:0] csr_addr_in,
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

    //----------------- OUTPUTS SANG WB STAGE -----------------
    output logic [31:0] pc_out,
    output logic [31:0] alu_result_out,
    output logic [31:0] mem_rdata_out,
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out            <= '0;
            alu_result_out    <= '0;
            mem_rdata_out     <= '0;
            rs1_data_out      <= '0;
            imm_out           <= '0;
            rd_addr_out       <= '0;
            csr_addr_out      <= '0;
            reg_write_out     <= 1'b0;
            wb_sel_out        <= 2'b00;
            csr_we_out        <= 1'b0;
            csr_op_out        <= 2'b00;
            csr_imm_sel_out   <= 1'b0;
            ecall_out         <= 1'b0;
            ebreak_out        <= 1'b0;
            mret_out          <= 1'b0;
            illegal_instr_out <= 1'b0;
            load_fault_out    <= 1'b0;
            store_fault_out   <= 1'b0;

        end else if (flush) begin
            pc_out            <= '0;
            reg_write_out     <= 1'b0;
            csr_we_out        <= 1'b0;
            ecall_out         <= 1'b0;
            ebreak_out        <= 1'b0;
            mret_out          <= 1'b0;
            illegal_instr_out <= 1'b0;
            load_fault_out    <= 1'b0;
            store_fault_out   <= 1'b0;

        end else if (!stall) begin
            pc_out            <= pc_in;
            alu_result_out    <= alu_result_in;
            mem_rdata_out     <= mem_rdata_in;
            rs1_data_out      <= rs1_data_in;
            imm_out           <= imm_in;
            rd_addr_out       <= rd_addr_in;
            csr_addr_out      <= csr_addr_in;
            reg_write_out     <= reg_write_in;
            wb_sel_out        <= wb_sel_in;
            csr_we_out        <= csr_we_in;
            csr_op_out        <= csr_op_in;
            csr_imm_sel_out   <= csr_imm_sel_in;
            ecall_out         <= ecall_in;
            ebreak_out        <= ebreak_in;
            mret_out          <= mret_in;
            illegal_instr_out <= illegal_instr_in;
            load_fault_out    <= load_fault_in;
            store_fault_out   <= store_fault_in;
        end
        // stall=1, flush=0: giữ nguyên
    end

endmodule
