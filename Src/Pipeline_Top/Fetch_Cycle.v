/*
 
 
  MODIFICATIONS from original:
    1. Instruction_Memory removed — replaced by i_cache instantiation.
       Reason: i_cache provides the same instruction fetch but with
       hit/miss signalling needed for stall generation.
 
    2. Added 'stall' input port.
       Reason: When the cache controller asserts stall=1 (cache miss),
       the IF/ID pipeline register must hold its current values and the
       PC must not advance. Without this, a new (wrong) instruction would
       overwrite the pipeline register on the next clock edge.
 
    3. PC_Module now receives the stall signal.
       Reason: PC must freeze during a miss so the same address is
       re-presented to the cache on the next cycle.
 
    4. i_cache ports (clock, address, rden, wren, hit_miss, q, mq, etc.)
       are exposed as top-level ports so the Cache_Controller in Pipeline_Top
       can connect to them directly.
 */

module fetch_cycle (
    input  wire        clk,
    input  wire        rst,
    input  wire        PCSrcE,          // branch taken signal from EX stage
    input  wire [31:0] PCTargetE,       // branch target address from EX stage
    input  wire        stall,           // NEW: 1 = freeze (cache miss)

    // i_cache connections (driven by Cache_Controller)
    input  wire        ic_rden,         // read enable  → i_cache (from controller)
    input  wire        ic_wren,         // write enable → i_cache (always 0)
    output wire        ic_hit_miss,     // hit/miss signal → Cache_Controller
    output wire [31:0] ic_q,            // instruction word from i_cache
    // i_cache memory refill ports → Cache_Controller → mem.v
    output wire [31:0] ic_mrdaddress,
    output wire        ic_mrden,
    output wire [31:0] ic_mwraddress,
    output wire        ic_mwren,
    output wire [31:0] ic_mdout,
    input  wire [31:0] ic_mq,           // data from main memory → i_cache

    // Pipeline outputs to ID stage
    output wire [31:0] InstrD,
    output wire [31:0] PCD,
    output wire [31:0] PCPlus4D
);

    // Internal wires
    wire [31:0] PC_F;       // next PC (mux output)
    wire [31:0] PCF;        // current PC (PC register output)
    wire [31:0] PCPlus4F;   // PC + 4

    // Pipeline register (IF/ID)
    reg [31:0] InstrF_reg;
    reg [31:0] PCF_reg;
    reg [31:0] PCPlus4F_reg;

    // PC Select Mux 
    // Selects between PC+4 (normal) and branch target
    Mux PC_MUX (
        .a(PCPlus4F),
        .b(PCTargetE),
        .s(PCSrcE),
        .c(PC_F)
    );

    // Program Counter 
    // Stall input added: PC holds value during cache miss
    PC_Module Program_Counter (
        .clk(clk),
        .rst(rst),
        .stall(stall),      // NEW
        .PC(PCF),
        .PC_Next(PC_F)
    );

    // I-Cache (replaces Instruction_Memory)
    // clock    -> clk
    // address  -> current PC
    // din      -> 0 (instruction cache never writes from CPU)
    // rden     -> driven by Cache_Controller
    // wren     -> driven by Cache_Controller (always 0)
    // hit_miss -> goes to Cache_Controller → stall logic
    // q        -> instruction word (32-bit)
    // mq       -> cache line data from main memory (on miss refill)
    i_cache ICACHE (
        .clock      (clk),
        .address    (PCF),
        .din        (32'h00000000),   // instruction cache: no CPU writes
        .rden       (ic_rden),
        .wren       (ic_wren),
        .hit_miss   (ic_hit_miss),
        .q          (ic_q),
        .mdout      (ic_mdout),
        .mrdaddress (ic_mrdaddress),
        .mrden      (ic_mrden),
        .mwraddress (ic_mwraddress),
        .mwren      (ic_mwren),
        .mq         (ic_mq)
    );

    // PC Adder
    PC_Adder PC_adder (
        .a(PCF),
        .b(32'h00000004),
        .c(PCPlus4F)
    );

    // IF/ID Pipeline Register 
    // On stall: hold current values (freeze the register)
    // On reset: clear to NOP (0x00000000)
    // Normal:   latch fetched instruction and PC values
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            InstrF_reg   <= 32'h00000000;
            PCF_reg      <= 32'h00000000;
            PCPlus4F_reg <= 32'h00000000;
        end
        else if (!stall) begin   // NEW: freeze on cache miss
            InstrF_reg   <= ic_q;         // use i_cache output instead of IMEM
            PCF_reg      <= PCF;
            PCPlus4F_reg <= PCPlus4F;
        end
        // else: stall=1 → hold all register values
    end

    // Output assignments 
    assign InstrD   = (rst == 1'b0) ? 32'h00000000 : InstrF_reg;
    assign PCD      = (rst == 1'b0) ? 32'h00000000 : PCF_reg;
    assign PCPlus4D = (rst == 1'b0) ? 32'h00000000 : PCPlus4F_reg;

endmodule
