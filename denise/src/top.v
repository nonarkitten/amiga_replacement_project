// Copyright 2011, 2012 Frederic Requin
// Copyright 2024, 2025 Renee Cousins, The Buffee project, Inc
//
// See README.md for details

module top(
  // CSG 8362R8 Denise chip
  input         M1H,
  input         M0H,

  input   [8:1] RGA,


  output  [3:0] RED,
  output  [3:0] GRN,
  output  [3:0] BLU,

  output        BURST_n, // Composite colour burst
  output        ZD_n,    // Transparency signal (genlock)

  input         CSYNC_n, // ignored right now
  input         CDAC_n,
  input         C7M,
  input         CCK,

  input         M0V,
  input         M1V,

  inout  [15:0] DB
);

//////////////////////////////////////////////////////
// PLL that generates 56 MHz clock from 7 MHz       //
//                                                  //
// Note that the iCE40HX specification states that  //
// the minimum PLL speed is ~10MHz, the actual      //
// lower bound is closer to 4.125MHz. The actual    //
// constraint is that the internal Fvco sits        //
// between 533 and 1066MHz.                         //
//                                                  //
//////////////////////////////////////////////////////

wire clk_56m;

`ifdef SIM
reg clk_56m = 0;
always #8.928 clk_56m = ~clk_56m; // example 56MHz
`else
/* verilator lint_off UNDRIVEN */
/* verilator lint_off PINMISSING */
SB_PLL40_CORE #(
    .FEEDBACK_PATH("SIMPLE"),
    .DIVR(4'b0000),
    .DIVF(7'b1111111), // x128
    .DIVQ(3'b100),     // /16 = x8
    .FILTER_RANGE(3'b001)
) pll_inst (
    .REFERENCECLK (C7M),
    .PLLOUTGLOBAL (clk_56m),
    .RESETB       (1'b1),
    .BYPASS       (1'b0)
);
/* verilator lint_on UNDRIVEN */
/* verilator lint_on PINMISSING */
`endif

reg [3:0] phase;
always @(posedge clk_56m)
    phase <= phase + 4'd1;

// Denise uses an internal clock that's separate from the
// bus signals provided by CCK, C7M and CDAC. This means
// we are free to regenerate good FPGA clocks that are
// entirely independent from the external clock.
//          _   _   _   _   _   _   _   _ 
// c28i  |_| |_| |_| |_| |_| |_| |_| |_| |  phase[0]
//            ___     ___     ___     ___ 
// c14i  |___|   |___|   |___|   |___|   |  phase[1]
//                _______         _______ 
// c7mi  |_______|       |_______|       |  phase[2]
//                        _______________ 
// ccki  |_______________|               |  phase[3]
//
//        0 1 2 3 4 5 6 7 8 9 A B C D E F   phase (hex)

// ================================================
// Internal "clock aliases"
// Use for latches ONLY, do not use as clocks
// ================================================
wire ccki  = (phase[3]);
wire cckqi = (phase[3:0] > 4'h3) && (phase[3:0] < 4'hC);
wire c7mi  = (phase[2]);
wire cdaci = (phase[2:0] > 3'h1) && (phase[2:0] < 6'h6);
wire c14i  = (phase[1]);
wire c28i  = (phase[0]);

// ================================================
// Frequency-equivalent strobes
// Use for conditionals ONLY, do not use as clocks
// ================================================
wire cck_e  = (phase[2:0] == 3'd0);
wire cckq_e = (phase[2:0] == 3'd4);
wire c7m_e  = (phase[1:0] == 2'd0);
wire cdac_e = (phase[1:0] == 2'd2);
wire c14m_e = (phase[0]   == 1'd0);

// ================================================
// Clock Domain Crossing
// ================================================

wire [15:0] w_dbo_d;
wire        w_dbo_d_en;

// External Capture
reg [8:1] rga_cck;
reg [15:0] db_cck;
always @(posedge C7M) begin
    if (CCK) rga_cck <= RGA;
    else     db_cck <= DB;
end

// Single real CDC into FPGA domain
reg [8:1] rga_sync1, rga_sync2;
reg [15:0] db_sync1, db_sync2;
always @(posedge clk_56m) begin
    rga_sync1 <= rga_cck;
    rga_sync2 <= rga_sync1;

    db_sync1 <= db_cck;
    db_sync2 <= db_sync1;
end

wire  [8:1] w_rga = rga_sync2;
wire [15:0] w_dbi = db_sync2;

// Data out does not need CDC
assign DB = (w_dbo_d_en) ? w_dbo_d : 16'hz;

// Video output (to Amber)
wire [3:0] w_red;
wire [3:0] w_green;
wire [3:0] w_blue;
wire       w_zd;
wire       w_burst;

denise #(
    // Config
    .cfg_ecs(1'b1),
    .cfg_a1k(1'b0)
) denise (
    // Clock (actual)
    .clk(clk_56m),

    // Clock levels
    .cck(ccki),
    .cckq(cckqi),
    .c7m(c7mi),
    .cdac(cdaci),
    .c14m(c14i),
    .c28m(c28i),    

    // Clock edges
    .cck_e(cck_e),
    .cckq_e(cckq_e),
    .cdac_e(cdac_e),
    .c7m_e(c7m_e),
    .c14m_e(c14m_e),

    // Mouse/Joystick
    .m0h(M0H),
    .m0v(M0V),
    .m1h(M1H),
    .m1v(M1V),

    // Bus Input/Output
    .rga(w_rga),
    .db_in(w_dbi),
    .db_out(w_dbo_d),
    .db_oen(w_dbo_d_en),

    // Video Output
    .red(w_red),
    .green(w_green),
    .blue(w_blue),
    .zd(w_zd),
    .burst(w_burst)
);

assign RED = w_red;
assign GRN = w_green;
assign BLU = w_blue;
assign ZD_n = w_zd;
assign BURST_n = w_burst;

endmodule
