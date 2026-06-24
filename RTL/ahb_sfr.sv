// AHB-Lite Slave SFR — Standard Register Map (OpenTitan-inspired)
//
// Register layout (HADDR[7:2] selects, word-aligned):
//   0x00  CTRL        RW     bit[0]=enable; bits[31:1]=peripheral-specific
//   0x04  STATUS      RO     driven by status_in (peripheral-supplied)
//   0x08  INTR_ENABLE RW     interrupt enable mask per source
//   0x0C  INTR_STATE  RW1C   pending flags; write 1 to clear
//   0x10  INTR_TEST   WO     write 1 to force-set INTR_STATE (debug/test)
//   0x14  DATA0       RW     general-purpose data 0
//   0x18  DATA1       RW     general-purpose data 1
//   0x1C  DATA2       RW     general-purpose data 2
//   0xFC  PERIPH_ID   RO     hardcoded peripheral identifier (parameter)
//
// IRQ: irq = |(INTR_STATE & INTR_ENABLE)
// irq_src: external event → sets INTR_STATE[0] each cycle it is high
// AHB HTRANS: only NONSEQ (2'b10) generates a transfer; IDLE/BUSY ignored.
// HRESP: always OKAY (1'b0)

module ahb_sfr #(
    parameter logic [31:0] PERIPH_ID_VAL = 32'h5346_5230
)(
    input  logic        clk_ahb,
    input  logic        rst_ahb_n,

    // AHB-Lite Slave
    input  logic        HSEL,
    input  logic        HREADY,      // HREADY from interconnect (input to slave)
    input  logic [31:0] HADDR,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,
    output logic [31:0] HRDATA,
    output logic        HREADYOUT,
    output logic        HRESP,

    // Peripheral interface
    input  logic [31:0] status_in,
    input  logic        irq_src,
    output logic [31:0] data0_out,
    output logic [31:0] data1_out,
    output logic [31:0] data2_out,
    output logic        irq
);

    localparam IDX_CTRL       = 6'h00;
    localparam IDX_STATUS     = 6'h01;
    localparam IDX_INTR_EN    = 6'h02;
    localparam IDX_INTR_STATE = 6'h03;
    localparam IDX_INTR_TEST  = 6'h04;
    localparam IDX_DATA0      = 6'h05;
    localparam IDX_DATA1      = 6'h06;
    localparam IDX_DATA2      = 6'h07;
    localparam IDX_PERIPH_ID  = 6'h3F;

    // Address-phase capture (Icarus-safe: bit-select outside always)
    logic [5:0] haddr_idx;
    assign haddr_idx = HADDR[7:2];

    // AHB is pipelined: capture address phase → drive data phase
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

    // irq_src as full-word mask (avoids bit-select inside always)
    logic [31:0] irq_src_set;
    assign irq_src_set = {31'd0, irq_src};

    // Registers
    logic [31:0] reg_ctrl;
    logic [31:0] reg_intr_enable;
    logic [31:0] reg_intr_state;
    logic [31:0] reg_data0;
    logic [31:0] reg_data1;
    logic [31:0] reg_data2;

    // Register write (data phase; last NBA wins for intr_state)
    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            reg_ctrl        <= 32'd0;
            reg_intr_enable <= 32'd0;
            reg_intr_state  <= 32'd0;
            reg_data0       <= 32'd0;
            reg_data1       <= 32'd0;
            reg_data2       <= 32'd0;
        end else begin
            reg_intr_state <= reg_intr_state | irq_src_set;
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

    // Read mux (combinational on addr_ph_idx captured last cycle)
    logic [31:0] rd_data_mux;
    always_comb begin
        case (addr_ph_idx)
            IDX_CTRL:       rd_data_mux = reg_ctrl;
            IDX_STATUS:     rd_data_mux = status_in;
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

    assign data0_out = reg_data0;
    assign data1_out = reg_data1;
    assign data2_out = reg_data2;

    logic [31:0] intr_masked;
    assign intr_masked = reg_intr_state & reg_intr_enable;
    assign irq = |intr_masked;

endmodule
