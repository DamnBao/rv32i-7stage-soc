// GPIO AHB — AHB-Lite GPIO peripheral, Standard SFR Register Map
//
// Register layout (HADDR[7:2] index):
//   0x00  CTRL        RW   (general; not used by GPIO logic)
//   0x04  STATUS      RO   current gpio_in value (synchronized, read-only)
//   0x08  INTR_ENABLE RW   [0]=enable edge-detect IRQ on gpio_in[0]
//   0x0C  INTR_STATE  RW1C [0]=edge detected on gpio_in[0] (W1C to clear)
//   0x10  INTR_TEST   WO   write 1 to force-set INTR_STATE[0] (software test)
//   0x14  DATA0       RW   gpio_out value (driven to pads when DATA1[0]=1)
//   0x18  DATA1       RW   [0]=output enable: 1=drive gpio_out, 0=gpio_out=0
//   0x1C  DATA2       RW   [0]=edge type select: 0=rising, 1=falling on gpio_in[0]
//   0xFC  PERIPH_ID   RO   0x47504941 ("GPIA")
//
// GPIO behavior:
//   gpio_out = DATA1[0] ? DATA0 : 0          (output enable via DATA1[0])
//   STATUS   = sync'd gpio_in (2-FF synchronizer for metastability)
//   Edge detect on gpio_in[0]: rising (DATA2[0]=0) or falling (DATA2[0]=1)
//   irq_src: one-cycle pulse when selected edge is detected → INTR_STATE[0]=1
//
// IRQ: irq = INTR_STATE[0] & INTR_ENABLE[0]
// PERIPH_ID: 0x47504941 (ASCII "GPIA")

