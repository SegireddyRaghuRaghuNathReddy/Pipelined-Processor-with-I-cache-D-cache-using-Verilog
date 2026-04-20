/*`include "Control_Unit_Top.v"
`include "Register_File.v"
`include "Sign_Extend.v"
*/



/*
 * Decode_Cycle.v
 *
 * MODIFICATION from original:
 *   Added 'stall' input port.
 *   Reason: The ID/EX pipeline register must also freeze during a cache miss.
 *   If it were allowed to update while the IF/ID register is frozen, the
 *   decode stage would re-decode stale data and corrupt the EX stage inputs.
 */

module decode_cycle (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,           // NEW: 1 = freeze ID/EX register

    input  wire [31:0] InstrD,
    input  wire [31:0] PCD,
    input  wire [31:0] PCPlus4D,
    input  wire        RegWriteW,
    input  wire [4:0]  RDW,
    input  wire [31:0] ResultW,

    output wire        RegWriteE,
    output wire        ALUSrcE,
    output wire        MemWriteE,
    output wire        ResultSrcE,
    output wire        BranchE,
    output wire [2:0]  ALUControlE,
    output wire [31:0] RD1_E,
    output [31:0] RD2_E,
    output wire [31:0] Imm_Ext_E,
    output wire [4:0]  RS1_E,
    output wire [4:0]  RS2_E,
    output wire [4:0]  RD_E,
    output wire [31:0] PCE,
    output wire [31:0] PCPlus4E
);

    // Interim wires
    wire        RegWriteD, ALUSrcD, MemWriteD, ResultSrcD, BranchD;
    wire [1:0]  ImmSrcD;
    wire [2:0]  ALUControlD;
    wire [31:0] RD1_D, RD2_D, Imm_Ext_D;

    // ID/EX pipeline registers
    reg        RegWriteD_r, ALUSrcD_r, MemWriteD_r, ResultSrcD_r, BranchD_r;
    reg [2:0]  ALUControlD_r;
    reg [31:0] RD1_D_r, RD2_D_r, Imm_Ext_D_r;
    reg [4:0]  RD_D_r, RS1_D_r, RS2_D_r;
    reg [31:0] PCD_r, PCPlus4D_r;

    //Control Unit
    Control_Unit_Top control (
        .Op       (InstrD[6:0]),
        .funct3   (InstrD[14:12]),
        .funct7   (InstrD[31:25]),
        .RegWrite (RegWriteD),
        .ImmSrc   (ImmSrcD),
        .ALUSrc   (ALUSrcD),
        .MemWrite (MemWriteD),
        .ResultSrc(ResultSrcD),
        .Branch   (BranchD),
        .ALUControl(ALUControlD)
    );

    // Register File 
    Register_File rf (
        .clk(clk),
        .rst(rst),
        .WE3(RegWriteW),
        .WD3(ResultW),
        .A1 (InstrD[19:15]),
        .A2 (InstrD[24:20]),
        .A3 (RDW),
        .RD1(RD1_D),
        .RD2(RD2_D)
    );

    //Sign Extension 
    Sign_Extend extension (
        .In     (InstrD[31:0]),
        .ImmSrc (ImmSrcD),
        .Imm_Ext(Imm_Ext_D)
    );

    // ID/EX Pipeline Register 
    // On stall: hold current values (freeze)
    // On flush (branch): insert NOP by clearing all control signals
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteD_r  <= 1'b0;
            ALUSrcD_r    <= 1'b0;
            MemWriteD_r  <= 1'b0;
            ResultSrcD_r <= 1'b0;
            BranchD_r    <= 1'b0;
            ALUControlD_r<= 3'b000;
            RD1_D_r      <= 32'h0;
            RD2_D_r      <= 32'h0;
            Imm_Ext_D_r  <= 32'h0;
            RD_D_r       <= 5'h0;
            PCD_r        <= 32'h0;
            PCPlus4D_r   <= 32'h0;
            RS1_D_r      <= 5'h0;
            RS2_D_r      <= 5'h0;
        end
        else if (!stall) begin   // NEW: freeze on cache miss
            RegWriteD_r  <= RegWriteD;
            ALUSrcD_r    <= ALUSrcD;
            MemWriteD_r  <= MemWriteD;
            ResultSrcD_r <= ResultSrcD;
            BranchD_r    <= BranchD;
            ALUControlD_r<= ALUControlD;
            RD1_D_r      <= RD1_D;
            RD2_D_r      <= RD2_D;
            Imm_Ext_D_r  <= Imm_Ext_D;
            RD_D_r       <= InstrD[11:7];
            PCD_r        <= PCD;
            PCPlus4D_r   <= PCPlus4D;
            RS1_D_r      <= InstrD[19:15];
            RS2_D_r      <= InstrD[24:20];
        end
        // else: stall=1 → hold all values
    end

    // Output Assignments
    assign RegWriteE  = RegWriteD_r;
    assign ALUSrcE    = ALUSrcD_r;
    assign MemWriteE  = MemWriteD_r;
    assign ResultSrcE = ResultSrcD_r;
    assign BranchE    = BranchD_r;
    assign ALUControlE= ALUControlD_r;
    assign RD1_E      = RD1_D_r;
    assign RD2_E      = RD2_D_r;
    assign Imm_Ext_E  = Imm_Ext_D_r;
    assign RD_E       = RD_D_r;
    assign PCE        = PCD_r;
    assign PCPlus4E   = PCPlus4D_r;
    assign RS1_E      = RS1_D_r;
    assign RS2_E      = RS2_D_r;

endmodule
