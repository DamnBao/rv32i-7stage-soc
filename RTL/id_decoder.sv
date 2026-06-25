// ID Decoder — combinational decode of a 32-bit RV32I+Zicsr instruction.
//
// All bit-field extractions are done via assign outside always_* to satisfy
// Icarus Verilog's restriction on constant part-selects inside always blocks.
//
// alu_op encoding: must stay in sync with alu.sv localparams.
// wb_sel encoding: 2'b00=ALU result, 01=memory rdata, 10=PC+4, 11=CSR rdata.
// csr_op encoding: 2'b01=CSRRW, 10=CSRRS, 11=CSRRC.

module id_decoder (
    input  logic [31:0] instr,

    // Register indices
    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic [4:0]  rd_addr,
    output logic [11:0] csr_addr,    // CSR address for Zicsr instructions
    output logic [2:0]  funct3,
    output logic [31:0] imm,         // Sign-extended immediate (type selected by opcode)

    // ALU control
    output logic [3:0]  alu_op,
    output logic        alu_src_a,   // 0=rs1, 1=PC
    output logic        alu_src_b,   // 0=rs2, 1=imm

    // Branch / jump
    output logic        branch,      // 1 if B-type
    output logic        jump,        // 1 if JAL or JALR
    output logic        jump_reg,    // 1 if JALR (register-relative)

    // Memory access
    output logic        mem_read,
    output logic        mem_write,
    output logic [1:0]  mem_size,    // 00=byte, 01=half, 10=word
    output logic        mem_ext,     // 0=zero-extend, 1=sign-extend

    // Write-back
    output logic        reg_write,
    output logic [1:0]  wb_sel,      // 00=ALU, 01=MEM, 10=PC+4, 11=CSR

    // CSR
    output logic        csr_we,
    output logic [1:0]  csr_op,      // 01=RW, 10=RS, 11=RC
    output logic        csr_imm_sel, // 0=use rs1, 1=use zimm (CSRRWI/CSRRSI/CSRRCI)

    // Exceptions
    output logic        ecall,
    output logic        ebreak,
    output logic        mret,
    output logic        illegal_instr
);

    // Định nghĩa các phép toán ALU
    localparam ALU_ADD   = 4'd0;
    localparam ALU_SUB   = 4'd1;
    localparam ALU_SLL   = 4'd2;
    localparam ALU_SLT   = 4'd3;
    localparam ALU_SLTU  = 4'd4;
    localparam ALU_XOR   = 4'd5;
    localparam ALU_SRL   = 4'd6;
    localparam ALU_SRA   = 4'd7;
    localparam ALU_OR    = 4'd8;
    localparam ALU_AND   = 4'd9;
    localparam ALU_PASSB = 4'd10;

    // Bóc tách cơ bản (Thực hiện bên ngoài always_comb)
    logic [6:0] opcode;
    logic [6:0] funct7;
    logic [1:0] instr_13_12; // Dùng để thay thế instr[13:12]
    logic       instr_14;    // Dùng để thay thế instr[14]
    
    assign opcode      = instr[6:0];
    assign funct3      = instr[14:12];
    assign funct7      = instr[31:25];
    assign rs1_addr    = instr[19:15];
    assign rs2_addr    = instr[24:20];
    assign rd_addr     = instr[11:7];
    assign csr_addr    = instr[31:20];
    assign instr_13_12 = instr[13:12];
    assign instr_14    = instr[14];

    // Trích xuất Immediate
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j, imm_z;
    assign imm_i = {{20{instr[31]}}, instr[31:20]}; 
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {instr[31:12], 12'd0};
    assign imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
    assign imm_z = {27'd0, instr[19:15]};

    always_comb begin
        // Khởi tạo mặc định
        imm           = 32'd0;
        alu_op        = ALU_ADD;
        alu_src_a     = 1'b0;
        alu_src_b     = 1'b0;
        branch        = 1'b0;
        jump          = 1'b0;
        jump_reg      = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        mem_size      = 2'b10;
        mem_ext       = 1'b0;
        reg_write     = 1'b0;
        wb_sel        = 2'b00;
        csr_we        = 1'b0;
        csr_op        = 2'b00;
        csr_imm_sel   = 1'b0;
        ecall         = 1'b0;
        ebreak        = 1'b0;
        mret          = 1'b0;
        illegal_instr = 1'b0;
        
        case (opcode)
            7'b0110111: begin // LUI
                imm       = imm_u;
                alu_src_b = 1'b1;
                alu_op    = ALU_PASSB;
                reg_write = 1'b1;
                wb_sel    = 2'b00;
            end
            
            7'b0010111: begin // AUIPC
                imm       = imm_u;
                alu_src_a = 1'b1;
                alu_src_b = 1'b1;
                alu_op    = ALU_ADD;
                reg_write = 1'b1;
                wb_sel    = 2'b00;
            end
            
            7'b1101111: begin // JAL
                imm       = imm_j;
                jump      = 1'b1;
                reg_write = 1'b1;
                wb_sel    = 2'b10;
            end
            
            7'b1100111: begin // JALR
                imm       = imm_i;
                jump      = 1'b1;
                jump_reg  = 1'b1;
                reg_write = 1'b1;
                wb_sel    = 2'b10;
                if (funct3 != 3'b000) illegal_instr = 1'b1;
            end
            
            7'b1100011: begin // BRANCH
                imm       = imm_b;
                branch    = 1'b1;
                if (funct3 == 3'b010 || funct3 == 3'b011) illegal_instr = 1'b1;
            end
            
            7'b0000011: begin // LOAD
                imm       = imm_i;
                alu_src_b = 1'b1; 
                mem_read  = 1'b1;
                reg_write = 1'b1;
                wb_sel    = 2'b01;
                mem_size  = instr_13_12; // Sử dụng biến tổng thể thay vì part-select
                mem_ext   = ~instr_14;   // Sử dụng biến tổng thể thay vì bit-select
                if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) illegal_instr = 1'b1;
            end
            
            7'b0100011: begin // STORE
                imm       = imm_s;
                alu_src_b = 1'b1; 
                mem_write = 1'b1;
                mem_size  = instr_13_12; // Sử dụng biến tổng thể
                if (funct3 > 3'b010) illegal_instr = 1'b1;
            end
            
            7'b0010011: begin // OP-IMM
                imm       = imm_i;
                alu_src_b = 1'b1;
                reg_write = 1'b1;
                wb_sel    = 2'b00;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    3'b001: begin
                        alu_op = ALU_SLL;
                        if (funct7 != 7'b0000000) illegal_instr = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = ALU_SRA;
                        else illegal_instr = 1'b1;
                    end
                endcase
            end
            
            7'b0110011: begin // OP
                reg_write = 1'b1;
                wb_sel    = 2'b00;
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_ADD;
                        else if (funct7 == 7'b0100000) alu_op = ALU_SUB;
                        else illegal_instr = 1'b1;
                    end
                    3'b001: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SLL;
                        else illegal_instr = 1'b1;
                    end
                    3'b010: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SLT;
                        else illegal_instr = 1'b1;
                    end
                    3'b011: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SLTU;
                        else illegal_instr = 1'b1;
                    end
                    3'b100: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_XOR;
                        else illegal_instr = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = ALU_SRA;
                        else illegal_instr = 1'b1;
                    end
                    3'b110: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_OR;
                        else illegal_instr = 1'b1;
                    end
                    3'b111: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_AND;
                        else illegal_instr = 1'b1;
                    end
                endcase
            end
            
            7'b0001111: begin // FENCE
            end
            
            7'b1110011: begin // SYSTEM
                if (funct3 == 3'b000) begin
                    // Sử dụng csr_addr đã khai báo bên ngoài thay vì instr[31:20]
                    if (csr_addr == 12'h000) ecall = 1'b1;
                    else if (csr_addr == 12'h001) ebreak = 1'b1;
                    else if (csr_addr == 12'h302) mret = 1'b1;
                    else illegal_instr = 1'b1;
                end else begin
                    csr_we    = 1'b1;
                    wb_sel    = 2'b11;
                    reg_write = 1'b1;
                    
                    if (instr_14) begin // Sử dụng biến tổng thể
                        imm = imm_z;
                        csr_imm_sel = 1'b1;
                    end
                    
                    case (instr_13_12) // Sử dụng biến tổng thể
                        2'b01: csr_op = 2'b01; // RW — always write
                        2'b10: begin // RS — skip write if source==0 (spec §9.1)
                            csr_op = 2'b10;
                            if (rs1_addr == 5'd0) csr_we = 1'b0;
                        end
                        2'b11: begin // RC — skip write if source==0 (spec §9.1)
                            csr_op = 2'b11;
                            if (rs1_addr == 5'd0) csr_we = 1'b0;
                        end
                        default: illegal_instr = 1'b1;
                    endcase
                end
            end
            
            default: illegal_instr = 1'b1;
        endcase
    end
endmodule
