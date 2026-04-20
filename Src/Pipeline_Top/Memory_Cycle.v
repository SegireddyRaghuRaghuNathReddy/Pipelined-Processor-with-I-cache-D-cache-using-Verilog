/*
 * Memory_Cycle.v
 *
 * MODIFICATIONS from original:
 *   1. Data_Memory removed — replaced by d_cache instantiation.
 *      Reason: d_cache provides the same read/write interface but with
 *      hit/miss signalling needed for stall generation.
 *
 *   2. Added 'stall' input port.
 *      Reason: The MEM/WB pipeline register must freeze during a D-cache miss.
 *      If it updated while the cache was still handling a miss, the wrong
 *      read data would be latched into the WB stage.
 *
 *   3. d_cache ports exposed as top-level ports for Cache_Controller.
 *      Reason: The controller needs to drive rden/wren and read hit_miss,
 *      mrdaddress, mrden, mwraddress, mwren, mdout for memory arbitration.
 *
 *   4. rden signal derived from ResultSrcM.
 *      Reason: ResultSrcM=1 means the instruction is a load (result comes
 *      from memory), so rden=ResultSrcM correctly enables the D-cache read.
 *      MemWriteM=1 means store, so wren=MemWriteM enables the D-cache write.
 */

module memory_cycle (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,           // NEW: 1 = freeze MEM/WB register

    // ── Inputs from EX/MEM register ───────────────────────────────────────
    input  wire        RegWriteM,
    input  wire        MemWriteM,
    input  wire        ResultSrcM,
    input  wire [4:0]  RD_M,
    input  wire [31:0] PCPlus4M,
    input  wire [31:0] WriteDataM,
    input  wire [31:0] ALU_ResultM,

    // ── d_cache connections (driven/read by Cache_Controller) ─────────────
    input  wire        dc_rden,         // read enable  → d_cache (from controller)
    input  wire        dc_wren,         // write enable → d_cache (from controller)
    output wire        dc_hit_miss,     // hit/miss → Cache_Controller
    output wire [31:0] dc_q,            // read data from d_cache
    // d_cache memory refill ports -> Cache_Controller -> mem.v
    output wire [31:0] dc_mrdaddress,
    output wire        dc_mrden,
    output wire [31:0] dc_mwraddress,
    output wire        dc_mwren,
    output wire [63:0] dc_mdout,
    input  wire [63:0] dc_mq,           // cache line data from main memory

    // Outputs to MEM/WB register
    output wire        RegWriteW,
    output wire        ResultSrcW,
    output wire [4:0]  RD_W,
    output wire [31:0] PCPlus4W,
    output wire [31:0] ALU_ResultW,
    output wire [31:0] ReadDataW
);

    // MEM/WB pipeline registers
    reg        RegWriteM_r, ResultSrcM_r;
    reg [4:0]  RD_M_r;
    reg [31:0] PCPlus4M_r, ALU_ResultM_r, ReadDataM_r;

    // D-Cache (replaces Data_Memory)
    // address  -> ALU result (computed memory address)
    // din      -> write data from register file (for store instructions)
    // rden     -> 1 on load  (ResultSrcM=1 means result from memory)
    // wren     -> 1 on store (MemWriteM=1)
    // hit_miss -> 1=hit, 0=miss → Cache_Controller → stall
    // q        -> 32-bit read data out to WB stage
    // mq       -> 64-bit cache line from main memory (on miss refill)
    d_cache DCACHE (
        .clock      (clk),
        .address    (ALU_ResultM),
        .din        (WriteDataM),
        .rden       (dc_rden),
        .wren       (dc_wren),
        .hit_miss   (dc_hit_miss),
        .q          (dc_q),
        .mdout      (dc_mdout),
        .mrdaddress (dc_mrdaddress),
        .mrden      (dc_mrden),
        .mwraddress (dc_mwraddress),
        .mwren      (dc_mwren),
        .mq         (dc_mq)
    );

    // MEM/WB Pipeline Register
    // On stall: hold current values (freeze)
    // On reset: clear to zero
    // Normal:   latch outputs for WB stage
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteM_r  <= 1'b0;
            ResultSrcM_r <= 1'b0;
            RD_M_r       <= 5'h0;
            PCPlus4M_r   <= 32'h0;
            ALU_ResultM_r<= 32'h0;
            ReadDataM_r  <= 32'h0;
        end
        else if (!stall) begin   // NEW: freeze on cache miss
            RegWriteM_r  <= RegWriteM;
            ResultSrcM_r <= ResultSrcM;
            RD_M_r       <= RD_M;
            PCPlus4M_r   <= PCPlus4M;
            ALU_ResultM_r<= ALU_ResultM;
            ReadDataM_r  <= dc_q;        // use d_cache output instead of DMEM
        end
        // else: stall=1 → hold all values
    end

    // Output Assignments 
    assign RegWriteW  = RegWriteM_r;
    assign ResultSrcW = ResultSrcM_r;
    assign RD_W       = RD_M_r;
    assign PCPlus4W   = PCPlus4M_r;
    assign ALU_ResultW= ALU_ResultM_r;
    assign ReadDataW  = ReadDataM_r;

endmodule
