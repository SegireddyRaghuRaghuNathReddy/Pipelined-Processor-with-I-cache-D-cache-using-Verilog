/*
   Added 'flush' input port.
   Reason: On a load-use hazard, the hazard unit needs to insert a NOP
   bubble into the EX/MEM register. This is done by clearing all control
   signals (RegWrite, MemWrite, ResultSrc, Branch) to zero when flush=1.
   This prevents the instruction currently in EX from having any effect
   on memory or registers — effectively making it a NOP for one cycle.
   All other logic (forwarding muxes, ALU, branch adder) is unchanged.
 */

module execute_cycle (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,           // NEW: 1 = insert NOP bubble into EX/MEM

    // Inputs from ID/EX register 
    input  wire        RegWriteE,
    input  wire        ALUSrcE,
    input  wire        MemWriteE,
    input  wire        ResultSrcE,
    input  wire        BranchE,
    input  wire [2:0]  ALUControlE,
    input  wire [31:0] RD1_E,
    input  wire [31:0] RD2_E,
    input  wire [31:0] Imm_Ext_E,
    input  wire [4:0]  RD_E,
    input  wire [31:0] PCE,
    input  wire [31:0] PCPlus4E,
    input  wire [31:0] ResultW,         // forwarded from WB stage
    input  wire [1:0]  ForwardA_E,      // from hazard unit
    input  wire [1:0]  ForwardB_E,      // from hazard unit

    // Outputs
    output wire        PCSrcE,          // branch taken → PC select + flush IF/ID
    output wire [31:0] PCTargetE,       // branch target address

    // EX/MEM register outputs
    output wire        RegWriteM,
    output wire        MemWriteM,
    output wire        ResultSrcM,
    output wire [4:0]  RD_M,
    output wire [31:0] PCPlus4M,
    output wire [31:0] WriteDataM,
    output wire [31:0] ALU_ResultM
);

    // Internal wires 
    wire [31:0] Src_A, Src_B_interim, Src_B;
    wire [31:0] ResultE;
    wire        ZeroE;

    // EX/MEM pipeline registers
    reg        RegWriteE_r, MemWriteE_r, ResultSrcE_r;
    reg [4:0]  RD_E_r;
    reg [31:0] PCPlus4E_r, RD2_E_r, ResultE_r;

    //  Forwarding Mux — Source A 
    // 00 -> register file value(RD1_E)
    // 01 -> WB  stage result(ResultW)
    // 10 -> MEM stage result(ALU_ResultM)
    Mux_3_by_1 srca_mux (
        .a(RD1_E),
        .b(ResultW),
        .c(ALU_ResultM),
        .s(ForwardA_E),
        .d(Src_A)
    );

    // Forwarding Mux — Source B 
    Mux_3_by_1 srcb_mux (
        .a(RD2_E),
        .b(ResultW),
        .c(ALU_ResultM),
        .s(ForwardB_E),
        .d(Src_B_interim)
    );

    // ALU Source Mux
    // Selects between forwarded register value and immediate
    Mux alu_src_mux (
        .a(Src_B_interim),
        .b(Imm_Ext_E),
        .s(ALUSrcE),
        .c(Src_B)
    );

    // ALU 
    ALU alu (
        .A         (Src_A),
        .B         (Src_B),
        .ALUControl(ALUControlE),
        .Result    (ResultE),
        .OverFlow  (),
        .Carry     (),
        .Zero      (ZeroE),
        .Negative  ()
    );

    // Branch Target Adder
    PC_Adder branch_adder (
        .a(PCE),
        .b(Imm_Ext_E),
        .c(PCTargetE)
    );

    // EX/MEM Pipeline Register 
    // On flush=1 (load-use bubble): clear all control signals → NOP effect
    // On reset:  clear everything
    // Normal:    latch ALU results and control signals
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteE_r  <= 1'b0;
            MemWriteE_r  <= 1'b0;
            ResultSrcE_r <= 1'b0;
            RD_E_r       <= 5'h0;
            PCPlus4E_r   <= 32'h0;
            RD2_E_r      <= 32'h0;
            ResultE_r    <= 32'h0;
        end
        else if (flush) begin   // NEW: insert NOP bubble
            RegWriteE_r  <= 1'b0;   // no register write
            MemWriteE_r  <= 1'b0;   // no memory write
            ResultSrcE_r <= 1'b0;   // no memory read result
            RD_E_r       <= 5'h0;
            PCPlus4E_r   <= 32'h0;
            RD2_E_r      <= 32'h0;
            ResultE_r    <= 32'h0;
        end
        else begin
            RegWriteE_r  <= RegWriteE;
            MemWriteE_r  <= MemWriteE;
            ResultSrcE_r <= ResultSrcE;
            RD_E_r       <= RD_E;
            PCPlus4E_r   <= PCPlus4E;
            RD2_E_r      <= Src_B_interim;
            ResultE_r    <= ResultE;
        end
    end

    //Output Assignments
    assign PCSrcE     = ZeroE & BranchE;
    assign RegWriteM  = RegWriteE_r;
    assign MemWriteM  = MemWriteE_r;
    assign ResultSrcM = ResultSrcE_r;
    assign RD_M       = RD_E_r;
    assign PCPlus4M   = PCPlus4E_r;
    assign WriteDataM = RD2_E_r;
    assign ALU_ResultM= ResultE_r;

endmodule
