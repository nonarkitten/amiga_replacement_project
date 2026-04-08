module bplane(
    input            C28M, // Bitplane Clock

    input [31:0]     DB,   // Parallel Data Inputs
    input [8:1]      WAD,  // Register Write Address Bus 

    // These should come from the Playfield horizontal shift comparators
    input            PFALD, // Playfield A Load
    input            PFBLD, // Playfield B Load
    input            PFASH, // Playfield A Shift
    input            PFBSH, // Playfield B Shift

    // This is our two-phase state for AGA; probably not used on ECS
    input            WEN1,  // Write Enable Phase 1
    input            WEN2,  // Write Enable Phase 2

    output [7:0]     BP
);

    wire       XFERA; // Playfield A Transfer
    wire       XFERB; // Playfield B Transfer
    wire [3:0] SHA;   // Playfield A Shift
    wire [3:0] SHB;   // Playfield B Shift
    wire [8:1] BPLD;  // Bitplane Load
    wire [8:1] WD1;   // Bitplace Write Phase 1
    wire [8:1] WD2;   // Bitplace Write Phase 2

    bpcon bpcon(
        .C28M(C28M), 
        .DB(DB[31:16]),    
        .WAD(WAD),   
        .PFALD(PFALD), 
        .PFBLD(PFBLD), 
        .PFASH(PFASH), 
        .PFBSH(PFBSH), 
        .WEN1(WEN1),  
        .WEN2(WEN2),  

        .XFERA(XFERA), 
        .XFERB(XFERB), 
        .SHA(SHA),   
        .SHB(SHB),   
        .BPLD(BPLD),  
        .WD1(WD1),   
        .WD2(WD2) 
    );

    bplreg bpldat1(C28M, DB, XFERA, SHA[0], BPLD[0], WEN1, WEN2, BP[0]);
    bplreg bpldat2(C28M, DB, XFERB, SHB[0], BPLD[1], WEN1, WEN2, BP[1]);
    bplreg bpldat3(C28M, DB, XFERA, SHA[1], BPLD[2], WEN1, WEN2, BP[2]);
    bplreg bpldat4(C28M, DB, XFERB, SHB[1], BPLD[3], WEN1, WEN2, BP[3]);
    bplreg bpldat5(C28M, DB, XFERA, SHA[2], BPLD[4], WEN1, WEN2, BP[4]);
    bplreg bpldat6(C28M, DB, XFERB, SHB[2], BPLD[5], WEN1, WEN2, BP[5]);
    bplreg bpldat7(C28M, DB, XFERA, SHA[3], BPLD[6], WEN1, WEN2, BP[6]);
    bplreg bpldat8(C28M, DB, XFERB, SHB[3], BPLD[7], WEN1, WEN2, BP[7]);

endmodule