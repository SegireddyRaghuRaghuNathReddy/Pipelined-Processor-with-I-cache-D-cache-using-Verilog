/*
  PC.v  — Program Counter
 
  MODIFICATION from original:
    Added 'stall' input.
    When stall=1 (cache miss), PC holds its current value instead of
    advancing. This prevents the processor from moving past an instruction
    that hasn't been fetched/completed yet.
 */

module PC_Module(clk, rst, stall, PC, PC_Next);

    input  clk, rst;
    input  stall;           // NEW: 1 = freeze PC (cache miss)
    input  [31:0] PC_Next;
    output reg [31:0] PC;

    always @(posedge clk) begin
        if (rst == 1'b0)
            PC <= 32'h00000000;
        else if (!stall)    // NEW: only advance when not stalled
            PC <= PC_Next;
        // else: hold current PC
    end

endmodule
