/* verilator lint_off LATCH */
/* verilator lint_off UNOPTFLAT */

module bpout (
    input      BPIN,       // Bit Plane Inputs

    input      BPCLK,      // Bitplane Clock       I$1411
     
    output reg BP          // Bit Plane Output buffer  I$1414/I$1290
);
    reg        LR;         // Latch "register"     I$78/I$79
    reg        DFF1, DFF2; // Bona-fide latch registers

    always @(*) begin
        if (BPCLK) LR = BPIN; 
        BP = DFF2;
    end

    always @(posedge BPCLK) begin
        DFF1 <= LR;
        DFF2 <= DFF1;
    end

endmodule

/* verilator lint_on LATCH */
/* verilator lint_on UNOPTFLAT */
