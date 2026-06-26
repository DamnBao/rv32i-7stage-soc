// AXI-Lite Master Interface (1GHz domain)
//
// Dịch giao thức req/resp từ CPU (mem1_stage) sang AXI4-Lite 5-channel.
//
// CPU side:
//   axi_req_valid: giữ HIGH suốt transaction (từ IDLE đến AXI_WAIT trong mem1_stage)
//   axi_req_we:    0=Read, 1=Write
//   axi_req_wdata: raw rs2_data (byte/half data right-aligned ở [7:0] / [15:0])
//   axi_req_size:  00=byte, 01=half, 10=word
//   axi_resp_valid: 1 khi transaction hoàn thành
//
// Write WSTRB + WDATA alignment:
//   CPU truyền data right-aligned, interface shift + set WSTRB theo size và addr[1:0]
//
// Timing (không pipeline, 1 transaction mỗi lần):
//   Read:  IDLE→RD_ADDR→RD_DATA (AR accepted→R received)
//   Write: IDLE→WR_PHASE (AW+W)→WR_RESP (B received)
//
// Icarus: mọi constant part-select bóc tách ngoài always

module axi_interface (
    input  logic        clk,
    input  logic        rst_n,

    //----------------- CPU REQUEST / RESPONSE -----------------
    input  logic        axi_req_valid,
    input  logic [31:0] axi_req_addr,
    input  logic        axi_req_we,
    input  logic [31:0] axi_req_wdata,
    input  logic [1:0]  axi_req_size,
    output logic        axi_resp_valid,
    output logic [31:0] axi_resp_rdata,
    output logic        axi_resp_err,

    //----------------- AXI4-LITE MASTER (ra interconnect) -----------------
    // Write address channel
    output logic [31:0] AWADDR,
    output logic [2:0]  AWPROT,
    output logic        AWVALID,
    input  logic        AWREADY,

    // Write data channel
    output logic [31:0] WDATA,
    output logic [3:0]  WSTRB,
    output logic        WVALID,
    input  logic        WREADY,

    // Write response channel
    input  logic [1:0]  BRESP,
    input  logic        BVALID,
    output logic        BREADY,

    // Read address channel
    output logic [31:0] ARADDR,
    output logic [2:0]  ARPROT,
    output logic        ARVALID,
    input  logic        ARREADY,

    // Read data channel
    input  logic [31:0] RDATA,
    input  logic [1:0]  RRESP,
    input  logic        RVALID,
    output logic        RREADY
);

    //=========================================================
    // FSM States
    //=========================================================
    localparam IDLE     = 3'd0;
    localparam RD_ADDR  = 3'd1;  // Waiting for ARREADY
    localparam RD_DATA  = 3'd2;  // Waiting for RVALID
    localparam WR_PHASE = 3'd3;  // Waiting for AW+W handshakes
    localparam WR_RESP  = 3'd4;  // Waiting for BVALID

    logic [2:0] state;
    logic aw_done, w_done;    // Track AW/W channel completion in WR_PHASE

    //=========================================================
    // Registered request info (latched khi rời IDLE)
    //=========================================================
    logic [31:0] addr_r, wdata_r;
    logic [1:0]  size_r;

    //=========================================================
    // Pre-extract addr fields (Icarus-safe)
    //=========================================================
    logic [1:0] addr_r_10;   // byte offset [1:0]
    logic       addr_r_1;    // half offset [1]
    assign addr_r_10 = addr_r[1:0];
    assign addr_r_1  = addr_r[1];

    //=========================================================
    // WDATA alignment + WSTRB (Combinational từ registered request)
    //=========================================================
    logic [7:0]  wdata_byte;
    logic [15:0] wdata_half;
    assign wdata_byte = wdata_r[7:0];
    assign wdata_half = wdata_r[15:0];

    logic [31:0] wdata_aligned;
    logic [3:0]  wstrb_out;

    always_comb begin
        case (size_r)
            2'b10: begin  // Word
                wdata_aligned = wdata_r;
                wstrb_out     = 4'b1111;
            end
            2'b01: begin  // Half-word
                wdata_aligned = {wdata_half, wdata_half};
                wstrb_out     = addr_r_1 ? 4'b1100 : 4'b0011;
            end
            default: begin  // Byte
                wdata_aligned = {wdata_byte, wdata_byte, wdata_byte, wdata_byte};
                wstrb_out     = 4'b0001 << addr_r_10;
            end
        endcase
    end

    //=========================================================
    // Combinational "both channels done" check (WR_PHASE)
    //=========================================================
    logic aw_handshake, w_handshake;
    assign aw_handshake = AWVALID && AWREADY;
    assign w_handshake  = WVALID  && WREADY;

    logic both_done;
    assign both_done = (aw_done || aw_handshake) && (w_done || w_handshake);

    //=========================================================
    // FSM Register
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            addr_r  <= 32'd0;
            wdata_r <= 32'd0;
            size_r  <= 2'b10;
            aw_done <= 1'b0;
            w_done  <= 1'b0;

        end else begin
            case (state)
                IDLE: begin
                    if (axi_req_valid) begin
                        addr_r  <= axi_req_addr;
                        wdata_r <= axi_req_wdata;
                        size_r  <= axi_req_size;
                        aw_done <= 1'b0;
                        w_done  <= 1'b0;
                        if (axi_req_we) state <= WR_PHASE;
                        else            state <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (ARREADY) state <= RD_DATA;
                end

                RD_DATA: begin
                    if (RVALID) state <= IDLE;
                end

                WR_PHASE: begin
                    if (aw_handshake) aw_done <= 1'b1;
                    if (w_handshake)  w_done  <= 1'b1;
                    if (both_done)    state   <= WR_RESP;
                end

                WR_RESP: begin
                    if (BVALID) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    //=========================================================
    // AXI Channel Outputs
    //=========================================================
    // Read address channel
    assign ARVALID = (state == RD_ADDR);
    assign ARADDR  = addr_r;
    assign ARPROT  = 3'b000;

    // Read data channel
    assign RREADY = (state == RD_DATA);

    // Write address channel
    assign AWVALID = (state == WR_PHASE) && !aw_done;
    assign AWADDR  = addr_r;
    assign AWPROT  = 3'b000;

    // Write data channel
    assign WVALID = (state == WR_PHASE) && !w_done;
    assign WDATA  = wdata_aligned;
    assign WSTRB  = wstrb_out;

    // Write response channel
    assign BREADY = (state == WR_RESP);

    //=========================================================
    // CPU Response Outputs (Combinational)
    //=========================================================
    logic rresp_err, bresp_err;
    assign rresp_err = (RRESP != 2'b00);
    assign bresp_err = (BRESP != 2'b00);

    assign axi_resp_valid = ((state == RD_DATA) && RVALID) ||
                            ((state == WR_RESP) && BVALID);
    assign axi_resp_rdata = RDATA;
    assign axi_resp_err   = ((state == RD_DATA) && RVALID && rresp_err) ||
                            ((state == WR_RESP) && BVALID && bresp_err);

endmodule
