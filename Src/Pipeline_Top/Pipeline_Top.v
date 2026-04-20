/*
 Pipeline_Top.v  — Fully integrated top module
 
  MODIFICATIONS from original:
 
    1. Instruction_Memory and Data_Memory are REMOVED from instantiation.
       They now live inside i_cache and d_cache respectively (via miss refill
       through the shared mem.v main memory).
 
    2. Cache_Controller added (new module).
       Drives rden/wren into both caches, arbitrates shared main memory
       access, and generates stall_pipeline signal.
 
    3. mem.v (main memory) added.
       Single-port memory shared by both caches for miss refill.
 
    4. Hazard_unit extended with:
         - stall_pipeline input  (from Cache_Controller)
         - load-use stall logic  (ResultSrcE, RD_E, Rs1_D, Rs2_D)
         - branch flush output   (flush_D → clears IF/ID register)
         - stall outputs         (stall_IF, stall_ID, stall_MEM)
 
    5. All pipeline stage modules receive stall/flush signals:
         - fetch_cycle   : stall_IF  (freezes PC + IF/ID register)
         - decode_cycle  : stall_ID  (freezes ID/EX register)
         - execute_cycle : flush_EX  (inserts NOP bubble on load-use)
         - memory_cycle  : stall_MEM (freezes MEM/WB register)
 
    6. New wires added for:
         - Cache controller <-> i_cache ports
         - Cache controller <-> d_cache ports
         - Cache controller <-> main memory ports
         - Hazard unit stall/flush distribution
         - Load-use hazard detection signals (Rs1_D, Rs2_D, RD_E, ResultSrcE)
 */

