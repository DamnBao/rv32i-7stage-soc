// MEM1/MEM2 Pipeline Register — carries MEM1 results to MEM2.
//
// flush: only fires after a bus transaction completes (zicsr holds off trap until
//        bus_stall_req drops, ensuring precise exceptions on AXI/AHB accesses).
// stall: fires for the full duration of a bus_stall_req.
// flush wins if both assert simultaneously.

module mem1_mem2_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,   // Freeze (bus_stall_req — holds pipeline while AXI/AHB pending)
    input  logic        flush,   // Clear to NOP (zicsr trap/MRET, deferred until bus completes)

    //----------------- INPUTS TỪ MEM1 STAGE -----------------
    input  logic [31:0] pc_in,
    input  logic [31:0] alu_result_in,
    input  logic [31:0] rdata_in,        // AXI/AHB bus read data (hợp lệ khi bus_stall_req=0)
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] imm_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [11:0] csr_addr_in,
    input  logic [1:0]  mem_src_in,      // 2'b00=DMEM, 2'b01=AXI, 2'b10=AHB, 2'b11=PLIC
    input  logic        mem_ext_in,
    input  logic [1:0]  mem_size_in,
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

    //----------------- OUTPUTS SANG MEM2 STAGE -----------------
    output logic [31:0] pc_out,
    output logic [31:0] alu_result_out,
    output logic [31:0] rdata_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] imm_out,
    output logic [4:0]  rd_addr_out,
    output logic [11:0] csr_addr_out,
    output logic [1:0]  mem_src_out,
    output logic        mem_ext_out,
    output logic [1:0]  mem_size_out,
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
            rdata_out         <= '0;
            rs1_data_out      <= '0;
            imm_out           <= '0;
            rd_addr_out       <= '0;
            csr_addr_out      <= '0;
            mem_src_out       <= 2'b00;
            mem_ext_out       <= 1'b0;
            mem_size_out      <= 2'b00;
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
            rdata_out         <= rdata_in;
            rs1_data_out      <= rs1_data_in;
            imm_out           <= imm_in;
            rd_addr_out       <= rd_addr_in;
            csr_addr_out      <= csr_addr_in;
            mem_src_out       <= mem_src_in;
            mem_ext_out       <= mem_ext_in;
            mem_size_out      <= mem_size_in;
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
        // stall=1, flush=0: giữ nguyên toàn bộ
    end

endmodule
