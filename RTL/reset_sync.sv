module reset_sync (
    input  logic clk,
    input  logic async_rst_n,
    output logic sync_rst_n
);

    logic rst_s1;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rst_s1     <= 1'b0;
            sync_rst_n <= 1'b0;
        end else begin
            rst_s1     <= 1'b1;
            sync_rst_n <= rst_s1;
        end
    end

endmodule
