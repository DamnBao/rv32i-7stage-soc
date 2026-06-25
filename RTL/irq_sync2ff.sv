// 2-FF Synchronizer for single-bit signals crossing clock domain boundaries.
//
// Usage in this SoC: AHB peripheral IRQ lines (500MHz) → CPU domain (1GHz).
// soc_top instantiates one copy per AHB slave to avoid glitching that would
// occur if multiple sources were OR'd before synchronization.
//
// Why 2 FFs: a single FF can output metastable voltage levels that propagate
// downstream; the second FF resolves them with overwhelming probability before
// any combinational logic samples the output.

module irq_sync2ff (
    input  logic clk,    // Destination clock (1GHz CPU domain)
    input  logic rst_n,  // Synchronized active-low reset in destination domain
    input  logic d,      // Asynchronous input from source clock domain (500MHz AHB)
    output logic q       // Synchronized output in destination clock domain
);

    logic ff1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff1 <= 1'b0;
            q   <= 1'b0;
        end else begin
            ff1 <= d;
            q   <= ff1;
        end
    end

endmodule
