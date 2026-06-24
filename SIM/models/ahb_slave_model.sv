`timescale 1ns/1ps
// AHB-Lite slave model: 8×32-bit registers, proper 2-state FSM, optional wait state
//
// state=IDLE: HREADY=1, waits for HTRANS[1]=1 (NONSEQ) to begin address phase
// state=DATA: latches request, HREADY=0 for 1 cycle if insert_wait, then HREADY=1
//             captures HWDATA and returns to IDLE when HREADY=1
//
// HRESP = inject_err (combinational, valid throughout data phase)
// HRDATA = mem[ridx_lat] (combinational, valid throughout data phase)
module ahb_slave_model (
    input  logic        clk_ahb,
    input  logic        rst_ahb_n,
    input  logic [31:0] HADDR,
    input  logic [2:0]  HSIZE,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,
    output logic        HREADY,
    output logic [31:0] HRDATA,
    output logic        HRESP,
    input  logic        inject_err,
    input  logic        insert_wait  // insert 1 wait cycle in data phase
);
    localparam IDLE_S = 1'b0;
    localparam DATA_S = 1'b1;

    logic        state;
    logic        wait_pending;
    logic [2:0]  ridx_lat;
    logic        hwrite_lat;
    logic [31:0] mem [0:7];
    integer k;

    logic [2:0] haddr_idx;
    assign haddr_idx = HADDR[4:2];

    // HREADY=0 only during wait_pending cycle in DATA state
    assign HREADY = (state == DATA_S) ? ~wait_pending : 1'b1;
    assign HRDATA = mem[ridx_lat];
    assign HRESP  = inject_err ? 1'b1 : 1'b0;

    always_ff @(posedge clk_ahb or negedge rst_ahb_n) begin
        if (!rst_ahb_n) begin
            state        <= IDLE_S;
            wait_pending <= 1'b0;
            ridx_lat     <= 3'd0;
            hwrite_lat   <= 1'b0;
            for (k = 0; k < 8; k = k + 1) mem[k] <= 32'd0;
        end else begin
            case (state)
                IDLE_S: begin
                    // Address phase: HTRANS=NONSEQ (or SEQ), HREADY=1 from slave in IDLE
                    if (HTRANS[1]) begin
                        ridx_lat     <= haddr_idx;
                        hwrite_lat   <= HWRITE;
                        wait_pending <= insert_wait;
                        state        <= DATA_S;
                    end
                end
                DATA_S: begin
                    if (wait_pending) begin
                        // HREADY=0 this cycle — clear wait, next cycle HREADY=1
                        wait_pending <= 1'b0;
                    end else begin
                        // HREADY=1 — data phase complete
                        if (hwrite_lat)
                            mem[ridx_lat] <= HWDATA;
                        state <= IDLE_S;
                    end
                end
                default: state <= IDLE_S;
            endcase
        end
    end
endmodule