`timescale 1ns/1ps

module gpio_ahb #(
    parameter logic [31:0] PERIPH_ID_VAL = 32'h4750_4941
)(
    input  logic        clk_ahb,
    input  logic        rst_ahb_n,

    // AHB-Lite Slave
    input  logic        HSEL,
    input  logic        HREADY,
    input  logic [31:0] HADDR,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,
    output logic [31:0] HRDATA,
    output logic        HREADYOUT,
    output logic        HRESP,

    // GPIO physical interface
    input  logic [31:0] gpio_in,    // sampled from pads
    output logic [31:0] gpio_out,   // to pads (drive-enable via DATA1[0])
    output logic        irq
);
    localparam IDX_CTRL       = 6'h00;
    localparam IDX_STATUS     = 6'h01;
    localparam IDX_INTR_EN    = 6'h02;
    localparam IDX_INTR_STATE = 6'h03;
    localparam IDX_INTR_TEST  = 6'h04;
    localparam IDX_DATA0      = 6'h05;  // gpio_out value
    localparam IDX_DATA1      = 6'h06;  // output enable
    localparam IDX_DATA2      = 6'h07;  // edge type select
    localparam IDX_PERIPH_ID  = 6'h3F;

    // ── AHB address-phase capture ──────────────────────────────────
    logic [5:0] haddr_idx;
    assign haddr_idx = HADDR[7:2];

    logic       addr_ph_valid;
    logic       addr_ph_write;
    logic [5:0] addr_ph_idx;

    logic active_transfer;
    assign active_transfer = HSEL && HREADY && (HTRANS == 2'b10);

    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            addr_ph_valid <= 1'b0;
            addr_ph_write <= 1'b0;
            addr_ph_idx   <= 6'd0;
        end else begin
            addr_ph_valid <= active_transfer;
            addr_ph_write <= HWRITE;
            addr_ph_idx   <= haddr_idx;
        end
    end

    // ── 2-FF synchronizer for gpio_in ─────────────────────────────
    // Prevents metastability when gpio_in comes from an async or pad domain
    logic [31:0] gpio_s1, gpio_s2, gpio_prev;
    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            gpio_s1   <= 32'd0;
            gpio_s2   <= 32'd0;
            gpio_prev <= 32'd0;
        end else begin
            gpio_s1   <= gpio_in;
            gpio_s2   <= gpio_s1;
            gpio_prev <= gpio_s2;
        end
    end

    // ── Edge detection on gpio_in[0] ──────────────────────────────
    // Bit-selects extracted outside always (Icarus rule)
    logic gpio_s2_0, gpio_prev_0;
    assign gpio_s2_0   = gpio_s2[0];
    assign gpio_prev_0 = gpio_prev[0];

    // edge_type_sel from DATA2[0]: captured below once reg_data2 is declared
    // Rising: s2=1 & prev=0; Falling: s2=0 & prev=1
    logic rising_0, falling_0;
    assign rising_0  = gpio_s2_0 & ~gpio_prev_0;
    assign falling_0 = ~gpio_s2_0 & gpio_prev_0;

    // ── SFR Registers ─────────────────────────────────────────────
    logic [31:0] reg_ctrl;
    logic [31:0] reg_intr_enable;
    logic [31:0] reg_intr_state;
    logic [31:0] reg_data0;   // gpio_out value
    logic [31:0] reg_data1;   // output enable
    logic [31:0] reg_data2;   // edge type select

    // Edge type and irq_src extracted (outside always per Icarus rule)
    logic edge_type_0;
    assign edge_type_0 = reg_data2[0];

    logic irq_src_w;
    assign irq_src_w = edge_type_0 ? falling_0 : rising_0;

    logic [31:0] irq_src_set;
    assign irq_src_set = {31'd0, irq_src_w};

    // ── SFR Register write ─────────────────────────────────────────
    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            reg_ctrl        <= 32'd0;
            reg_intr_enable <= 32'd0;
            reg_intr_state  <= 32'd0;
            reg_data0       <= 32'd0;
            reg_data1       <= 32'd0;
            reg_data2       <= 32'd0;
        end else begin
            // Accumulate edge-detect event into INTR_STATE[0]
            reg_intr_state <= reg_intr_state | irq_src_set;
            // Bus write (data phase; last NBA wins for intr_state)
            if (addr_ph_valid && addr_ph_write) begin
                case (addr_ph_idx)
                    IDX_CTRL:
                        reg_ctrl <= HWDATA;
                    IDX_INTR_EN:
                        reg_intr_enable <= HWDATA;
                    IDX_INTR_STATE:
                        reg_intr_state <= (reg_intr_state | irq_src_set) & ~HWDATA;
                    IDX_INTR_TEST:
                        reg_intr_state <= reg_intr_state | irq_src_set | HWDATA;
                    IDX_DATA0:
                        reg_data0 <= HWDATA;
                    IDX_DATA1:
                        reg_data1 <= HWDATA;
                    IDX_DATA2:
                        reg_data2 <= HWDATA;
                    default: ;
                endcase
            end
        end
    end

    // ── Read mux (combinational on captured addr_ph_idx) ──────────
    logic [31:0] rd_data_mux;
    always_comb begin
        case (addr_ph_idx)
            IDX_CTRL:       rd_data_mux = reg_ctrl;
            IDX_STATUS:     rd_data_mux = gpio_s2;       // sync'd gpio_in (read-only)
            IDX_INTR_EN:    rd_data_mux = reg_intr_enable;
            IDX_INTR_STATE: rd_data_mux = reg_intr_state;
            IDX_DATA0:      rd_data_mux = reg_data0;
            IDX_DATA1:      rd_data_mux = reg_data1;
            IDX_DATA2:      rd_data_mux = reg_data2;
            IDX_PERIPH_ID:  rd_data_mux = PERIPH_ID_VAL;
            default:        rd_data_mux = 32'd0;
        endcase
    end

    assign HRDATA    = rd_data_mux;
    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0;

    // gpio_out: driven when DATA1[0]=1 (output enable)
    logic gpio_oe;
    assign gpio_oe  = reg_data1[0];
    assign gpio_out = gpio_oe ? reg_data0 : 32'd0;

    logic [31:0] intr_masked;
    assign intr_masked = reg_intr_state & reg_intr_enable;
    assign irq = |intr_masked;

endmodule
