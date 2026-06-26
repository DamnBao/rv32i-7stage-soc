// Branch Predictor — 16-entry 2-bit saturating counter BHT + Branch Target Buffer.
//
// Lookup (combinational, IF1 stage):
//   index = fetch_pc[5:2] (4 bits → 16 entries)
//   tag   = fetch_pc[31:6] (26 bits, for collision detection)
//   BTB hit = btb_valid[index] && btb_tag[index] == tag
//   predict_taken  = BTB hit && bht[index][1]   (top bit of 2-bit counter)
//   predict_target = btb_target[index]
//
// Update (sequential, EX stage):
//   BHT: saturating +1 on taken, -1 on not-taken  (00↔01↔10↔11)
//   BTB: entry written (valid=1, tag, target) only when update_taken=1
//   Initial BHT state: 2'b01 (weakly not-taken) → cold-start acts as predict-not-taken
//
// Coding constraints: all bit/part-selects on wires in assign statements; none in always_*.

module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,

    // ── IF1 lookup (combinational) ──────────────────────────
    input  logic [31:0] fetch_pc,
    output logic        predict_taken,
    output logic [31:0] predict_target,

    // ── EX update (sequential) ──────────────────────────────
    input  logic        update_en,      // 1 when branch/jump resolves at EX
    input  logic [31:0] update_pc,      // PC of resolved branch/jump
    input  logic        update_taken,   // actual taken / not-taken
    input  logic [31:0] update_target   // actual target address (used when update_taken=1)
);
    localparam N     = 16;   // number of BTB/BHT entries
    localparam TAG_W = 26;   // pc[31:6] — 32 - 4 (index) - 2 (always-zero pc[1:0])

    // ── Storage arrays ──────────────────────────────────────
    logic             btb_valid  [N];
    logic [TAG_W-1:0] btb_tag    [N];
    logic [31:0]      btb_target [N];
    logic [1:0]       bht        [N];

    // ── Lookup wires (extracted per coding rule: no bit-select inside always_*) ──
    logic [3:0]       lu_idx;
    logic [TAG_W-1:0] lu_tag;
    logic             lu_valid;
    logic [TAG_W-1:0] lu_btb_tag;
    logic [31:0]      lu_btb_target;
    logic [1:0]       lu_bht;

    assign lu_idx        = fetch_pc[5:2];
    assign lu_tag        = fetch_pc[31:6];
    assign lu_valid      = btb_valid[lu_idx];
    assign lu_btb_tag    = btb_tag[lu_idx];
    assign lu_btb_target = btb_target[lu_idx];
    assign lu_bht        = bht[lu_idx];

    assign predict_target = lu_btb_target;
    assign predict_taken  = lu_valid && (lu_btb_tag == lu_tag) && lu_bht[1];

    // ── Update wires ─────────────────────────────────────────
    logic [3:0]       up_idx;
    logic [TAG_W-1:0] up_tag;
    logic [1:0]       up_bht_cur;
    logic [1:0]       up_bht_next;

    assign up_idx     = update_pc[5:2];
    assign up_tag     = update_pc[31:6];
    assign up_bht_cur = bht[up_idx];

    always_comb begin
        if (update_taken)
            up_bht_next = (up_bht_cur == 2'b11) ? 2'b11 : up_bht_cur + 2'b01;
        else
            up_bht_next = (up_bht_cur == 2'b00) ? 2'b00 : up_bht_cur - 2'b01;
    end

    // ── Sequential update ─────────────────────────────────────
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin
                btb_valid[i]  <= 1'b0;
                btb_tag[i]    <= 26'd0;
                btb_target[i] <= 32'd0;
                bht[i]        <= 2'b01;  // weakly not-taken
            end
        end else if (update_en) begin
            bht[up_idx] <= up_bht_next;
            if (update_taken) begin
                btb_valid[up_idx]  <= 1'b1;
                btb_tag[up_idx]    <= up_tag;
                btb_target[up_idx] <= update_target;
            end
        end
    end

endmodule
