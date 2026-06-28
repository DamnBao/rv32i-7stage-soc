// MEM1 Stage: Address Decode + Bus Transaction FSM
//
// Nhiệm vụ:
//   1. Giải mã địa chỉ (addr_in = alu_result) vào 4 vùng: DMEM / AXI / AHB / Unmapped
//   2. Điều khiển giao dịch bus với DMEM, AXI Interface, và AHB Request/Response FIFO
//   3. Phát bus_stall_req về Hazard Unit khi giao dịch AXI/AHB chưa xong
//   4. Phát fault về Zicsr khi địa chỉ không hợp lệ hoặc bus trả về lỗi
//
// Ràng buộc "Precise Exception":
//   FSM KHÔNG bị flush giữa chừng — nếu ngắt/exception xuất hiện khi đang giao dịch,
//   Hazard Unit phải giữ stall cho đến khi giao dịch kết thúc, Zicsr mới xử lý.
//
// Payload AHB Request FIFO (67-bit):
//   [66:35] = addr (32-bit)
//   [34:3]  = wdata (32-bit)
//   [2]     = mem_write (1=write, 0=read)
//   [1:0]   = mem_size (HSIZE: 00=byte, 01=half, 10=word)
//
// Payload AHB Response FIFO (33-bit):
//   [32]    = HRESP (1=error)
//   [31:0]  = read data

