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

  wire clk_56m;
  
  wire ccki;
  wire cckqi;
  wire c7mi;
  wire cdaci;
  wire c14i;
  wire c28i;
  wire cck_e;
  wire cckq_e;
  wire c7m_e;
  wire cdac_e;
  wire c14m_e;

  clock clock(
    .c7m(C7M),

    .c56m(clk_56m),

    .ccki(ccki),
    .cckqi(cckqi),
    .c7mi(c7mi),
    .cdaci(cdaci),
    .c14i(c14i),
    .c28i(c28i),
    
    .cck_e(cck_e),
    .cckq_e(cckq_e),
    .c7m_e(c7m_e),
    .cdac_e(cdac_e),
    .c14m_e(c14m_e)
  );  
  
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
