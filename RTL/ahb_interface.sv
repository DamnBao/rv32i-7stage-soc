// AHB-Lite Master Interface (500MHz domain)
//
// Đọc request từ Request FIFO (CPU→AHB CDC), thực hiện AHB-Lite transaction,
// ghi kết quả vào Response FIFO (AHB→CPU CDC).
//
// Request FIFO payload (67-bit): [66:35]=addr, [34:3]=wdata, [2]=write, [1:0]=size
// Response FIFO payload (33-bit): [32]=HRESP_err, [31:0]=HRDATA
//
// AHB-Lite timing (non-pipelined):
//   Cycle N (IDLE_ST + request): Address phase — HTRANS=NONSEQ, HADDR, HWRITE, HSIZE
//   Cycle N+1 (DATA_ST): Data phase — HWDATA stable, wait HREADY
//   When HREADY=1: capture HRDATA/HRESP, push to response FIFO
//
// Không có back-to-back pipelining — luôn quay về IDLE giữa các transaction.

module ahb_interface (
    input  logic        clk_ahb,    // 500MHz
    input  logic        rst_ahb_n,  // Đã đồng bộ về 500MHz domain

    //----------------- REQUEST FIFO (500MHz read side) -----------------
    input  logic        req_empty,
    output logic        req_rd_en,
    input  logic [66:0] req_rd_data,  // {addr(32), wdata(32), write(1), size(2)}

    //----------------- RESPONSE FIFO (500MHz write side) -----------------
    output logic        resp_wr_en,
    output logic [32:0] resp_wr_data, // {HRESP(1), HRDATA(32)}

    //----------------- AHB-LITE MASTER -----------------
    output logic [31:0] HADDR,
    output logic [2:0]  HSIZE,
    output logic [1:0]  HTRANS,
    output logic        HWRITE,
    output logic [31:0] HWDATA,
    input  logic        HREADY,
    input  logic [31:0] HRDATA,
    input  logic        HRESP    // 0=OKAY, 1=ERROR
);

    localparam IDLE_ST = 1'b0;
    localparam DATA_ST = 1'b1;

    logic state;

    //=========================================================
    // Pre-extract FIFO fields (Icarus-safe constant part-selects)
    //=========================================================
    logic [31:0] req_addr;
    logic [31:0] req_wdata;
    logic        req_write;
    logic [1:0]  req_size;
    assign req_addr  = req_rd_data[66:35];
    assign req_wdata = req_rd_data[34:3];
    assign req_write = req_rd_data[2];
    assign req_size  = req_rd_data[1:0];

    //=========================================================
    // Registered address-phase info (held stable during data phase)
    //=========================================================
    logic [31:0] haddr_reg, hwdata_reg;
    logic        hwrite_reg;
    logic [1:0]  hsize_reg;

    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            state      <= IDLE_ST;
            haddr_reg  <= 32'd0;
            hwdata_reg <= 32'd0;
            hwrite_reg <= 1'b0;
            hsize_reg  <= 2'b00;
        end else begin
            case (state)
                IDLE_ST: begin
                    if (!req_empty) begin
                        // Latch request từ FIFO cho data phase tiếp theo
                        haddr_reg  <= req_addr;
                        hwdata_reg <= req_wdata;
                        hwrite_reg <= req_write;
                        hsize_reg  <= req_size;
                        state      <= DATA_ST;
                    end
                end
                DATA_ST: begin
                    if (HREADY)
                        state <= IDLE_ST;
                end
                default: state <= IDLE_ST;
            endcase
        end
    end

    //=========================================================
    // FIFO read enable: pop khi thấy request ở IDLE
    //=========================================================
    assign req_rd_en = (state == IDLE_ST) && !req_empty;

    //=========================================================
    // AHB Address-phase: HADDR combinational trong IDLE (từ FIFO),
    // chuyển sang registered khi vào DATA (stable)
    //=========================================================
    logic in_idle_with_req;
    assign in_idle_with_req = (state == IDLE_ST) && !req_empty;

    assign HADDR  = in_idle_with_req ? req_addr  : haddr_reg;
    assign HWRITE = in_idle_with_req ? req_write : hwrite_reg;
    assign HSIZE  = in_idle_with_req ? {1'b0, req_size}  : {1'b0, hsize_reg};

    // HTRANS: NONSEQ trong address phase (IDLE + request), IDLE trong data phase
    always_comb begin
        if      (state == IDLE_ST && !req_empty) HTRANS = 2'b10;  // NONSEQ
        else if (state == DATA_ST)               HTRANS = 2'b00;  // IDLE (no next transfer)
        else                                     HTRANS = 2'b00;  // IDLE
    end

    //=========================================================
    // HWDATA: luôn từ registered value (stable trong toàn bộ data phase)
    //=========================================================
    assign HWDATA = hwdata_reg;

    //=========================================================
    // Response FIFO: push khi data phase hoàn thành (HREADY=1)
    //=========================================================
    assign resp_wr_en   = (state == DATA_ST) && HREADY;
    assign resp_wr_data = {HRESP, HRDATA};

endmodule
