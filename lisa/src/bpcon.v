/* verilator lint_off LATCH */
/* verilator lint_off UNOPTFLAT */

module bpcon (
    input            C28M,

    // Contrary to the patent, each block does it's own RGA decoding
    input     [15:0] DB,    // Data bus
    input      [8:1] WAD,   // Register Write Address Bus 

    // These should come from the Playfield horizontal shift comparators
    input            PFALD, // Playfield A Load
    input            PFBLD, // Playfield B Load
    input            PFASH, // Playfield A Shift
    input            PFBSH, // Playfield B Shift

    // This is our two-phase state for AGA; probably not used on ECS
    input            WEN1,  // Write Enable Phase 1
    input            WEN2,  // Write Enable Phase 2

    output reg       XFERA, // Playfield A Transfer
    output reg       XFERB, // Playfield B Transfer
    output reg [3:0] SHA,   // Playfield A Shift
    output reg [3:0] SHB,   // Playfield B Shift

    output reg [8:1] BPLD,  // Bitplane Load

    // This is plit into two phases for AGA to enable
    // writes into two different sets of 32-bit registers
    // forming a complete 64-bit shift register

    output reg [8:1] WD1,   // Bitplace Write Phase 1
    output reg [8:1] WD2    // Bitplace Write Phase 2

    // Playfield A is 7, 5, 3, 1
    // Playfield B is 8, 6, 4, 2
);

    reg [3:0] XFER;
    reg       PFALD_;
    reg       PFBLD_;
    reg       PFASH_;
    reg       PFBSH_;
    reg [3:0] BPUC;

    wire BPLCON0 = (WAD[8:1] == 8'b10000000);

    always @(posedge BPLCON0) begin
        BPUC <= {DB[4], DB[14:12]};
    end

    always @(posedge C28M) begin
        XFER[0] <= (WAD[8:1] == 8'b10001000);
        XFER[1] <= ~XFER[0];
        XFER[2] <= ~(XFER[0] & XFER[1]);
        XFER[3] <= ~XFER[2];

        PFALD_ <= ~PFALD;
        PFBLD_ <= ~PFBLD;

        PFASH_ <= ~PFASH;
        PFBSH_ <= ~PFBSH;        
    end

    always @(*) begin
        WD1 = 8'b0; // default
        WD2 = 8'b0; // default
        if (WAD[8:4] == 5'b10001) begin
            if (WEN1) WD1[WAD[3:1]] = 1'b1;
            if (WEN2) WD2[WAD[3:1]] = 1'b1;
        end

        XFERA = XFER[3];
        XFERB = XFER[3];

        SHA = {4{(~(PFASH_ & C28M))}};
        SHB = {4{(~(PFBSH_ & C28M))}};

        BPLD[1] = PFALD_ && (BPUC > 4'd0);
        BPLD[2] = PFBLD_ && (BPUC > 4'd1);
        BPLD[3] = PFALD_ && (BPUC > 4'd2);
        BPLD[4] = PFBLD_ && (BPUC > 4'd3);
        BPLD[5] = PFALD_ && (BPUC > 4'd4);
        BPLD[6] = PFBLD_ && (BPUC > 4'd5);
        BPLD[7] = PFALD_ && (BPUC > 4'd6);
        BPLD[8] = PFBLD_ && (BPUC > 4'd7);
    end

endmodule

/* verilator lint_on LATCH */
/* verilator lint_on UNOPTFLAT */
