// PLIC — Platform-Level Interrupt Controller (simplified, 6 sources, 1 hart)
//
// Chuẩn tham chiếu: SiFive PLIC specification (riscv-plic-spec)
//
// Base address: 0x0C00_0000 (decode addr[31:24] == 8'h0C trong mem1_stage)
// Truy cập: đồng bộ 1GHz, 1-cycle read latency (tương tự DMEM — không cần stall)
//
// Source ID mapping (irq_src[5:0]):
//   irq_src[0] = source 1 = axi_S0 (1GHz, kết nối thẳng)
//   irq_src[1] = source 2 = axi_S1
//   irq_src[2] = source 3 = axi_S2
//   irq_src[3] = source 4 = ahb_S0 (đã qua 2-FF sync trong soc_top)
//   irq_src[4] = source 5 = ahb_S1
//   irq_src[5] = source 6 = ahb_S2
//
// Register map (addr[23:0] từ base):
//   0x000004  PRIORITY[1]  RW  3-bit, 0=disable, 1-7=level
//   0x000008  PRIORITY[2]  RW
//   0x00000C  PRIORITY[3]  RW
//   0x000010  PRIORITY[4]  RW
//   0x000014  PRIORITY[5]  RW
//   0x000018  PRIORITY[6]  RW
//   0x001000  PENDING      RO  bit[6:1]=pending flag từng source
//   0x002000  ENABLE       RW  bit[6:1]=enable mask
//   0x200000  THRESHOLD    RW  3-bit, chỉ forward nếu priority > threshold
//   0x200004  CLAIM        RO  đọc = ID winner hiện tại (0=không có)
//             COMPLETE     WO  ghi = source ID vừa xử lý xong (clear pending)
//
// Priority encoder: source có priority cao nhất thắng; tie-break: ID nhỏ hơn thắng
// Pending edge: set khi rising edge của irq_src, clear khi CPU ghi COMPLETE
//
// Icarus constraint: mọi constant part-select trích ra ngoài always bằng assign

