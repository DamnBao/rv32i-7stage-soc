// AXI-Lite Interconnect (1GHz domain)
//
// 1 Master (axi_interface) → 3 Slaves (SFR0, SFR1, SFR2)
//
// Address decode (dùng addr[27:12], bóc tách ngoài always):
//   addr[27:12] == 16'h0000 → Slave 0 (base 0x2000_0000)
//   addr[27:12] == 16'h0001 → Slave 1 (base 0x2000_1000)
//   addr[27:12] == 16'h0002 → Slave 2 (base 0x2000_2000)
//
// Write routing:
//   AWVALID → slave dựa trên AWADDR (aw_sel, combinational)
//   WVALID  → slave dựa trên AWADDR nếu AWVALID còn high, hoặc aw_sel_reg sau khi AW accepted
//   BVALID  → mux về master từ aw_sel_reg (registered sau AW handshake)
//
// Read routing:
//   ARVALID → slave dựa trên ARADDR (ar_sel, combinational)
//   RVALID/RDATA → mux về master từ ar_sel_reg (registered sau AR handshake)
//
// IRQ aggregation: OR của tất cả slave IRQ

module axi_interconnect (
    input  logic        clk,
    input  logic        rst_n,

    //----------------- TỪ AXI MASTER (axi_interface) -----------------
    // Write address
    input  logic [31:0] M_AWADDR,
    input  logic [2:0]  M_AWPROT,
    input  logic        M_AWVALID,
    output logic        M_AWREADY,

    // Write data
    input  logic [31:0] M_WDATA,
    input  logic [3:0]  M_WSTRB,
    input  logic        M_WVALID,
    output logic        M_WREADY,

    // Write response
    output logic [1:0]  M_BRESP,
    output logic        M_BVALID,
    input  logic        M_BREADY,

    // Read address
    input  logic [31:0] M_ARADDR,
    input  logic [2:0]  M_ARPROT,
    input  logic        M_ARVALID,
    output logic        M_ARREADY,

    // Read data
    output logic [31:0] M_RDATA,
    output logic [1:0]  M_RRESP,
    output logic        M_RVALID,
    input  logic        M_RREADY,

    //----------------- SLAVE 0 -----------------
    output logic [31:0] S0_AWADDR,
    output logic [2:0]  S0_AWPROT,
    output logic        S0_AWVALID,
    input  logic        S0_AWREADY,

    output logic [31:0] S0_WDATA,
    output logic [3:0]  S0_WSTRB,
    output logic        S0_WVALID,
    input  logic        S0_WREADY,

    input  logic [1:0]  S0_BRESP,
    input  logic        S0_BVALID,
    output logic        S0_BREADY,

    output logic [31:0] S0_ARADDR,
    output logic [2:0]  S0_ARPROT,
    output logic        S0_ARVALID,
    input  logic        S0_ARREADY,

    input  logic [31:0] S0_RDATA,
    input  logic [1:0]  S0_RRESP,
    input  logic        S0_RVALID,
    output logic        S0_RREADY,

    input  logic        irq0,

    //----------------- SLAVE 1 -----------------
    output logic [31:0] S1_AWADDR,
    output logic [2:0]  S1_AWPROT,
    output logic        S1_AWVALID,
    input  logic        S1_AWREADY,

    output logic [31:0] S1_WDATA,
    output logic [3:0]  S1_WSTRB,
    output logic        S1_WVALID,
    input  logic        S1_WREADY,

    input  logic [1:0]  S1_BRESP,
    input  logic        S1_BVALID,
    output logic        S1_BREADY,

    output logic [31:0] S1_ARADDR,
    output logic [2:0]  S1_ARPROT,
    output logic        S1_ARVALID,
    input  logic        S1_ARREADY,

    input  logic [31:0] S1_RDATA,
    input  logic [1:0]  S1_RRESP,
    input  logic        S1_RVALID,
    output logic        S1_RREADY,

    input  logic        irq1,

    //----------------- SLAVE 2 -----------------
    output logic [31:0] S2_AWADDR,
    output logic [2:0]  S2_AWPROT,
    output logic        S2_AWVALID,
    input  logic        S2_AWREADY,

    output logic [31:0] S2_WDATA,
    output logic [3:0]  S2_WSTRB,
    output logic        S2_WVALID,
    input  logic        S2_WREADY,

    input  logic [1:0]  S2_BRESP,
    input  logic        S2_BVALID,
    output logic        S2_BREADY,

    output logic [31:0] S2_ARADDR,
    output logic [2:0]  S2_ARPROT,
    output logic        S2_ARVALID,
    input  logic        S2_ARREADY,

    input  logic [31:0] S2_RDATA,
    input  logic [1:0]  S2_RRESP,
    input  logic        S2_RVALID,
    output logic        S2_RREADY,

    input  logic        irq2,

    //----------------- IRQ AGGREGATION -----------------
    output logic        axi_irq
);

    //=========================================================
    // 1. Address Decode (Combinational)
    //    Bóc tách addr[27:12] ngoài always
    //=========================================================
    logic [15:0] araddr_27_12, awaddr_27_12;
    assign araddr_27_12 = M_ARADDR[27:12];
    assign awaddr_27_12 = M_AWADDR[27:12];

    logic [1:0] ar_sel, aw_sel;

    always_comb begin
        ar_sel = 2'd3;  // Default: no slave
        if      (araddr_27_12 == 16'h0000) ar_sel = 2'd0;
        else if (araddr_27_12 == 16'h0001) ar_sel = 2'd1;
        else if (araddr_27_12 == 16'h0002) ar_sel = 2'd2;
    end

    always_comb begin
        aw_sel = 2'd3;
        if      (awaddr_27_12 == 16'h0000) aw_sel = 2'd0;
        else if (awaddr_27_12 == 16'h0001) aw_sel = 2'd1;
        else if (awaddr_27_12 == 16'h0002) aw_sel = 2'd2;
    end

    //=========================================================
    // 2. Registered Slave Select (cho response mux)
    //    ar_sel_reg: latch khi AR handshake (ARVALID && ARREADY)
    //    aw_sel_reg: latch khi AW handshake (AWVALID && AWREADY)
    //=========================================================
    logic [1:0] ar_sel_reg, aw_sel_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_sel_reg <= 2'd3;
            aw_sel_reg <= 2'd3;
        end else begin
            if (M_ARVALID && M_ARREADY) ar_sel_reg <= ar_sel;
            if (M_AWVALID && M_AWREADY) aw_sel_reg <= aw_sel;
        end
    end

    //=========================================================
    // 3. Write Data (W) Routing
    //    Khi AWVALID còn high → dùng aw_sel (cùng AW đang gửi)
    //    Sau khi AW accepted (AWVALID=0) → dùng aw_sel_reg
    //=========================================================
    logic [1:0] w_route;
    assign w_route = M_AWVALID ? aw_sel : aw_sel_reg;

    //=========================================================
    // 4. AW Channel → Slaves
    //=========================================================
    assign S0_AWADDR  = M_AWADDR;
    assign S0_AWPROT  = M_AWPROT;
    assign S0_AWVALID = M_AWVALID && (aw_sel == 2'd0);

    assign S1_AWADDR  = M_AWADDR;
    assign S1_AWPROT  = M_AWPROT;
    assign S1_AWVALID = M_AWVALID && (aw_sel == 2'd1);

    assign S2_AWADDR  = M_AWADDR;
    assign S2_AWPROT  = M_AWPROT;
    assign S2_AWVALID = M_AWVALID && (aw_sel == 2'd2);

    // AWREADY mux về master (từ selected slave, combinational via aw_sel)
    always_comb begin
        case (aw_sel)
            2'd0:    M_AWREADY = S0_AWREADY;
            2'd1:    M_AWREADY = S1_AWREADY;
            2'd2:    M_AWREADY = S2_AWREADY;
            default: M_AWREADY = 1'b0;
        endcase
    end

    //=========================================================
    // 5. W Channel → Slaves (routed by w_route)
    //=========================================================
    assign S0_WDATA  = M_WDATA;
    assign S0_WSTRB  = M_WSTRB;
    assign S0_WVALID = M_WVALID && (w_route == 2'd0);

    assign S1_WDATA  = M_WDATA;
    assign S1_WSTRB  = M_WSTRB;
    assign S1_WVALID = M_WVALID && (w_route == 2'd1);

    assign S2_WDATA  = M_WDATA;
    assign S2_WSTRB  = M_WSTRB;
    assign S2_WVALID = M_WVALID && (w_route == 2'd2);

    // WREADY mux
    always_comb begin
        case (w_route)
            2'd0:    M_WREADY = S0_WREADY;
            2'd1:    M_WREADY = S1_WREADY;
            2'd2:    M_WREADY = S2_WREADY;
            default: M_WREADY = 1'b0;
        endcase
    end

    //=========================================================
    // 6. B Channel ← Slaves (mux by aw_sel_reg)
    //=========================================================
    assign S0_BREADY = M_BREADY && (aw_sel_reg == 2'd0);
    assign S1_BREADY = M_BREADY && (aw_sel_reg == 2'd1);
    assign S2_BREADY = M_BREADY && (aw_sel_reg == 2'd2);

    always_comb begin
        case (aw_sel_reg)
            2'd0:    begin M_BVALID = S0_BVALID; M_BRESP = S0_BRESP; end
            2'd1:    begin M_BVALID = S1_BVALID; M_BRESP = S1_BRESP; end
            2'd2:    begin M_BVALID = S2_BVALID; M_BRESP = S2_BRESP; end
            default: begin M_BVALID = 1'b0;      M_BRESP = 2'b00;    end
        endcase
    end

    //=========================================================
    // 7. AR Channel → Slaves
    //=========================================================
    assign S0_ARADDR  = M_ARADDR;
    assign S0_ARPROT  = M_ARPROT;
    assign S0_ARVALID = M_ARVALID && (ar_sel == 2'd0);

    assign S1_ARADDR  = M_ARADDR;
    assign S1_ARPROT  = M_ARPROT;
    assign S1_ARVALID = M_ARVALID && (ar_sel == 2'd1);

    assign S2_ARADDR  = M_ARADDR;
    assign S2_ARPROT  = M_ARPROT;
    assign S2_ARVALID = M_ARVALID && (ar_sel == 2'd2);

    // ARREADY mux
    always_comb begin
        case (ar_sel)
            2'd0:    M_ARREADY = S0_ARREADY;
            2'd1:    M_ARREADY = S1_ARREADY;
            2'd2:    M_ARREADY = S2_ARREADY;
            default: M_ARREADY = 1'b0;
        endcase
    end

    //=========================================================
    // 8. R Channel ← Slaves (mux by ar_sel_reg)
    //=========================================================
    assign S0_RREADY = M_RREADY && (ar_sel_reg == 2'd0);
    assign S1_RREADY = M_RREADY && (ar_sel_reg == 2'd1);
    assign S2_RREADY = M_RREADY && (ar_sel_reg == 2'd2);

    always_comb begin
        case (ar_sel_reg)
            2'd0:    begin M_RVALID = S0_RVALID; M_RDATA = S0_RDATA; M_RRESP = S0_RRESP; end
            2'd1:    begin M_RVALID = S1_RVALID; M_RDATA = S1_RDATA; M_RRESP = S1_RRESP; end
            2'd2:    begin M_RVALID = S2_RVALID; M_RDATA = S2_RDATA; M_RRESP = S2_RRESP; end
            default: begin M_RVALID = 1'b0;      M_RDATA = 32'd0;    M_RRESP = 2'b00;    end
        endcase
    end

    //=========================================================
    // 9. IRQ Aggregation
    //=========================================================
    assign axi_irq = irq0 | irq1 | irq2;

endmodule
