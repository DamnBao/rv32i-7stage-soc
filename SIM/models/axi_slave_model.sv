`timescale 1ns/1ps
// AXI-Lite slave model: 8×32-bit registers, immediate handshakes, error injection
module axi_slave_model (
    input  logic        clk,
    input  logic        rst_n,
    // Write address
    input  logic [31:0] AWADDR,
    input  logic        AWVALID,
    output logic        AWREADY,
    // Write data
    input  logic [31:0] WDATA,
    input  logic [3:0]  WSTRB,
    input  logic        WVALID,
    output logic        WREADY,
    // Write response
    output logic [1:0]  BRESP,
    output logic        BVALID,
    input  logic        BREADY,
    // Read address
    input  logic [31:0] ARADDR,
    input  logic        ARVALID,
    output logic        ARREADY,
    // Read data
    output logic [31:0] RDATA,
    output logic [1:0]  RRESP,
    output logic        RVALID,
    input  logic        RREADY,
    // Error injection
    input  logic        inject_bresp_err,
    input  logic        inject_rresp_err
);
    logic [31:0] mem [0:7];
    logic [2:0] wr_idx, rd_idx;
    assign wr_idx = AWADDR[4:2];
    assign rd_idx = ARADDR[4:2];

    // Byte-enable mask
    logic [31:0] be_mask;
    assign be_mask = {{8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}}};

    // Immediate accepts
    assign AWREADY = 1'b1;
    assign WREADY  = 1'b1;
    assign ARREADY = 1'b1;

    integer k;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            BVALID <= 1'b0;  BRESP <= 2'b00;
            RVALID <= 1'b0;  RDATA <= 32'd0;  RRESP <= 2'b00;
            for (k = 0; k < 8; k = k + 1) mem[k] <= 32'd0;
        end else begin
            // Write: AW + W both arrive simultaneously from axi_interface
            if (AWVALID && WVALID) begin
                mem[wr_idx] <= (WDATA & be_mask) | (mem[wr_idx] & ~be_mask);
                BVALID <= 1'b1;
                BRESP  <= inject_bresp_err ? 2'b10 : 2'b00;
            end
            if (BVALID && BREADY) BVALID <= 1'b0;

            // Read: latch data one cycle after AR handshake
            if (ARVALID) begin
                RDATA  <= mem[rd_idx];
                RRESP  <= inject_rresp_err ? 2'b10 : 2'b00;
                RVALID <= 1'b1;
            end
            if (RVALID && RREADY) RVALID <= 1'b0;
        end
    end
endmodule