module plic (
    input  logic        clk,
    input  logic        rst_n,

    //----------------- IRQ SOURCES (đã sync về 1GHz) -----------------
    // irq_src[0]=source1=axi_S0, ..., irq_src[5]=source6=ahb_S2(synced)
    input  logic [5:0]  irq_src,

    //----------------- CPU REGISTER ACCESS (1GHz, synchronous) -----------------
    input  logic        re,          // read enable (MEM1 cycle)
    input  logic        we,          // write enable (MEM1 cycle)
    input  logic [23:0] addr,        // register address trong PLIC space
    input  logic [31:0] wdata,       // write data
    output logic [31:0] rdata,       // read data (valid cycle sau — 1-cycle latency)

    //----------------- OUTPUT → ZICSR -----------------
    output logic        meip         // Machine External Interrupt Pending
);

    //=========================================================
    // 0. Register Address Localparams
    //=========================================================
    localparam [23:0] ADDR_PRI1  = 24'h000004;
    localparam [23:0] ADDR_PRI2  = 24'h000008;
    localparam [23:0] ADDR_PRI3  = 24'h00000C;
    localparam [23:0] ADDR_PRI4  = 24'h000010;
    localparam [23:0] ADDR_PRI5  = 24'h000014;
    localparam [23:0] ADDR_PRI6  = 24'h000018;
    localparam [23:0] ADDR_PEND  = 24'h001000;
    localparam [23:0] ADDR_ENA   = 24'h002000;
    localparam [23:0] ADDR_THOLD = 24'h200000;
    localparam [23:0] ADDR_CLAIM = 24'h200004;

    //=========================================================
    // 1. Register Declarations
    //=========================================================
    logic [2:0] reg_priority [1:6];  // unpacked, element-select safe in always_ff
    logic [6:1] reg_pending;         // packed [6:1]: bit[i] = pending source i
    logic [6:1] reg_enable;
    logic [2:0] reg_threshold;
    logic [5:0] irq_src_prev;        // để detect rising edge

    //=========================================================
    // 2. Pre-extract Signals (Icarus: không dùng part-select trong always_*)
    //=========================================================

    // wdata fields
    logic [2:0] wdata_2_0;
    logic [5:0] wdata_6_1;
    assign wdata_2_0 = wdata[2:0];   // ghi priority / threshold / complete ID
    assign wdata_6_1 = wdata[6:1];   // ghi enable

    // Priority values (element-select của unpacked array → assign an toàn)
    logic [2:0] pri1, pri2, pri3, pri4, pri5, pri6;
    assign pri1 = reg_priority[1];
    assign pri2 = reg_priority[2];
    assign pri3 = reg_priority[3];
    assign pri4 = reg_priority[4];
    assign pri5 = reg_priority[5];
    assign pri6 = reg_priority[6];

    // Rising edge detect: set pending khi irq_src lên 1 từ 0
    logic [5:0] irq_rising;
    assign irq_rising = irq_src & ~irq_src_prev;

    // pending_set[i] = rising edge của source i
    logic [6:1] pending_set;
    assign pending_set[1] = irq_rising[0];
    assign pending_set[2] = irq_rising[1];
    assign pending_set[3] = irq_rising[2];
    assign pending_set[4] = irq_rising[3];
    assign pending_set[5] = irq_rising[4];
    assign pending_set[6] = irq_rising[5];

    // Active: pending & enabled & priority > threshold
    logic [6:1] src_active;
    assign src_active[1] = reg_pending[1] & reg_enable[1] & (pri1 > reg_threshold);
    assign src_active[2] = reg_pending[2] & reg_enable[2] & (pri2 > reg_threshold);
    assign src_active[3] = reg_pending[3] & reg_enable[3] & (pri3 > reg_threshold);
    assign src_active[4] = reg_pending[4] & reg_enable[4] & (pri4 > reg_threshold);
    assign src_active[5] = reg_pending[5] & reg_enable[5] & (pri5 > reg_threshold);
    assign src_active[6] = reg_pending[6] & reg_enable[6] & (pri6 > reg_threshold);

    //=========================================================
    // 3. Complete Write → pending_clr (Combinational)
    //=========================================================
    logic [6:1] complete_clr;
    always_comb begin
        complete_clr = 6'd0;
        if (we && (addr == ADDR_CLAIM)) begin
            case (wdata_2_0)
                3'd1: complete_clr = 6'b000001;  // clear source 1
                3'd2: complete_clr = 6'b000010;
                3'd3: complete_clr = 6'b000100;
                3'd4: complete_clr = 6'b001000;
                3'd5: complete_clr = 6'b010000;
                3'd6: complete_clr = 6'b100000;  // clear source 6
                default: complete_clr = 6'd0;
            endcase
        end
    end

    //=========================================================
    // 4. Priority Encoder — Winner Selection (Combinational)
    // Duyệt từ source 1 → 6; chỉ thắng nếu priority STRICTLY cao hơn
    // → tie-break tự nhiên: source ID nhỏ hơn thắng (vì nó set winner_id trước)
    //=========================================================
    logic [2:0] winner_id;
    logic [2:0] win_pri;
    always_comb begin
        winner_id = 3'd0;
        win_pri   = 3'd0;
        if (src_active[1] && (pri1 > win_pri)) begin winner_id = 3'd1; win_pri = pri1; end
        if (src_active[2] && (pri2 > win_pri)) begin winner_id = 3'd2; win_pri = pri2; end
        if (src_active[3] && (pri3 > win_pri)) begin winner_id = 3'd3; win_pri = pri3; end
        if (src_active[4] && (pri4 > win_pri)) begin winner_id = 3'd4; win_pri = pri4; end
        if (src_active[5] && (pri5 > win_pri)) begin winner_id = 3'd5; win_pri = pri5; end
        if (src_active[6] && (pri6 > win_pri)) begin winner_id = 3'd6; win_pri = pri6; end
    end

    assign meip = (winner_id != 3'd0);

    //=========================================================
    // 5. Register Updates (Sequential)
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_priority[1] <= 3'd0;
            reg_priority[2] <= 3'd0;
            reg_priority[3] <= 3'd0;
            reg_priority[4] <= 3'd0;
            reg_priority[5] <= 3'd0;
            reg_priority[6] <= 3'd0;
            reg_pending     <= 6'd0;
            reg_enable      <= 6'd0;
            reg_threshold   <= 3'd0;
            irq_src_prev    <= 6'd0;
            rdata           <= 32'd0;
        end else begin
            // Track irq for next-cycle edge detect
            irq_src_prev <= irq_src;

            // Pending: OR in rising edges, AND-NOT complete clears
            // (rising edge and complete in same cycle: clear wins — acceptable tradeoff)
            reg_pending <= (reg_pending | pending_set) & ~complete_clr;

            // Register writes (COMPLETE handled via complete_clr above)
            if (we) begin
                case (addr)
                    ADDR_PRI1:  reg_priority[1] <= wdata_2_0;
                    ADDR_PRI2:  reg_priority[2] <= wdata_2_0;
                    ADDR_PRI3:  reg_priority[3] <= wdata_2_0;
                    ADDR_PRI4:  reg_priority[4] <= wdata_2_0;
                    ADDR_PRI5:  reg_priority[5] <= wdata_2_0;
                    ADDR_PRI6:  reg_priority[6] <= wdata_2_0;
                    ADDR_ENA:   reg_enable      <= wdata_6_1;
                    ADDR_THOLD: reg_threshold   <= wdata_2_0;
                    default: ;
                endcase
            end

            // Register reads (1-cycle latency: capture now, CPU reads result next cycle)
            if (re) begin
                case (addr)
                    ADDR_PRI1:  rdata <= {29'd0, pri1};
                    ADDR_PRI2:  rdata <= {29'd0, pri2};
                    ADDR_PRI3:  rdata <= {29'd0, pri3};
                    ADDR_PRI4:  rdata <= {29'd0, pri4};
                    ADDR_PRI5:  rdata <= {29'd0, pri5};
                    ADDR_PRI6:  rdata <= {29'd0, pri6};
                    ADDR_PEND:  rdata <= {25'd0, reg_pending,   1'b0};
                    ADDR_ENA:   rdata <= {25'd0, reg_enable,    1'b0};
                    ADDR_THOLD: rdata <= {29'd0, reg_threshold};
                    ADDR_CLAIM: rdata <= {29'd0, winner_id};
                    default:    rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