module mem1_stage (
    input  logic        clk,
    input  logic        rst_n,

    //----------------- TỪ EX/MEM1 REGISTER -----------------
    input  logic [31:0] addr_in,          // = alu_result (địa chỉ bộ nhớ hoặc kết quả ALU)
    input  logic [31:0] wdata_in,         // = rs2_data (dữ liệu ghi Store)
    input  logic [31:0] rs1_data_in,      // nguồn dữ liệu CSR (đã forward)
    input  logic [31:0] imm_in,           // zimm cho CSR-immediate
    input  logic [31:0] pc_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [11:0] csr_addr_in,
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    input  logic [1:0]  mem_size_in,
    input  logic        mem_ext_in,
    input  logic        reg_write_in,
    input  logic [1:0]  wb_sel_in,
    input  logic        csr_we_in,
    input  logic [1:0]  csr_op_in,
    input  logic        csr_imm_sel_in,
    input  logic        ecall_in,
    input  logic        ebreak_in,
    input  logic        mret_in,
    input  logic        illegal_instr_in,

    //----------------- DMEM INTERFACE (1GHz, no stall) -----------------
    output logic        dmem_re,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [1:0]  dmem_size,

    //----------------- AXI INTERFACE (1GHz, đồng bộ) -----------------
    output logic        axi_req_valid,
    output logic [31:0] axi_req_addr,
    output logic        axi_req_we,
    output logic [31:0] axi_req_wdata,
    output logic [1:0]  axi_req_size,
    input  logic        axi_resp_valid,
    input  logic [31:0] axi_resp_rdata,
    input  logic        axi_resp_err,

    //----------------- AHB REQUEST FIFO (Write domain: 1GHz) -----------------
    output logic        req_fifo_wr_en,
    output logic [66:0] req_fifo_wr_data,

    //----------------- AHB RESPONSE FIFO (Read domain: 1GHz) -----------------
    input  logic        resp_fifo_rd_empty,
    output logic        resp_fifo_rd_en,
    input  logic [32:0] resp_fifo_rd_data, // [32]=HRESP err, [31:0]=rdata

    //----------------- PLIC INTERFACE (1GHz, synchronous — no stall) -----------------
    output logic        plic_re,
    output logic        plic_we,
    output logic [23:0] plic_addr,
    output logic [31:0] plic_wdata,

    //----------------- HAZARD UNIT -----------------
    output logic        bus_stall_req,

    //----------------- ZICSR (Fault signals) -----------------
    output logic        load_access_fault,
    output logic        store_access_fault,

    //----------------- SANG MEM1/MEM2 REGISTER -----------------
    output logic [31:0] pc_out,
    output logic [31:0] alu_result_out,   // = addr_in (pass-through)
    output logic [31:0] rdata_out,        // dữ liệu đọc từ AXI/AHB (hợp lệ khi bus xong)
    output logic [31:0] rs1_data_out,
    output logic [31:0] imm_out,
    output logic [4:0]  rd_addr_out,
    output logic [11:0] csr_addr_out,
    output logic [1:0]  mem_src_out,      // 2'b00=DMEM, 2'b01=AXI, 2'b10=AHB
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
    output logic        load_misaligned_out,   // mcause=4: Load Address Misaligned
    output logic        store_misaligned_out   // mcause=6: Store Address Misaligned
);

    //=========================================================
    // 1. Address Decode (Bit-slicing dùng assign ngoài always)
    //=========================================================
    logic [15:0] addr_31_16;
    logic [3:0]  addr_31_28;
    logic [7:0]  addr_31_24;
    assign addr_31_16 = addr_in[31:16];
    assign addr_31_28 = addr_in[31:28];
    assign addr_31_24 = addr_in[31:24];

    logic dmem_sel, axi_sel, ahb_sel, plic_sel, fault_sel;
    assign dmem_sel  = (addr_31_16 == 16'h0001);
    assign axi_sel   = (addr_31_28 == 4'h2);
    assign ahb_sel   = (addr_31_28 == 4'h3);
    assign plic_sel  = (addr_31_24 == 8'h0C);  // 0x0C000000 – 0x0CFFFFFF
    assign fault_sel = ~dmem_sel & ~axi_sel & ~ahb_sel & ~plic_sel;

    logic is_mem_access;
    assign is_mem_access = mem_read_in | mem_write_in;

    // Misaligned detection (RV32I §2.6): halfword needs addr[0]=0, word needs addr[1:0]=00
    logic addr_0, addr_1;
    assign addr_0 = addr_in[0];
    assign addr_1 = addr_in[1];
    logic misaligned;
    assign misaligned = (mem_size_in == 2'b01) ? addr_0 :
                        (mem_size_in == 2'b10) ? (addr_0 | addr_1) :
                        1'b0;

    // Only valid (aligned) accesses proceed to bus
    logic is_mem_access_valid;
    assign is_mem_access_valid = is_mem_access & ~misaligned;

    //=========================================================
    // 2. Bus Transaction FSM
    //=========================================================
    localparam IDLE     = 2'd0;
    localparam AXI_WAIT = 2'd1;
    localparam AHB_WAIT = 2'd2;

    logic [1:0] state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (is_mem_access && axi_sel)      state <= AXI_WAIT;
                    else if (is_mem_access && ahb_sel) state <= AHB_WAIT;
                end
                AXI_WAIT: if (axi_resp_valid)          state <= IDLE;
                AHB_WAIT: if (!resp_fifo_rd_empty)     state <= IDLE;
                default:                               state <= IDLE;
            endcase
        end
    end

    //=========================================================
    // 3. Bus Stall (Combinational)
    // Assert ngay khi phát hiện giao dịch bus, giữ đến khi có phản hồi
    // Misaligned accesses never enter AXI_WAIT/AHB_WAIT so no extra guard needed.
    //=========================================================
    assign bus_stall_req =
        (is_mem_access_valid & (axi_sel | ahb_sel) & (state == IDLE)) |
        (state == AXI_WAIT & ~axi_resp_valid)                          |
        (state == AHB_WAIT &  resp_fifo_rd_empty);

    //=========================================================
    // 4. DMEM Interface
    // Tín hiệu tổ hợp — DMEM đồng bộ hóa nội bộ, data ra ở MEM2
    //=========================================================
    assign dmem_re    = is_mem_access_valid & dmem_sel & mem_read_in;
    assign dmem_we    = is_mem_access_valid & dmem_sel & mem_write_in;
    assign dmem_addr  = addr_in;
    assign dmem_wdata = wdata_in;
    assign dmem_size  = mem_size_in;

    //=========================================================
    // 5. AXI Interface
    // Giữ req_valid suốt AXI_WAIT (AXI Interface latch ở chu kỳ đầu)
    //=========================================================
    assign axi_req_valid = is_mem_access_valid & axi_sel & (state == IDLE || state == AXI_WAIT);
    assign axi_req_addr  = addr_in;
    assign axi_req_we    = mem_write_in;
    assign axi_req_wdata = wdata_in;
    assign axi_req_size  = mem_size_in;

    //=========================================================
    // 6. AHB Request FIFO
    // wr_en chỉ assert 1 chu kỳ trong IDLE — sau đó FSM chuyển sang AHB_WAIT
    // nên wr_en=0, không ghi lại vào FIFO
    //=========================================================
    assign req_fifo_wr_en   = is_mem_access_valid & ahb_sel & (state == IDLE);
    assign req_fifo_wr_data = {addr_in, wdata_in, mem_write_in, mem_size_in};

    //=========================================================
    // 6b. PLIC Interface (synchronous, 1 cycle — không cần FSM/stall)
    //=========================================================
    assign plic_re    = is_mem_access_valid & plic_sel & mem_read_in;
    assign plic_we    = is_mem_access_valid & plic_sel & mem_write_in;
    assign plic_addr  = addr_in[23:0];
    assign plic_wdata = wdata_in;

    //=========================================================
    // 7. AHB Response FIFO
    // Pop FIFO ngay khi có phản hồi (trong AHB_WAIT)
    //=========================================================
    assign resp_fifo_rd_en = (state == AHB_WAIT) & ~resp_fifo_rd_empty;

    // Bóc tách FIFO response ngoài always để tránh lỗi Icarus
    logic [31:0] ahb_rdata;
    logic        ahb_resp_err;
    assign ahb_rdata    = resp_fifo_rd_data[31:0];
    assign ahb_resp_err = resp_fifo_rd_data[32];

    //=========================================================
    // 8. Read Data Output (Combinational từ bus response)
    // MEM1/MEM2 reg sẽ latch rdata_out ở cạnh lên khi bus_stall_req=0
    // Tại thời điểm đó rdata_out hợp lệ vì:
    //   - AXI: axi_resp_rdata ổn định khi axi_resp_valid=1
    //   - AHB: ahb_rdata từ FIFO combinational read, còn hợp lệ trước khi rd_ptr tăng
    //=========================================================
    always_comb begin
        rdata_out = 32'd0;
        if (state == AXI_WAIT && axi_resp_valid)
            rdata_out = axi_resp_rdata;
        else if (state == AHB_WAIT && !resp_fifo_rd_empty)
            rdata_out = ahb_rdata;
    end

    //=========================================================
    // 9. Fault Signals → Zicsr
    //=========================================================
    logic unmapped_fault, bus_err;
    // Unmapped fault: only on aligned accesses (misaligned takes exception priority)
    assign unmapped_fault = is_mem_access_valid & fault_sel & (state == IDLE);
    assign bus_err = (state == AXI_WAIT & axi_resp_valid & axi_resp_err) |
                     (state == AHB_WAIT & ~resp_fifo_rd_empty & ahb_resp_err);

    assign load_access_fault  = (unmapped_fault | bus_err) & mem_read_in;
    assign store_access_fault = (unmapped_fault | bus_err) & mem_write_in;

    // Misaligned exceptions (RV32I §2.6): mcause 4 (load) / 6 (store)
    assign load_misaligned_out  = is_mem_access & misaligned & mem_read_in;
    assign store_misaligned_out = is_mem_access & misaligned & mem_write_in;

    //=========================================================
    // 10. Pass-through → MEM1/MEM2 Register
    //=========================================================
    assign pc_out          = pc_in;
    assign alu_result_out  = addr_in;
    assign rs1_data_out    = rs1_data_in;
    assign imm_out         = imm_in;
    assign rd_addr_out     = rd_addr_in;
    assign csr_addr_out    = csr_addr_in;
    assign mem_ext_out     = mem_ext_in;
    assign mem_size_out    = mem_size_in;
    assign reg_write_out   = reg_write_in;
    assign wb_sel_out      = wb_sel_in;
    assign csr_we_out      = csr_we_in;
    assign csr_op_out      = csr_op_in;
    assign csr_imm_sel_out = csr_imm_sel_in;
    assign ecall_out       = ecall_in;
    assign ebreak_out      = ebreak_in;
    assign mret_out        = mret_in;
    assign illegal_instr_out = illegal_instr_in;

    // mem_src cho MEM2 biết lấy rdata từ nguồn nào
    // 2'b00=DMEM, 2'b01=AXI, 2'b10=AHB, 2'b11=PLIC
    assign mem_src_out = dmem_sel  ? 2'b00 :
                         axi_sel   ? 2'b01 :
                         ahb_sel   ? 2'b10 : 2'b11;

endmodule