`include "Fetch_Cycle.v"
`include "Decode_Cycle.v"
`include "Execute_Cycle.v"
`include "Memory_Cycle.v"
`include "Writeback_Cycle.v"
`include "PC.v"
`include "PC_Adder.v"
`include "Mux.v"
`include "Mux3by1.v"
`include "Control_Unit_Top.v"
`include "Register_File.v"
`include "Sign_Extend.v"
`include "ALU.v"
`include "Hazard_unit.v"
`include "i_cache.v"
`include "d_cache.v"
`include "mem.v"
`include "Cache_Controller.v"
`include "clog2.v"

module Pipeline_top (
    input wire clk,
    input wire rst
);

    
    // SECTION 1 — Original pipeline inter-stage wires (unchanged)
  

    wire        PCSrcE, RegWriteW, RegWriteE, ALUSrcE, MemWriteE;
    wire        ResultSrcE, BranchE, RegWriteM, MemWriteM, ResultSrcM, ResultSrcW;
    wire [2:0]  ALUControlE;
    wire [4:0]  RD_E, RD_M, RDW;
    wire [31:0] PCTargetE, InstrD, PCD, PCPlus4D, ResultW;
    wire [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;
    wire [31:0] PCPlus4M, WriteDataM, ALU_ResultM;
    wire [31:0] PCPlus4W, ALU_ResultW, ReadDataW;
    wire [4:0]  RS1_E, RS2_E;
    wire [1:0]  ForwardBE, ForwardAE;

    
    // SECTION 2 — New hazard/stall/flush wires
    

    wire        stall_IF;           // freeze PC and IF/ID register
    wire        stall_ID;           // freeze ID/EX register
    wire        stall_MEM;          // freeze MEM/WB register
    wire        flush_D;            // clear IF/ID register (branch taken)
    wire        flush_EX;           // insert NOP into EX/MEM (load-use)
    wire        stall_pipeline;     // from Cache_Controller (cache miss)

    // Signals needed for load-use hazard detection in Hazard_unit
    // Rs1_D, Rs2_D: source registers currently in ID stage
    wire [4:0]  Rs1_D, Rs2_D;      // driven by decode_cycle (InstrD[19:15/24:20])

  
    // SECTION 3 — I-cache <-> Cache_Controller wires
   

    wire        ic_rden, ic_wren;           // controller → i_cache
    wire        ic_hit_miss;                // i_cache → controller
    wire [31:0] ic_q;                       // i_cache → fetch stage
    wire [31:0] ic_mrdaddress;              // i_cache → controller → mem
    wire        ic_mrden;
    wire [31:0] ic_mwraddress;
    wire        ic_mwren;
    wire [31:0] ic_mdout;                   // i_cache → controller → mem (evict)
    wire [31:0] ic_mq;                      // mem → controller → i_cache

   
    // SECTION 4 — D-cache <-> Cache_Controller wires
    

    wire        dc_rden, dc_wren;           // controller → d_cache
    wire        dc_hit_miss;                // d_cache → controller
    wire [31:0] dc_q;                       // d_cache → memory stage
    wire [31:0] dc_mrdaddress;              // d_cache → controller → mem
    wire        dc_mrden;
    wire [31:0] dc_mwraddress;
    wire        dc_mwren;
    wire [63:0] dc_mdout;                   // d_cache → controller → mem (evict)
    wire [63:0] dc_mq;                      // mem → controller → d_cache


    // SECTION 5 — Main memory (mem.v) wires
 

    wire [31:0] mem_rdaddress;
    wire        mem_rden;
    wire [31:0] mem_wraddress;
    wire        mem_wren;
    wire [31:0] mem_data;                   // write data -> mem
    wire [31:0] mem_q;                      // read data  <- mem

    
    // SECTION 6 — Derived signals
    

    // load-use flush for EX stage:
    // same condition as load_use_stall inside Hazard_unit — flush EX when stalling
    assign flush_EX = stall_IF & ~stall_pipeline;
    //   stall_IF is asserted on load-use OR cache miss
    //   ~stall_pipeline isolates the load-use case
    //   on cache miss: stall_MEM handles it; no EX flush needed

    // Rs1_D / Rs2_D come directly from the current instruction in ID stage
    // (same bits the original decode_cycle already reads internally)
    assign Rs1_D = InstrD[19:15];
    assign Rs2_D = InstrD[24:20];

    // D-cache request signals derived from pipeline control:
    //   rden = ResultSrcM means it's a load (result comes from memory)
    //   wren = MemWriteM  means it's a store
    // These are passed to Cache_Controller which forwards them to dc_rden/dc_wren
    wire dcache_rden_req = ResultSrcM;
    wire dcache_wren_req = MemWriteM;

    // I-cache always reading during normal operation
    wire icache_rden_req = 1'b1;

    
    // MODULE INSTANTIATIONS
   

    // Fetch Stage 
    fetch_cycle Fetch (
        .clk          (clk),
        .rst          (rst),
        .PCSrcE       (PCSrcE),
        .PCTargetE    (PCTargetE),
        .stall        (stall_IF),       // NEW: freeze on miss or load-use
        // i_cache ports
        .ic_rden      (ic_rden),
        .ic_wren      (ic_wren),
        .ic_hit_miss  (ic_hit_miss),
        .ic_q         (ic_q),
        .ic_mrdaddress(ic_mrdaddress),
        .ic_mrden     (ic_mrden),
        .ic_mwraddress(ic_mwraddress),
        .ic_mwren     (ic_mwren),
        .ic_mdout     (ic_mdout),
        .ic_mq        (ic_mq),
        // pipeline outputs
        .InstrD       (InstrD),
        .PCD          (PCD),
        .PCPlus4D     (PCPlus4D)
    );

    // Decode Stage 
    decode_cycle Decode (
        .clk          (clk),
        .rst          (rst),
        .stall        (stall_ID),       // NEW: freeze on miss or load-use
        .InstrD       (InstrD),
        .PCD          (PCD),
        .PCPlus4D     (PCPlus4D),
        .RegWriteW    (RegWriteW),
        .RDW          (RDW),
        .ResultW      (ResultW),
        .RegWriteE    (RegWriteE),
        .ALUSrcE      (ALUSrcE),
        .MemWriteE    (MemWriteE),
        .ResultSrcE   (ResultSrcE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .RD1_E        (RD1_E),
        .RD2_E        (RD2_E),
        .Imm_Ext_E    (Imm_Ext_E),
        .RD_E         (RD_E),
        .PCE          (PCE),
        .PCPlus4E     (PCPlus4E),
        .RS1_E        (RS1_E),
        .RS2_E        (RS2_E)
    );

    // Execute Stage
    execute_cycle Execute (
        .clk          (clk),
        .rst          (rst),
        .flush        (flush_EX),       // NEW: insert NOP on load-use
        .RegWriteE    (RegWriteE),
        .ALUSrcE      (ALUSrcE),
        .MemWriteE    (MemWriteE),
        .ResultSrcE   (ResultSrcE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .RD1_E        (RD1_E),
        .RD2_E        (RD2_E),
        .Imm_Ext_E    (Imm_Ext_E),
        .RD_E         (RD_E),
        .PCE          (PCE),
        .PCPlus4E     (PCPlus4E),
        .PCSrcE       (PCSrcE),
        .PCTargetE    (PCTargetE),
        .RegWriteM    (RegWriteM),
        .MemWriteM    (MemWriteM),
        .ResultSrcM   (ResultSrcM),
        .RD_M         (RD_M),
        .PCPlus4M     (PCPlus4M),
        .WriteDataM   (WriteDataM),
        .ALU_ResultM  (ALU_ResultM),
        .ResultW      (ResultW),
        .ForwardA_E   (ForwardAE),
        .ForwardB_E   (ForwardBE)
    );

    // Memory Stage 
    memory_cycle Memory (
        .clk          (clk),
        .rst          (rst),
        .stall        (stall_MEM),      // NEW: freeze on cache miss
        .RegWriteM    (RegWriteM),
        .MemWriteM    (MemWriteM),
        .ResultSrcM   (ResultSrcM),
        .RD_M         (RD_M),
        .PCPlus4M     (PCPlus4M),
        .WriteDataM   (WriteDataM),
        .ALU_ResultM  (ALU_ResultM),
        // d_cache ports
        .dc_rden      (dc_rden),
        .dc_wren      (dc_wren),
        .dc_hit_miss  (dc_hit_miss),
        .dc_q         (dc_q),
        .dc_mrdaddress(dc_mrdaddress),
        .dc_mrden     (dc_mrden),
        .dc_mwraddress(dc_mwraddress),
        .dc_mwren     (dc_mwren),
        .dc_mdout     (dc_mdout),
        .dc_mq        (dc_mq),
        // outputs to WB
        .RegWriteW    (RegWriteW),
        .ResultSrcW   (ResultSrcW),
        .RD_W         (RDW),
        .PCPlus4W     (PCPlus4W),
        .ALU_ResultW  (ALU_ResultW),
        .ReadDataW    (ReadDataW)
    );

    // Write Back Stage
    writeback_cycle WriteBack (
        .clk       (clk),
        .rst       (rst),
        .ResultSrcW(ResultSrcW),
        .PCPlus4W  (PCPlus4W),
        .ALU_ResultW(ALU_ResultW),
        .ReadDataW (ReadDataW),
        .ResultW   (ResultW)
    );

    // Hazard Unit 
    hazard_unit Forwarding_block (
        .rst(rst),
        // forwarding
        .RegWriteM     (RegWriteM),
        .RegWriteW     (RegWriteW),
        .RD_M          (RD_M),
        .RD_W          (RDW),
        .Rs1_E         (RS1_E),
        .Rs2_E         (RS2_E),
        .ForwardAE     (ForwardAE),
        .ForwardBE     (ForwardBE),
        // load-use hazard
        .ResultSrcE    (ResultSrcE),    // NEW
        .RD_E          (RD_E),          // NEW
        .Rs1_D         (Rs1_D),         // NEW
        .Rs2_D         (Rs2_D),         // NEW
        // branch flush
        .PCSrcE        (PCSrcE),        // NEW
        // cache miss stall
        .stall_pipeline(stall_pipeline),// NEW
        // stall/flush outputs
        .stall_IF      (stall_IF),      // NEW
        .stall_ID      (stall_ID),      // NEW
        .stall_MEM     (stall_MEM),     // NEW
        .flush_D       (flush_D)        // NEW
    );

    //Cache Controller
    Cache_Controller cache_ctrl (
        .clk           (clk),
        .rst           (rst),
        // I-cache side
        .icache_address(InstrD),        // NOTE: PC is internal to fetch_cycle
        .icache_rden   (icache_rden_req),
        .ic_rden       (ic_rden),
        .ic_wren       (ic_wren),
        .ic_hit_miss   (ic_hit_miss),
        .ic_mrdaddress (ic_mrdaddress),
        .ic_mrden      (ic_mrden),
        .ic_mwraddress (ic_mwraddress),
        .ic_mwren      (ic_mwren),
        .ic_mdout      (ic_mdout),
        // D-cache side
        .dcache_address(ALU_ResultM),
        .dcache_din    (WriteDataM),
        .dcache_rden   (dcache_rden_req),
        .dcache_wren   (dcache_wren_req),
        .dc_rden       (dc_rden),
        .dc_wren       (dc_wren),
        .dc_hit_miss   (dc_hit_miss),
        .dc_mrdaddress (dc_mrdaddress),
        .dc_mrden      (dc_mrden),
        .dc_mwraddress (dc_mwraddress),
        .dc_mwren      (dc_mwren),
        .dc_mdout      (dc_mdout),
        // Main memory
        .mem_rdaddress (mem_rdaddress),
        .mem_rden      (mem_rden),
        .mem_wraddress (mem_wraddress),
        .mem_wren      (mem_wren),
        .mem_data      (mem_data),
        .mem_q         (mem_q),
        // Stall output
        .stall_pipeline(stall_pipeline)
    );

    // Main Memory (shared by both caches for miss refill) 
    // WIDTH=32, DEPTH=4096 → 16KB addressable with 32-bit words
    // FILE="memfile.hex" → pre-loads your instruction program
    mem #(
        .WIDTH(32),
        .DEPTH(4096),
        .FILE ("memfile.hex"),
        .INIT (0)
    ) MainMemory (
        .clock    (clk),
        .data     (mem_data),
        .rdaddress(mem_rdaddress[11:0]),  // 12-bit index into 4096-deep memory
        .rden     (mem_rden),
        .wraddress(mem_wraddress[11:0]),
        .wren     (mem_wren),
        .q        (mem_q)
    );

    // D-cache mq connection 
    // d_cache expects 64-bit mq (MWIDTH=64), mem.v gives 32-bit.
    // Duplicate the 32-bit word into both halves of the 64-bit line.
    assign dc_mq = {mem_q, mem_q};

    // I-cache mq connection 
    assign ic_mq = mem_q;

endmodule
