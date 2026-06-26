// Register File — 32×32-bit synchronous-write, combinational-read, 2 read ports.
//
// Gap-4 RAW bypass (write-before-read):
//   In a 7-stage pipeline, WB commits on the same cycle that ID reads the register
//   file. Without bypass, the instruction at ID would read a stale value because the
//   synchronous write happens at the next posedge. The combinational bypass on the
//   read ports resolves this without a stall.
//
// x0 hardwired to zero: write enable is gated so x0 is never updated.

module register_file (
    input  logic        clk,
    input  logic        rst_n,

    // Read port 1 (rs1 at ID stage)
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,

    // Read port 2 (rs2 at ID stage)
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,

    // Write port (rd from WB stage)
    input  logic        we,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data
);

    logic [31:0] registers [0:31];
    integer i;

    logic we_valid;
    assign we_valid = we && (rd_addr != 5'd0);  // x0 is never written

    //=========================================================
    // Synchronous Write
    //=========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (we_valid) begin
            registers[rd_addr] <= rd_data;
        end
    end

    //=========================================================
    // Combinational Read — gap-4 RAW bypass included
    //=========================================================
    assign rs1_data = (rs1_addr == 5'd0)               ? 32'd0   :
                      (we_valid && rd_addr == rs1_addr) ? rd_data :
                      registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0)               ? 32'd0   :
                      (we_valid && rd_addr == rs2_addr) ? rd_data :
                      registers[rs2_addr];

endmodule
