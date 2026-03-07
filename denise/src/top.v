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

SB_PLL40_CORE #(
    .FEEDBACK_PATH("SIMPLE"),
    .DIVR(4'b0000),       // reference divider
    .DIVF(7'b1111111),    // feedback multiplier = 1 + 31 = 32
    .DIVQ(3'b100),        // output divider = 2 * (1 + 1) = 4
    .FILTER_RANGE(3'b001) // minimum filter range
) pll_inst (
    .REFERENCECLK  (C7M),
    .PLLOUTGLOBAL  (clk_56m),
    .RESETB        (1'b1),
    .BYPASS        (1'b0)
);

// Resample actual CCK at 56MHz
reg [7:0] cck;
always @(posedge clk_56m) cck <= { cck[6:0], CCK };

wire w_cck_edge  = (cck[0] != cck[1]);                       // Lowres pixel clock
wire w_cckq_edge = (cck[4] != cck[5]);                       // Hires pixel clock
wire w_cdac_edge = (cck[2] != cck[3]) || (cck[6] != cck[7]); // Super-hires pixel clock

wire w_cck  = cck[0]; // Recreate CCK (&&w_cck = rising, &&~w_cck = falling)
wire w_cckq = cck[4]; // Recreate CCKQ
wire w_c7m  = cck[0] ^ cck[4];
wire w_cdac = cck[2] ^ cck[6];

// RGA bus
wire  [8:1] w_rga = RGA;

// Data bus
wire [15:0] w_dbi = DB;
wire [15:0] w_dbo_d;
wire        w_dbo_d_en;

assign DB = (w_dbo_d_en) ? w_dbo_d : 16'hz;

// Video output (to Amber)
wire [3:0] w_red;
wire [3:0] w_green;
wire [3:0] w_blue;
wire       w_zd;
wire       w_burst = BURST_n;

denise denise(
    // Clock
    .clk(clk_56m),

    // Clock enables
    .cck(w_cck),
    .cckq(w_cckq),
    .c7m(w_c7m),
    .cdac(w_cdac),
    .cck_edge(w_cck_edge),
    .cckq_edge(w_cckq_edge),
    .cdac_edge(w_cdac_edge),

    // Mouse/Joystick
    .m0h(M0H),
    .m0v(M0V),
    .m1h(M1H),
    .m1v(M1V),

    // Config
    .cfg_ecs(1'b1),
    .cfg_a1k(1'b0),

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

endmodule
