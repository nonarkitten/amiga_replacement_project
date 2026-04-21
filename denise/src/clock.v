`timescale 1ps/1ps

//      ,ad8888ba,   88           ,ad8888ba,      ,ad8888ba,   88      a8P   
//     d8"'    `"8b  88          d8"'    `"8b    d8"'    `"8b  88    ,88'    
//    d8'            88         d8'        `8b  d8'            88  ,88"      
//    88             88         88          88  88             88,d88'       
//    88             88         88          88  88             8888"88,      
//    Y8,            88         Y8,        ,8P  Y8,            88P   Y8b     
//     Y8a.    .a8P  88          Y8a.    .a8P    Y8a.    .a8P  88     "88,   
//      `"Y8888Y"'   88888888888  `"Y8888Y"'      `"Y8888Y"'   88       Y8b  

module clock(
    input  c7m,   // 

    output c56m,  // deprecated

    output ccki,  // 
    output cckqi, // 
    output c7mi,  // 
    output cdaci, // 
    output c14i,  // 
    output c28i,  // 

    output cck_e, // 
    output cckq_e,// 
    output c7m_e, // 
    output cdac_e,// 
    output c14m_e // 
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

  //wire c56m;

  `ifdef SIM
  reg c56m = 0;
  always #8.928 c56m = ~c56m; // example 56MHz
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
      .REFERENCECLK (c7m),
      .PLLOUTGLOBAL (c56m),
      .RESETB       (1'b1),
      .BYPASS       (1'b0)
  );
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on PINMISSING */
  `endif

  reg [3:0] phase;
  always @(posedge c56m)
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
  assign ccki  = (phase[3]);
  assign cckqi = (phase[3:0] > 4'h3) && (phase[3:0] < 4'hC);
  assign c7mi  = (phase[2]);
  assign cdaci = (phase[2:0] > 3'h1) && (phase[2:0] < 6'h6);
  assign c14i  = (phase[1]);
  assign c28i  = (phase[0]);

  // ================================================
  // Frequency-equivalent strobes
  // Use for conditionals ONLY, do not use as clocks
  // ================================================
  assign cck_e  = (phase[2:0] == 3'd0);
  assign cckq_e = (phase[2:0] == 3'd4);
  assign c7m_e  = (phase[1:0] == 2'd0);
  assign cdac_e = (phase[1:0] == 2'd2);
  assign c14m_e = (phase[0]   == 1'd0);

endmodule
