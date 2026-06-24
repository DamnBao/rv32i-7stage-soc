// AHB-Lite Slave SFR (500MHz domain)
//
// Generic SFR peripheral với 8 × 32-bit registers.
// Reg address: HADDR[4:2] (3 bit → 8 word registers, offset 0x00..0x1C)
//
// AHB-Lite slave protocol (0-wait state, HREADYOUT=1 always):
//   Address phase (cycle N): HSEL=1, HTRANS=NONSEQ, HADDR, HWRITE sampled when HREADY=1
//   Data phase (cycle N+1): Write → sfr_reg[reg_idx] ← HWDATA (rising edge N+1)
//                           Read  → HRDATA = sfr_reg[reg_idx] (combinational)
//
// Register map:
//   Offset 0x00 (REG0): Control register
//   Offset 0x04 (REG1): Status register
//   Offset 0x08..0x18: General-purpose
//   Offset 0x1C (REG7): IRQ register — REG7[0]=1 → assert irq output
//
// IRQ: sfr_reg[7][0] (software-settable, cleared by writing 0)
// HRESP: 0 (OKAY) always

module ahb_sfr (
    input  logic        clk_ahb,
    input  logic        rst_ahb_n,

    //----------------- AHB-LITE SLAVE -----------------
    input  logic        HSEL,
    input  logic        HREADY,     // Global HREADY từ interconnect
    input  logic [31:0] HADDR,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,
    output logic [31:0] HRDATA,
    output logic        HREADYOUT,  // Luôn = 1 (0-wait state)
    output logic        HRESP,      // Luôn = 0 (OKAY)

    //----------------- IRQ -----------------
    output logic        irq         // = sfr_reg[7][0]
);

    //=========================================================
    // 1. Pre-extract (Icarus-safe constant part-selects)
    //=========================================================
    logic [2:0] haddr_4_2;
    assign haddr_4_2 = HADDR[4:2];   // Register index trong address phase

    logic htrans_valid;
    assign htrans_valid = HTRANS[1];  // NONSEQ or SEQ

    //=========================================================
    // 2. Register Address-phase Info
    //    Latch khi HSEL=1, HTRANS valid, HREADY=1 (address phase OK)
    //=========================================================
    logic [2:0] reg_idx;        // Registered register index (data phase)
    logic       reg_write_en;   // Registered write enable (data phase)

    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            reg_idx      <= 3'd0;
            reg_write_en <= 1'b0;
        end else if (HREADY) begin
            reg_idx      <= haddr_4_2;
            reg_write_en <= HSEL & htrans_valid & HWRITE;
        end
    end

    //=========================================================
    // 3. SFR Register File (8 × 32-bit)
    //=========================================================
    logic [31:0] sfr_reg [0:7];

    integer i;
    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            for (i = 0; i < 8; i = i + 1)
                sfr_reg[i] <= 32'd0;
        end else if (reg_write_en) begin
            sfr_reg[reg_idx] <= HWDATA;
        end
    end

    //=========================================================
    // 4. Read Data (Combinational, data phase)
    //=========================================================
    assign HRDATA = sfr_reg[reg_idx];

    //=========================================================
    // 5. Fixed responses
    //=========================================================
    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0;

    //=========================================================
    // 6. IRQ (bóc tách bên ngoài để tránh Icarus issue)
    //=========================================================
    logic sfr7_bit0;
    assign sfr7_bit0 = sfr_reg[7][0];
    assign irq = sfr7_bit0;

endmodule
