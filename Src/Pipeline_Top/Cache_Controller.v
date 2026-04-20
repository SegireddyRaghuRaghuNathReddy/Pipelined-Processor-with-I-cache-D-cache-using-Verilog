/*
 * Cache_Controller.v
 *
 * NEW MODULE — did not exist before.
 *
 * PURPOSE:
 *   Acts as the glue between your pipeline stages and the cache modules.
 *   It does three things:
 *     1. Drives rden/wren signals into both caches based on pipeline requests.
 *     2. Monitors hit_miss outputs and generates pipeline stall signals.
 *     3. Connects the cache miss refill ports to the shared main memory (mem.v).
 *
 * WHY NEEDED:
 *   Your i_cache and d_cache both have rden/wren/hit_miss/mrdaddress/mq ports
 *   that need to be driven correctly. Without a controller, caches would never
 *   know when to start a transaction, and the pipeline would never know when
 *   to stall. This module centralises all that logic cleanly.
 *
 * STALL LOGIC:
 *   stall_pipeline = 1 whenever either cache reports a miss (hit_miss = 0)
 *   during an active request. The pipeline (PC, IF/ID, ID/EX, EX/MEM registers)
 *   must freeze while stall_pipeline = 1.
 *
 * MEMORY ARBITRATION:
 *   Both caches share one main memory (mem.v). A simple priority scheme is
 *   used: I-cache miss is served first, then D-cache miss. In practice both
 *   misses rarely occur in the same cycle because instructions and data are
 *   in separate caches.
 */

module Cache_Controller (
    input  wire        clk,
    input  wire        rst,

    //I-cache
    input  wire [31:0] icache_address,    // PC from Fetch stage
    input  wire        icache_rden,       // always 1 during normal fetch
    // i_cache ports driven by controller
    output reg         ic_rden,           // rden  → i_cache
    output reg         ic_wren,           // wren  → i_cache (always 0 for I$)
    // i_cache outputs read by controller
    input  wire        ic_hit_miss,       // hit_miss from i_cache
    input  wire [31:0] ic_mrdaddress,     // memory read address from i_cache
    input  wire        ic_mrden,          // memory read enable from i_cache
    input  wire [31:0] ic_mwraddress,     // memory write address from i_cache
    input  wire        ic_mwren,          // memory write enable from i_cache
    input  wire [31:0] ic_mdout,          // data from i_cache → memory (evict)

    //D-cache side 
    input  wire [31:0] dcache_address,    // ALU result from MEM stage
    input  wire [31:0] dcache_din,        // write data from MEM stage
    input  wire        dcache_rden,       // 1 on load instruction
    input  wire        dcache_wren,       // 1 on store instruction
    // d_cache ports driven by controller
    output reg         dc_rden,           // rden → d_cache
    output reg         dc_wren,           // wren → d_cache
    // d_cache outputs read by controller
    input  wire        dc_hit_miss,       // hit_miss from d_cache
    input  wire [31:0] dc_mrdaddress,     // memory read address from d_cache
    input  wire        dc_mrden,          // memory read enable from d_cache
    input  wire [31:0] dc_mwraddress,     // memory write address from d_cache
    input  wire        dc_mwren,          // memory write enable from d_cache
    input  wire [63:0] dc_mdout,          // data from d_cache → memory (evict)

    // Shared main memory (mem.v) ports
    // mem.v is single-ported so we arbitrate here
    output reg  [31:0] mem_rdaddress,     // read address  -> mem
    output reg         mem_rden,          // read enable   -> mem
    output reg  [31:0] mem_wraddress,     // write address -> mem
    output reg         mem_wren,          // write enable  -> mem
    output reg  [31:0] mem_data,          // write data    -> mem
    input  wire [31:0] mem_q,             // read data     <- mem

    // Pipeline stall output 
    output wire        stall_pipeline     // 1 = freeze all pipeline registers
);

    // Internal miss detection 
    // A miss is only meaningful when there is an active request.
    wire ic_miss = icache_rden  & ~ic_hit_miss;
    wire dc_miss = (dcache_rden | dcache_wren) & ~dc_hit_miss;

    // Stall whenever either cache is handling a miss
    assign stall_pipeline = ic_miss | dc_miss;

    // Drive rden/wren into caches 
    always @(*) begin
        // I-cache: always read, never write (instruction cache)
        ic_rden = icache_rden;
        ic_wren = 1'b0;

        // D-cache: read on load, write on store
        dc_rden = dcache_rden;
        dc_wren = dcache_wren;
    end

    // Memory arbitration (I-cache has priority) 
    // When both caches miss simultaneously, serve I-cache first.
    always @(*) begin
        if (ic_mrden | ic_mwren) begin
            // I-cache is accessing memory
            mem_rdaddress = ic_mrdaddress;
            mem_rden      = ic_mrden;
            mem_wraddress = ic_mwraddress;
            mem_wren      = ic_mwren;
            mem_data      = ic_mdout;       // eviction data (32-bit)
        end
        else if (dc_mrden | dc_mwren) begin
            // D-cache is accessing memory
            mem_rdaddress = dc_mrdaddress;
            mem_rden      = dc_mrden;
            mem_wraddress = dc_mwraddress;
            mem_wren      = dc_mwren;
            mem_data      = dc_mdout[31:0]; // lower word of 64-bit eviction
        end
        else begin
            // No cache needs memory
            mem_rdaddress = 32'h0;
            mem_rden      = 1'b0;
            mem_wraddress = 32'h0;
            mem_wren      = 1'b0;
            mem_data      = 32'h0;
        end
    end

endmodule
