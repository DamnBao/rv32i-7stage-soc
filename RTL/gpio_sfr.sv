// GPIO SFR — AXI-Lite Peripheral implementing the SFR Standard Register Map
//
// Demonstrates how to build a real peripheral on top of axi_sfr by wrapping it
// with GPIO-specific logic:
//
//   CTRL        = peripheral enable (generic, unused by GPIO logic)
//   STATUS      = gpio_in (bit0 = 2-FF sync'd; other bits = raw gpio_in)
//   INTR_ENABLE = unmask edge-detect interrupt source 0
//   INTR_STATE  = rising-edge detected on gpio_in[0] (W1C)
//   INTR_TEST   = force-set INTR_STATE for software testing
//   DATA0       = gpio output value (driven to gpio_out when DATA1[0]=1)
//   DATA1[0]    = output enable: 1 = drive gpio_out = DATA0; 0 = gpio_out = 0
//   PERIPH_ID   = 32'h4750_4900 ("GPIO")
//
// gpio_in[0] edge detect: 2-FF synchronizer + rising-edge pulse → irq_src
// gpio_out: combinational from reg_ctrl[0] and DATA0

module gpio_sfr (
    input  logic        clk,       // 1GHz (same as AXI bus)
    input  logic        rst_n,     // sync (rst_cpu_n from soc_top)

    // AXI-Lite Slave (connect to soc_top AXI slave port)
    input  logic [31:0] AWADDR,
    input  logic [2:0]  AWPROT,
    input  logic        AWVALID,
    output logic        AWREADY,
    input  logic [31:0] WDATA,
    input  logic [3:0]  WSTRB,
    input  logic        WVALID,
    output logic        WREADY,
    output logic [1:0]  BRESP,
    output logic        BVALID,
    input  logic        BREADY,
    input  logic [31:0] ARADDR,
    input  logic [2:0]  ARPROT,
    input  logic        ARVALID,
    output logic        ARREADY,
    output logic [31:0] RDATA,
    output logic [1:0]  RRESP,
    output logic        RVALID,
    input  logic        RREADY,

    // GPIO physical interface
    input  logic [31:0] gpio_in,   // sampled from pads
    output logic [31:0] gpio_out,  // to pads (drive-enable controlled externally)
    output logic        irq        // interrupt to CPU (via axi_interconnect)
);

    // 2-FF synchronizer for gpio_in[0] (crossing from I/O pad to 1GHz domain)
    logic gpio_in0;
    assign gpio_in0 = gpio_in[0];  // extract before always blocks

    logic gpio_s1, gpio_s2, gpio_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_s1   <= 1'b0;
            gpio_s2   <= 1'b0;
            gpio_prev <= 1'b0;
        end else begin
            gpio_s1   <= gpio_in0;
            gpio_s2   <= gpio_s1;
            gpio_prev <= gpio_s2;
        end
    end

    logic irq_src_pulse;
    assign irq_src_pulse = gpio_s2 & ~gpio_prev;  // rising edge

    // Internal data outputs from axi_sfr
    logic [31:0] data0_out_int, data1_out_int, data2_out_int;
    logic [31:0] ctrl_out_int;

    // STATUS register feeds gpio_in synchronizer output (all 32 bits with bit0 sync'd)
    // For simplicity: STATUS returns gpio_in with bit0 replaced by synchronized value
    logic [31:0] gpio_in_masked;
    logic [31:0] gpio_in_upper;
    assign gpio_in_upper  = gpio_in & 32'hFFFF_FFFE;  // clear bit0
    assign gpio_in_masked = gpio_in_upper | {31'd0, gpio_s2};  // bit0 = sync'd

    // Instantiate standard SFR core
    axi_sfr #(.PERIPH_ID_VAL(32'h4750_4900)) u_sfr (
        .clk        (clk),
        .rst_n      (rst_n),
        .AWADDR     (AWADDR),  .AWPROT (AWPROT),  .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA      (WDATA),   .WSTRB  (WSTRB),   .WVALID (WVALID),  .WREADY (WREADY),
        .BRESP      (BRESP),   .BVALID (BVALID),  .BREADY (BREADY),
        .ARADDR     (ARADDR),  .ARPROT (ARPROT),  .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA      (RDATA),   .RRESP  (RRESP),   .RVALID (RVALID),  .RREADY (RREADY),
        .status_in  (gpio_in_masked),
        .irq_src    (irq_src_pulse),
        .data0_out  (data0_out_int),
        .data1_out  (data1_out_int),
        .data2_out  (data2_out_int),
        .irq        (irq)
    );

    // GPIO output: CTRL[0] = output enable
    // We can't read reg_ctrl directly from axi_sfr, so we decode CTRL from DATA0 context.
    // gpio_sfr uses DATA0 as gpio output value; CTRL[0] as output enable.
    // axi_sfr's data0_out = DATA0 register value.
    // For CTRL, we need a separate register — read it from axi_sfr by noting that
    // axi_sfr exposes data0_out/data1_out/data2_out.  CTRL is internal to axi_sfr.
    // Solution: use DATA1[0] as output-enable flag visible externally.
    // data1_out_int[0] = 1 → enable gpio_out drive.
    logic gpio_oe;
    assign gpio_oe  = data1_out_int[0];
    assign gpio_out = gpio_oe ? data0_out_int : 32'd0;

endmodule
