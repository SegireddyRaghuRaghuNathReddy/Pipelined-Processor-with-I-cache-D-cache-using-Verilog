/*
 
 
  MODIFICATIONS from original:
    Original only handled forwarding (ForwardAE, ForwardBE).
    The following have been added:
 
    1. stall_pipeline input — from Cache_Controller.
       When stall_pipeline=1 (cache miss), all pipeline registers freeze.
       The hazard unit passes this through as stall to each stage.
 
    2. Load-use stall (stall_load).
       Reason: When a load instruction is in EX and the very next
       instruction reads the loaded register, the data is not yet
       available (it won't be until after MEM). We must insert one
       bubble (NOP) into the pipeline by:
         - Stalling IF and ID (freeze their registers)
         - Flushing EX (clear control signals → NOP bubble)
       Condition: ResultSrcE=1 (load in EX) AND
                  (RD_E == RS1_D OR RD_E == RS2_D)
 
    3. Branch flush (flush_D).
       Reason: When a branch is taken (PCSrcE=1), the instruction
       already fetched into IF/ID is wrong. We must flush it by
       clearing the IF/ID register (insert a NOP).
 
    FORWARDING logic is unchanged from the original.
    ForwardAE=2'b10 → forward from MEM stage (ALU_ResultM)
    ForwardAE=2'b01 → forward from WB stage  (ResultW)
    ForwardAE=2'b00 → no forwarding (use register file value)
 */

module hazard_unit (
    input  wire        rst,

    // Forwarding inputs
    input  wire        RegWriteM,       // MEM stage writing a register?
    input  wire        RegWriteW,       // WB  stage writing a register?
    input  wire [4:0]  RD_M,            // destination register in MEM
    input  wire [4:0]  RD_W,            // destination register in WB
    input  wire [4:0]  Rs1_E,           // source register 1 in EX
    input  wire [4:0]  Rs2_E,           // source register 2 in EX

    // Load-use hazard inputs
    input  wire        ResultSrcE,      // NEW: 1 = load instruction in EX stage
    input  wire [4:0]  RD_E,            // NEW: destination register in EX
    input  wire [4:0]  Rs1_D,           // NEW: source register 1 in ID stage
    input  wire [4:0]  Rs2_D,           // NEW: source register 2 in ID stage

    // Branch flush input
    input  wire        PCSrcE,          // NEW: 1 = branch taken (flush IF/ID)

    // Cache miss stall input
    input  wire        stall_pipeline,  // NEW: 1 = cache miss, freeze pipeline

    // Forwarding outputs (unchanged)
    output wire [1:0]  ForwardAE,       // mux select for EX src A
    output wire [1:0]  ForwardBE,       // mux select for EX src B

    // Stall outputs 
    output wire        stall_IF,        // NEW: freeze IF/ID register + PC
    output wire        stall_ID,        // NEW: freeze ID/EX register
    output wire        stall_MEM,       // NEW: freeze MEM/WB register

    //Flush output 
    output wire        flush_D          // NEW: clear IF/ID register (branch taken)
);

    // Load-use stall detection
    // If a load (ResultSrcE=1) is in EX and the next instruction (in ID)
    // reads the same register, we must stall for 1 cycle.
    wire load_use_stall = ResultSrcE &
                          ((RD_E == Rs1_D) | (RD_E == Rs2_D)) &
                          (RD_E != 5'h0);

    //Combined stall 
    // Stall if either a cache miss OR a load-use hazard is detected
    wire stall_any = stall_pipeline | load_use_stall;

    //Stall signal distribution
    // IF and ID stages always freeze together on any stall
    assign stall_IF  = (rst == 1'b0) ? 1'b0 : stall_any;
    assign stall_ID  = (rst == 1'b0) ? 1'b0 : stall_any;
    // MEM stage only freezes on cache miss (not load-use)
    assign stall_MEM = (rst == 1'b0) ? 1'b0 : stall_pipeline;

    // Branch flush
    // Flush the IF/ID register when a branch is taken.
    // Note: do NOT flush during a stall (cache miss takes priority).
    assign flush_D = (rst == 1'b0) ? 1'b0 : (PCSrcE & ~stall_any);

    // Forwarding logic (unchanged from original) 
    assign ForwardAE = (rst == 1'b0) ? 2'b00 :
                       ((RegWriteM) & (RD_M != 5'h0) & (RD_M == Rs1_E)) ? 2'b10 :
                       ((RegWriteW) & (RD_W != 5'h0) & (RD_W == Rs1_E)) ? 2'b01 :
                       2'b00;

    assign ForwardBE = (rst == 1'b0) ? 2'b00 :
                       ((RegWriteM) & (RD_M != 5'h0) & (RD_M == Rs2_E)) ? 2'b10 :
                       ((RegWriteW) & (RD_W != 5'h0) & (RD_W == Rs2_E)) ? 2'b01 :
                       2'b00;

endmodule
