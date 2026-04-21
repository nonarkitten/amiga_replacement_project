// Copyright 2011, 2012 Frederic Requin
// Copyright 2024, 2025 Renee Cousins, The Buffee project, Inc
//  
// See README.md for details

module denise #(
    // Configuration
    parameter cfg_aga = 1'b0,  // Enable AGA-specific features
    parameter cfg_ecs = 1'b1,  // Enable ECS-specific features
    parameter cfg_a1k = 1'b0   // Normal mode(0), A1000 mode(1)
  ) (
    // Main clock
    input clk,        // Master clock (28/56/85 MHz)

    // Internal "clock aliases"
    input cck,        // CCK clock
    input cckq,       // CCK quadrature clock
    input c7m,        // 7MHz clock
    input cdac,       // 7MHz quadrature clock
    input c14m,       // 14MHz clock
    input c28m,       // 28MHz clock

    // Clock edges (56Mhz pulse)
    input cck_e,   // CCK edge
    input cckq_e,  // CCKQ edge
    input cdac_e,  // CDAC edge
    input c7m_e,
    input c14m_e,

    // Mouse/Joystick
    input m0h,
    input m0v,
    input m1h,
    input m1v,

    // Busses
    input  [ 8:1] rga,     // RGA bus
    input  [15:0] db_in,   // Data bus input
    output [15:0] db_out,  // Data bus output
    output        db_oen,  // Data bus output enable

    // Video output
    output     [3:0] red,      // Red component output
    output     [3:0] green,    // Green component output
    output     [3:0] blue,     // Blue component output
    output           zd,       // Genlock
    output           burst     // Composite color burst
  );

  // Commodore loved puns; WEN is *when* we ought to do one of two things
  // from the external bus world
  reg wen1, wen2;
  always @(posedge clk) begin
    if (c7m_e && !c7m) begin
      wen1 <=  cck;
      wen2 <= ~cck;
    end
  end
  
  // JOYxDAT registers
  reg [15:0] r_JOY0DAT;
  reg [15:0] r_JOY1DAT;
  reg [15:0] r_JOYTEST;

  quad m0v_quad(clk, cck, cck_e, w_wregs_joyw_en, r_JOYTEST[15:8], m0v, r_JOY0DAT[15:8]);
  quad m0h_quad(clk, cck, cck_e, w_wregs_joyw_en, r_JOYTEST[7:0] , m0h, r_JOY0DAT[7:0] );
  quad m1v_quad(clk, cck, cck_e, w_wregs_joyw_en, r_JOYTEST[15:8], m1v, r_JOY1DAT[15:8]);
  quad m1h_quad(clk, cck, cck_e, w_wregs_joyw_en, r_JOYTEST[7:0] , m1h, r_JOY1DAT[7:0] );

  // CLXCON register
  reg   [3:0] r_ENSP;
  reg   [5:0] r_ENBP;
  reg   [5:0] r_MVBP;

  // CLXDAT register
  reg  [14:0] r_CLXDAT;
  wire [14:0] w_CLXDAT;

  // BPLCON0 register
  reg         r_HIRES;  // High resoloution (640*200/640*400 interlace)
  reg   [3:0] r_BPU;    // Bit plane use code 0000-1000
  reg         r_HOMOD;  // Hold and modify mode
  reg         r_DBLPF;  // Double playfield (PFI=odd FP2= even bit planes)
  reg         r_COLOR;  // Enables color burst output signal
  reg         r_GAUD;   // Genlock audio enable
  reg         r_UHRES;  // Enables the UHRES pointers (for 1k*1k) 
  reg         r_SHRES;  // Super hi-res mode (35ns pixel width)
  reg         r_BYPASS; // Bypass color table and 8 bit wide data appear on R(7:0)
  reg         r_ECSENA; // When low (default), select bits in BPLCON3 are disabled

  // BPLCON1 register
  reg   [3:0] r_PF1H;
  reg   [3:0] r_PF2H;

  // BPLCON2 register
  reg   [2:0] r_ZDBPSEL;    // Bitplane Key
  reg         r_ZDBPEN;     // Use Bitplane Key
  reg         r_ZDCTEN;     // Use Color Key
  reg         r_KILLEHB;    // Kill halfbrite  
  reg         r_PF2PRI;     // Flip Playfield priority
  reg   [2:0] r_PF2P;       // Playfield 2 priority vs sprites
  reg   [2:0] r_PF1P;       // Playfield 1 priority vs sprites

  // BPLCON3 register
  reg   [2:0] r_SPR_RES;
  reg         r_BRDRBLNK;
  reg         r_BRDNTRAN;

  // BPLDAT registers
  reg   [15:0] r_BPLxDAT [0:5]; // Register written to by DMA
  reg   [15:0] r_BPLxTMP [0:5]; // Load into temporary when BPL 1 written
  reg   [19:0] r_BPLxSHF [0:5]; // Load into shifters when HPOS=PFxH, extra bits for LOL

  // COLORxx registers
  reg   [11:0] r_COLORxx_lo [0:15]; // COLOR00-COLOR15
  reg   [11:0] r_COLORxx_hi [0:15]; // COLOR16-COLOR31
  reg          r_COLOR_KEY  [0:31];

  // DIWSTRT, DIWSTOP and DIWHIGH (DIsplay Window) regisers
  reg    [8:0] r_HDIWSTRT;
  reg    [8:0] r_HDIWSTOP;

  // HBSTRT, HBSTOP (Horizontal Blank) registers
  reg   [10:0] r_HBSTRT;
  reg   [10:0] r_HBSTOP;

  // Sprite Registers  
  reg          r_SPRxATT  [0:7];
  reg   [10:0] r_SPRxHPOS [0:7];
  reg   [15:0] r_SPRxDATA [0:7];
  reg   [15:0] r_SPRxDATB [0:7];

  // Internal ECS Registers
  // wire        c28m = cck_e | cckq_e | cdac_e;
  reg [10:0]  r_rhpos;                  // real hpos counter in shres pixels

  wire [8:0]  r_hpos   = r_rhpos[10:2]; // horizontal position counter (lores pixels)
  wire [1:0]  r_shhpos = r_rhpos[1:0];  // hires and suprehires position counter

  reg         r_armed   [0:7];
  reg         r_enabled [0:7];
  reg         r_vblank;         // in vertical blank
  reg         r_vblank_p;       // previosu sample of vblank 
  reg         r_hblank;         // in horizontal blank
  reg         r_cblank;         // in either blank
  // reg         r_hwin_ena;       // horizontal window
  reg         r_lol_ena;        // long-line enabled
  
  // Do this nearly immediately to ensure we read in time
  assign db_out = w_rregs_joy0_en ? r_JOY0DAT        :
                  w_rregs_joy1_en ? r_JOY1DAT        :
                  w_rregs_clx_en  ? {1'b0, r_CLXDAT} :
                  w_rregs_id_en   ? 16'hFFFC         :
                                    16'd0;

  assign db_oen = w_rregs_joy0_en | w_rregs_joy1_en | w_rregs_clx_en | w_rregs_id_en;

  reg [15:0] r_db_in;
  reg [8:1] r_rga_in;

  //  888888ba,                                              88            8888888ba    ,ad888ba,        db         
  //  88    `"8b                                             88            88     "8b  d8"'   `"8b      d88b        
  //  88      `8b                                            88            88     ,8P d8'              d8'`8b       
  //  88       88  ,adPPYba,  ,adPPYba,  ,adPPYba,   ,adPPYb,88  ,adPPYba, 88aaaaa8P' 88              d8'  `8b      
  //  88       88 a8P_____88 a8"     "" a8"     "8a a8"    `Y88 a8P_____88 88"""88'   88     88888   d8YaaaaY8b     
  //  88       8P 8PP""""""" 8b         8b       d8 8b       88 8PP""""""" 88   `8b   Y8,       88  d8""""""""8b    
  //  88    .a8P  "8b,   ,aa "8a,   ,aa "8a,   ,a8" "8a,   ,d88 "8b,   ,aa 88    `8b   Y8a.   .a88 d8'        `8b   
  //  888888Y"'    `"Ybbd8"'  `"Ybbd8"'  `"YbbdP"'   `"8bbdP"Y8  `"Ybbd8"' 88     `8b   `"Y8888P" d8'          `8b  
                                           
  // Comparators
  wire w_rregs_joy0_en  = (r_rga_in[8:1] == 8'b0_0000_101);  // JOYxDAT  : $00A
  wire w_rregs_joy1_en  = (r_rga_in[8:1] == 8'b0_0000_110);  // JOYxDAT  : $00C
  wire w_rregs_clx_en   = (r_rga_in[8:1] == 8'b0_0000_111);  // CLXDAT   : $00E
  wire w_rregs_id_en    = (r_rga_in[8:1] == 8'b0_0111_110);  // DENISEID : $07C
  wire w_wregs_hpos_en  = (r_rga_in[8:1] == 8'b0_0111_110);  // VHPOS    : $02C
  wire w_wregs_joyw_en  = (r_rga_in[8:1] == 8'b0_0011_011);  // JOYTEST  : $036
  wire w_wregs_str_en   = (r_rga_in[8:1] == 8'b0_0011_1xx);  // Strobes  : $038 - $03E
                                                             // $038 STREQU
                                                             // $03A STRVBL
                                                             // $03C STRHOR
                                                             // $03E STRLONG

  wire w_wregs_diwb_en  = (r_rga_in[8:1] == 8'b0_1000_111);  // DIWSTRT  : $08E
  wire w_wregs_diwe_en  = (r_rga_in[8:1] == 8'b0_1001_000);  // DIWSTOP  : $090
  wire w_wregs_clx_en   = (r_rga_in[8:1] == 8'b0_1001_100);  // CLXCON   : $098
  wire w_wregs_ctl_en   = (r_rga_in[8:1] == 8'b1_0000_0xx);  // BPLCONx  : $100 - $106
  wire w_wregs_bpl_en   = (r_rga_in[8:1] == 8'b1_0001_xxx);  // BPLDAT   : $110 - $11E
  wire w_wregs_bpl_load = (r_rga_in[8:1] == 8'b1_0001_000);  // BPLDAT   : $110
  wire w_wregs_spr_en   = (r_rga_in[8:1] == 8'b1_01xx_xxx);  // Sprites  : $140 - $17E
  wire w_wregs_clut_en  = (r_rga_in[8:1] == 8'b1_10xx_xxx);  // Color    : $180 - $1BE
  wire w_wregs_diwh_en  = (r_rga_in[8:1] == 8'b1_1110_010);  // DIWHIGH  : $1E4

  always @(posedge clk) begin
    
    // Latch RGA bits
    if (cck_e & cck) r_rga_in <= rga;      

    // Read in DB bits for next cycle
    // Latch DB bits for next cycle
    r_db_in <= db_in;

    if (cck_e & cck) begin
      if (w_wregs_joyw_en) begin
        r_JOYTEST <= r_db_in;
      end

      if (w_wregs_str_en) begin
        if ((r_rga_in[2:1] == 2'b11) && cfg_ecs) begin
          r_lol_ena <= 1'b1;
        end else begin
          r_vblank <= !r_rga_in[2];
          r_lol_ena <= 1'b0;
        end
      end 

      if (w_wregs_spr_en) begin
        case (r_rga_in[2:1])
          2'b00 : begin 
            // SPRxPOS register
            r_SPRxHPOS[r_rga_in[5:3]][10:3] <= r_db_in[7:0];
          end
          2'b01 : begin 
            // SPRxCTL register
            r_SPRxATT[r_rga_in[5:3]]       <= r_db_in[7];
            //  superhires position
            r_SPRxHPOS[r_rga_in[5:3]][1:0] <= r_db_in[4:3] & {2{cfg_ecs}};
            r_SPRxHPOS[r_rga_in[5:3]][2]   <= r_db_in[0];
            r_armed[r_rga_in[5:3]]         <= 0;
          end
          2'b10 : begin 
            // SPRxDATA register
            r_SPRxDATA[r_rga_in[5:3]]      <= r_db_in[15:0];
            r_armed[r_rga_in[5:3]]         <= 1;
          end
          2'b11 : begin 
            // SPRxDATB register
            r_SPRxDATB[r_rga_in[5:3]]      <= r_db_in[15:0];
          end
        endcase
      end

      if (w_wregs_clx_en) begin
        r_ENSP   <= r_db_in[15:12];
        r_ENBP   <= r_db_in[11:6];
        r_MVBP   <= r_db_in[5:0];        
        r_CLXDAT <= 0;
      end else begin
        r_CLXDAT <= r_CLXDAT | w_CLXDAT;
      end

      if (w_wregs_ctl_en) begin
        case (r_rga_in[2:1])
        // BPLCON0
        2'b00 : begin
          r_HIRES    <= r_db_in[15];
          r_BPU      <= { r_db_in[4] && cfg_aga, r_db_in[14:12] };
          r_HOMOD    <= r_db_in[11];
          r_DBLPF    <= r_db_in[10];
          r_SHRES    <= r_db_in[6]     && cfg_ecs;
          end
        // BPLCON1
        2'b01 : begin
          r_PF1H     <= r_db_in[3:0]; // {r_db_in[11:10], r_db_in[3:0]}  <- AGA 64-pixel shifts
          r_PF2H     <= r_db_in[7:4]; // {r_db_in[15:14], r_db_in[7:4]}  <- AGA 64-pixel shifts
          end
        // BPLCON2
        2'b10 : begin
          r_ZDBPSEL  <= r_db_in[14:12] && cfg_ecs;
          r_ZDBPEN   <= r_db_in[11]    && cfg_ecs;
          r_ZDCTEN   <= r_db_in[10]    && cfg_ecs;
          r_KILLEHB  <= r_db_in[9]     && cfg_ecs;
          r_PF2PRI   <= r_db_in[6];
          r_PF2P     <= r_db_in[5:3];
          r_PF1P     <= r_db_in[2:0];
          end
        // BPLCON3
        2'b11 : begin
          r_SPR_RES  <= r_db_in[7:6]    & {2{cfg_ecs}}; // FIXME AGA
          r_BRDRBLNK <= r_db_in[5]     && cfg_ecs;
          r_BRDNTRAN <= r_db_in[4]     && cfg_ecs;
          end
        endcase
      end

      if (w_wregs_clut_en) begin
        r_COLOR_KEY[r_rga_in[5:1]] <= r_db_in[15];
        if (r_rga_in[5]) 
          r_COLORxx_hi[r_rga_in[4:1]] <= r_db_in[11:0];
        else             
          r_COLORxx_lo[r_rga_in[4:1]] <= r_db_in[11:0];
      end

      if (w_wregs_diwb_en) begin
        r_HBSTRT <= {r_db_in[7:0], r_db_in[10:8] && {3{cfg_ecs}}};
      end
      if (w_wregs_diwe_en) begin
        r_HBSTOP <= {r_db_in[7:0], r_db_in[10:8] && {3{cfg_ecs}}};
      end      

      if (w_wregs_diwb_en) begin
        r_HDIWSTRT <= {1'b0, r_db_in[7:0]};
      end
      if (w_wregs_diwe_en) begin
        r_HDIWSTOP <= {1'b1, r_db_in[7:0]};
      end      
      if (w_wregs_diwh_en && cfg_ecs) begin
        r_HDIWSTRT[8] <= r_db_in[5];
        r_HDIWSTOP[8] <= r_db_in[13];
      end
    end
  end  

  //     ,ad8888ba,                                                                             
  //    d8"'    `"8b                                       ,d                                   
  //   d8'                                                 88                                   
  //   88             ,adPPYba,  88       88 8b,dPPYba,  MM88MMM  ,adPPYba, 8b,dPPYba, ,adPPYba,
  //   88            a8"     "8a 88       88 88P'   `"8a   88    a8P_____88 88P'   "Y8 I8[    ""
  //   Y8,           8b       d8 88       88 88       88   88    8PP""""""" 88          `"Y8ba, 
  //    Y8a.    .a8P "8a,   ,a8" "8a,   ,a88 88       88   88,   "8b,   ,aa 88         aa    ]8I
  //     `"Y8888Y"'   `"YbbdP"'   `"YbbdP'Y8 88       88   "Y888  `"Ybbd8"' 88         `"YbbdP"'

  // Verified inner workings
  //
  // HPOS AGA/ECS
  // [10:1] Counter 10-bit (on C14M)
  // [0]    14MHz Generated clock (C14M)
  // RESET: 10'b00000100
  //
  // OCS
  // [10:3] Counter 8-bit (on CCK)
  // [2]    Colour Clock (CCK)
  // [1:0]  N/A
  // RESET: 8'bb000001
  
  // LOAD is always into HPOS [10:3]
  // RESET is triggered by one of STRHOR, STREQU or STRVBL.
  
  // Lie: Commodore HRM says VHPOS is Agnus only

  reg r_vwin_ena_;
  reg r_hwin_ena_;
  wire r_hwin_ena = r_vwin_ena_ & r_hwin_ena_;
  // reg r_cburst;

  always @(posedge clk) begin
    r_rhpos[0] <= ~c14m;
    if (c14m_e && ~c14m) begin
      if (cck_e && cck && w_wregs_str_en)
        r_rhpos[10:1] <= 8'b0000000100;
      else if (cck_e && cck && w_wregs_hpos_en)
        r_rhpos[10:1] <= { db_in[7:0], 2'b00 };
      else
        r_rhpos[10:1] <= r_rhpos[10:1] + 1;
    end
  end

  // diwcmp
  always @(posedge clk) begin
    if (c28m) begin
      if (r_hpos == 9'h013)          r_vwin_ena_ <= 1'b0;
      else if (w_wregs_bpl_en)       r_vwin_ena_ <= 1'b1;
      if (r_hpos == r_HDIWSTRT)      r_hwin_ena_ <= 1'b1;
      else if (r_hpos == r_HDIWSTOP) r_hwin_ena_ <= 1'b0;
    end
  end

  // blkcmp
  always @(posedge clk) begin
    if (c28m) begin
      if (r_rhpos ==  11'h040) r_hblank <= 1'b1;     // Horizontal blank start
      if (r_rhpos == r_HBSTRT) r_hblank <= 1'b1;     // Horizontal blank start
      if (r_hpos  ==  11'h174) r_hblank <= 1'b0;     // Horizontal blank stop      
      if (r_hpos  == r_HBSTOP) r_hblank <= 1'b0;     // Horizontal blank stop      
    end
  end

  // brscmp
  reg brston, brtsoff;
  always @(posedge clk) begin
    if (c28m) begin
      brston <=  (r_hpos == 9'h026);         // Colour burst start
      brtsoff <= (r_hpos == 9'h04E);        // Colour burst stop      

      r_vblank_p <= r_vblank;
      r_cblank   <= r_hblank || r_vblank;

    end
  end

  // bstcmp
  reg bwin;
  reg ben;
  always @(*) begin
    if (brston) bwin = 1;
    if (brtsoff) bwin = 0;
    if (wen1 && w_wregs_str_en) begin
      if (r_rga_in[2:1] == 2'b01) ben = 1;
      if (r_rga_in[2:1] == 2'b00) ben = 0;
    end
  end

  reg r_cburst;
  always @(posedge clk) begin
    r_cburst <= bwin && ben && !r_COLOR;
  end

  // Bitplane decoder (async)
  wire [7:0] r_bpl_ena =
    (r_BPU == 3'd0) ? 8'b00000000 :
    (r_BPU == 3'd1) ? 8'b00000001 :
    (r_BPU == 3'd2) ? 8'b00000011 :
    (r_BPU == 3'd3) ? 8'b00000111 :
    (r_BPU == 3'd4) ? 8'b00001111 :
    (r_BPU == 3'd5) ? 8'b00011111 :
    (r_BPU == 3'd6) ? 8'b00111111 :
    (r_BPU == 3'd7) ? 8'b01111111 :
                      8'b11111111 ; // 1xxx all 8bpp
   
  wire w_pixel_clk = (cck_e) || (cckq_e && (r_HIRES || r_SHRES)) || (cdac_e && r_SHRES);

  //    88888888ba  88                     88                                    
  //    88      "8b ""   ,d                88                                    
  //    88      ,8P      88                88                                    
  //    88aaaaaa8P' 88 MM88MMM 8b,dPPYba,  88 ,adPPYYba, 8b,dPPYba,   ,adPPYba,  
  //    88""""""8b, 88   88    88P'    "8a 88 ""     `Y8 88P'   `"8a a8P_____88  
  //    88      `8b 88   88    88       d8 88 ,adPPPPP88 88       88 8PP"""""""  
  //    88      a8P 88   88,   88b,   ,a8" 88 88,    ,88 88       88 "8b,   ,aa  
  //    88888888P"  88   "Y888 88`YbbdP"'  88 `"8bbdP"Y8 88       88  `"Ybbd8"'  
  //                           88                                                
  //                           88                                                
  
  // Bitplane Shifters
  wire r_LORES = ~r_SHRES && ~r_HIRES;

  wire w_bpl_shift = (r_SHRES)
                  || (r_HIRES && (r_rhpos[0:0] == 1'b0))
                  || (r_LORES && (r_rhpos[1:0] == 2'b11));

  reg  r_pf1_load;       // load BPL registers
  reg  r_pf2_load;       // load BPL registers

  wire [3:0] w_delaymask = (r_SHRES) ? 3 : (r_HIRES) ? 7 : 15;
  wire [4:0] w_lol_select = (r_lol_ena) ? ((r_SHRES) ? 19 : (r_HIRES) ? 17 : 16) : 15;

  reg [5:0] w_bpl_bus;

  always @(posedge clk) begin
    if (cck_e & cck && w_wregs_bpl_en) begin
      case (r_rga_in[3:1])
        3'd0 : begin
          r_BPLxTMP[0] <= r_db_in;
          r_BPLxTMP[1] <= r_BPLxDAT[1];
          r_BPLxTMP[2] <= r_BPLxDAT[2];
          r_BPLxTMP[3] <= r_BPLxDAT[3];
          r_BPLxTMP[4] <= r_BPLxDAT[4];
          r_BPLxTMP[5] <= r_BPLxDAT[5];
          r_pf1_load <= 1;
          r_pf2_load <= 1;
        end
        3'd1 : r_BPLxDAT[1] <= r_db_in;
        3'd2 : r_BPLxDAT[2] <= r_db_in;
        3'd3 : r_BPLxDAT[3] <= r_db_in;
        3'd4 : r_BPLxDAT[4] <= r_db_in;
        3'd5 : r_BPLxDAT[5] <= r_db_in;
        default:;
      endcase
    end

    if (c28m) begin
      if (r_pf1_load && ((r_hpos[3:0] & w_delaymask) == r_PF1H)) begin
        r_pf1_load <= 0;
        if (r_bpl_ena[0]) r_BPLxSHF[0] <= {r_BPLxSHF[0][18:15], r_BPLxTMP[0]};
        if (r_bpl_ena[2]) r_BPLxSHF[2] <= {r_BPLxSHF[2][18:15], r_BPLxTMP[2]};
        if (r_bpl_ena[4]) r_BPLxSHF[4] <= {r_BPLxSHF[4][18:15], r_BPLxTMP[4]};

      end else if (w_bpl_shift) begin
        r_BPLxSHF[0] <= {r_BPLxSHF[0][18:0], 1'b0};
        r_BPLxSHF[2] <= {r_BPLxSHF[2][18:0], 1'b0};
        r_BPLxSHF[4] <= {r_BPLxSHF[4][18:0], 1'b0};
      end

      if (r_pf2_load && ((r_hpos[3:0] & w_delaymask) == r_PF2H)) begin
        r_pf2_load <= 0;
        if (r_bpl_ena[1]) r_BPLxSHF[1] <= {r_BPLxSHF[1][18:15], r_BPLxTMP[1]};
        if (r_bpl_ena[3]) r_BPLxSHF[3] <= {r_BPLxSHF[3][18:15], r_BPLxTMP[3]};
        if (r_bpl_ena[5]) r_BPLxSHF[5] <= {r_BPLxSHF[5][18:15], r_BPLxTMP[5]};

      end else if (w_bpl_shift) begin
        r_BPLxSHF[1] <= {r_BPLxSHF[1][18:0], 1'b0};
        r_BPLxSHF[3] <= {r_BPLxSHF[3][18:0], 1'b0};
        r_BPLxSHF[5] <= {r_BPLxSHF[5][18:0], 1'b0};
      end

      // Bitplane Bus
      w_bpl_bus <= {
        r_BPLxSHF[5][w_lol_select], r_BPLxSHF[4][w_lol_select],
        r_BPLxSHF[3][w_lol_select], r_BPLxSHF[2][w_lol_select],
        r_BPLxSHF[1][w_lol_select], r_BPLxSHF[0][w_lol_select]
      } & {6{r_hwin_ena}};

    end
  end


  //     ad88888ba                         88                                  
  //    d8"     "8b                        ""   ,d                             
  //    Y8,                                     88                             
  //    `Y8aaaaa,   8b,dPPYba,  8b,dPPYba, 88 MM88MMM  ,adPPYba,               
  //      `"""""8b, 88P'    "8a 88P'   "Y8 88   88    a8P_____88               
  //            `8b 88       d8 88         88   88    8PP"""""""               
  //    Y8a     a8P 88b,   ,a8" 88         88   88,   "8b,   ,aa               
  //     "Y88888P"  88`YbbdP"'  88         88   "Y888  `"Ybbd8"'               
  //                88                                                         
  //                88                                                         

  // Sprite Shifters
  reg [19:0] r_SPRxSHFA [0:7];
  reg [19:0] r_SPRxSHFB [0:7];
  reg  [7:0] r_spr_lol  [0:7];

  wire w_SPR_SHRES = (r_SPR_RES == 2'b11);
  wire w_SPR_HIRES = (r_SPR_RES == 2'b10) || ((r_SPR_RES == 2'b00) && r_SHRES);
  wire w_SPR_LORES = (r_SPR_RES == 2'b01) || ((r_SPR_RES == 2'b00) && ~r_SHRES);

  reg [15:0] w_spr_bus;
  reg [11:0] r_rhpos_lol;

  integer i_spr;
  always @(posedge clk) begin
    // Sprites shift registers
    if (!c28m) begin
      r_rhpos_lol <= r_rhpos - (r_lol_ena ? 4 : 32);
      for (i_spr = 0; i_spr < 8; i_spr = i_spr + 1) begin
        r_enabled[i_spr] <= r_armed[i_spr];
        if (r_enabled[i_spr] && (r_rhpos_lol == r_SPRxHPOS[i_spr])) begin
          r_SPRxSHFA[i_spr] <= r_SPRxDATA[i_spr];
          r_SPRxSHFB[i_spr] <= r_SPRxDATB[i_spr];

        end else if((w_SPR_SHRES)
                 || (w_SPR_HIRES && (r_rhpos[0:0] == r_SPRxHPOS[i_spr][0:0]))
                 || (w_SPR_LORES && (r_rhpos[1:0] == r_SPRxHPOS[i_spr][1:0]))) begin
          
          r_SPRxSHFA[i_spr] <= {r_SPRxSHFA[i_spr][14:0], 1'b0};
          r_SPRxSHFB[i_spr] <= {r_SPRxSHFB[i_spr][14:0], 1'b0};
        end
      end

      // Sprite Bus
      w_spr_bus <= {
        r_SPRxSHFA[7][15], r_SPRxSHFB[7][15],
        r_SPRxSHFA[6][15], r_SPRxSHFB[6][15],
        r_SPRxSHFA[5][15], r_SPRxSHFB[5][15],
        r_SPRxSHFA[4][15], r_SPRxSHFB[4][15],
        r_SPRxSHFA[3][15], r_SPRxSHFB[3][15],
        r_SPRxSHFA[2][15], r_SPRxSHFB[2][15],
        r_SPRxSHFA[1][15], r_SPRxSHFB[1][15],
        r_SPRxSHFA[0][15], r_SPRxSHFB[0][15]
      } & {16{r_hwin_ena}};
    end
  end

  //      ,ad8888ba,              88  88  88           88                          
  //     d8"'    `"8b             88  88  ""           ""                          
  //    d8'                       88  88                                           
  //    88             ,adPPYba,  88  88  88 ,adPPYba, 88  ,adPPYba,  8b,dPPYba,   
  //    88            a8"     "8a 88  88  88 I8[    "" 88 a8"     "8a 88P'   `"8a  
  //    Y8,           8b       d8 88  88  88  `"Y8ba,  88 8b       d8 88       88  
  //     Y8a.    .a8P "8a,   ,a8" 88  88  88 aa    ]8I 88 "8a,   ,a8" 88       88  
  //      `"Y8888Y"'   `"YbbdP"'  88  88  88 `"YbbdP"' 88  `"YbbdP"'  88       88  

  // Sprite groups        
  wire [3:0] w_spr_clx = {
    (|w_spr_bus[3:0]   & r_ENSP[0]), (|w_spr_bus[7:4]   & r_ENSP[1]),
    (|w_spr_bus[11:8]  & r_ENSP[2]), (|w_spr_bus[15:12] & r_ENSP[3])
  };

  // Bitplane match
  wire [5:0] w_bpl_clx = (w_bpl_bus ^ ~r_MVBP) | (~r_ENBP);

  // Odd and even bitplanes match
  wire   w_odd_clx  = w_bpl_clx[0] | w_bpl_clx[2] | w_bpl_clx[4];
  wire   w_even_clx = w_bpl_clx[1] | w_bpl_clx[3] | w_bpl_clx[5];

  // Sprites-sprites collisions
  assign w_CLXDAT[14] = w_spr_clx[2] & w_spr_clx[3]; // Sprites #4 and #6
  assign w_CLXDAT[13] = w_spr_clx[1] & w_spr_clx[3]; // Sprites #2 and #6
  assign w_CLXDAT[12] = w_spr_clx[1] & w_spr_clx[2]; // Sprites #2 and #4
  assign w_CLXDAT[11] = w_spr_clx[0] & w_spr_clx[3]; // Sprites #0 and #6
  assign w_CLXDAT[10] = w_spr_clx[0] & w_spr_clx[2]; // Sprites #0 and #4
  assign w_CLXDAT[9]  = w_spr_clx[0] & w_spr_clx[1]; // Sprites #0 and #2
  // Sprites-bitplanes collisions
  assign w_CLXDAT[8]  = w_even_clx   & w_spr_clx[3]; // Even and Sprite #6
  assign w_CLXDAT[7]  = w_even_clx   & w_spr_clx[2]; // Even and Sprite #4
  assign w_CLXDAT[6]  = w_even_clx   & w_spr_clx[1]; // Even and Sprite #2
  assign w_CLXDAT[5]  = w_even_clx   & w_spr_clx[0]; // Even and Sprite #0
  assign w_CLXDAT[4]  = w_odd_clx    & w_spr_clx[3]; // Odd and Sprite #6
  assign w_CLXDAT[3]  = w_odd_clx    & w_spr_clx[2]; // Odd and Sprite #4
  assign w_CLXDAT[2]  = w_odd_clx    & w_spr_clx[1]; // Odd and Sprite #2
  assign w_CLXDAT[1]  = w_odd_clx    & w_spr_clx[0]; // Odd and Sprite #0
  // Bitplanes-bitplanes collisions
  assign w_CLXDAT[0]  = w_odd_clx    & w_even_clx;

  //    88888888ba             88                        88                      
  //    88      "8b            ""                        ""   ,d                 
  //    88      ,8P                                           88                 
  //    88aaaaaa8P' 8b,dPPYba, 88  ,adPPYba,  8b,dPPYba, 88 MM88MMM 8b       d8  
  //    88""""""'   88P'   "Y8 88 a8"     "8a 88P'   "Y8 88   88    `8b     d8'  
  //    88          88         88 8b       d8 88         88   88     `8b   d8'   
  //    88          88         88 "8a,   ,a8" 88         88   88,     `8b,d8'    
  //    88          88         88  `"YbbdP"'  88         88   "Y888     Y88'     
  //                                                                    d8'      
  //                                                                   d8'         

  // Playfield visible
  reg [1:0] w_pf_vis;
  always @(*) begin
    // Playfields valid signal
    if (r_DBLPF) begin
      // Dual playfield mode
      w_pf_vis[0] = w_bpl_bus[0] | w_bpl_bus[2] | w_bpl_bus[4];
      w_pf_vis[1] = w_bpl_bus[1] | w_bpl_bus[3] | w_bpl_bus[5];
    end else begin
      // Single playfield mode
      w_pf_vis[0] = 1'b0;
      w_pf_vis[1] = |w_bpl_bus;
    end
  end

  // Playfield Composition
  reg [5:0] bpl_clut;
  always @(posedge clk) begin
    if (c28m) begin
      if (r_DBLPF) begin
        // Dual playfield mode
        if (r_PF2PRI) begin
          // PF2 has priority
          case (w_pf_vis)
            2'b00   : bpl_clut <= 6'b000000;
            2'b01   : bpl_clut <= { 3'b000, w_bpl_bus[4], w_bpl_bus[2], w_bpl_bus[0] };
            default : bpl_clut <= { 3'b001, w_bpl_bus[5], w_bpl_bus[3], w_bpl_bus[1] };
          endcase
        end else begin
          // PF1 has priority
          case (w_pf_vis)
            2'b00   : bpl_clut <= 6'b000000;
            2'b10   : bpl_clut <= { 3'b001, w_bpl_bus[5], w_bpl_bus[3], w_bpl_bus[1] };
            default : bpl_clut <= { 3'b000, w_bpl_bus[4], w_bpl_bus[2], w_bpl_bus[0] };
          endcase
        end
      end else begin
        // Single playfield mode
        if ((r_PF2P[2:1] == 2'b11) && (r_BPU == 3'd5) && (w_bpl_bus[4]))
          // OCS/ECS undocumented behaviour
          bpl_clut <= 6'b010000;
        else
          // Normal behaviour
          bpl_clut <= w_bpl_bus;
      end        
    end
  end

  // Sprite Composition
  wire [2:0] spr_pri = {
    (|w_spr_bus[3:0])   ? 3'd0 :      // Sprites #0 and #1 => group #0
    (|w_spr_bus[7:4])   ? 3'd1 :      // Sprites #2 and #3 => group #1
    (|w_spr_bus[11:8])  ? 3'd2 :      // Sprites #4 and #5 => group #2
    (|w_spr_bus[15:12]) ? 3'd3 : 3'd7 // Sprites #6 and #7 => group #3
  };

  wire [1:0] spr_even = { w_spr_bus[{spr_pri[1:0], 2'b00}], w_spr_bus[{spr_pri[1:0], 2'b01}] };
  wire [1:0] spr_odd  = { w_spr_bus[{spr_pri[1:0], 2'b10}], w_spr_bus[{spr_pri[1:0], 2'b11}] };
  wire       spr_att  = r_SPRxATT[{spr_pri[1:0], 1'b1}] || (r_SPRxATT[{spr_pri[1:0], 1'b0}] && cfg_ecs);

  reg  [3:0] spr_clut;
  reg        spr_vis;

  always @(posedge clk) begin
    if (c28m) begin
      spr_vis <= ~(((spr_pri[0] >= r_PF1P) && (w_pf_vis[0])) || // Playfield #1 test
                   ((spr_pri[1] >= r_PF2P) && (w_pf_vis[1])) || // Playfield #2 test      
                   ((spr_pri[2])));                             // No Sprites visible

           if (spr_att)   spr_clut <= { spr_odd, spr_even };      // Attached sprite
      else if (|spr_even) spr_clut <= { spr_pri[1:0], spr_even }; // Even sprite
      else                spr_clut <= { spr_pri[1:0], spr_odd };  // Odd sprite

    end
  end  

  //    88888888ba    ,ad8888ba,  88888888ba         ,ad8888ba,                                                        
  //    88      "8b  d8"'    `"8b 88      "8b       d8"'    `"8b                ,d                              ,d     
  //    88      ,8P d8'           88      ,8P      d8'        `8b               88                              88     
  //    88aaaaaa8P' 88            88aaaaaa8P'      88          88 88       88 MM88MMM 8b,dPPYba,  88       88 MM88MMM  
  //    88""""88'   88      88888 88""""""8b,      88          88 88       88   88    88P'    "8a 88       88   88     
  //    88    `8b   Y8,        88 88      `8b      Y8,        ,8P 88       88   88    88       d8 88       88   88     
  //    88     `8b   Y8a.    .a88 88      a8P       Y8a.    .a8P  "8a,   ,a88   88,   88b,   ,a8" "8a,   ,a88   88,    
  //    88      `8b   `"Y88888P"  88888888P"         `"Y8888Y"'    `"YbbdP'Y8   "Y888 88`YbbdP"'   `"YbbdP'Y8   "Y888  
  //                                                                                  88                               
  //                                                                                  88                               

  reg [11:0] r_clut_hi;
  reg [11:0] r_clut_lo;
  reg [11:0] r_rgb_out;
  reg [11:0] r_rgb_ham;
  reg        r_zd_clut;
  reg        r_zd;

  always @(*) begin
    r_zd_clut = (!(|bpl_clut) &&  ~r_ZDBPEN & ~r_ZDCTEN)
              | (r_ZDBPEN & bpl_clut[r_ZDBPSEL])
              | (r_COLOR_KEY[bpl_clut] & r_ZDCTEN);

  end

  always @(posedge clk) begin
    // Get both colour lookups
    r_clut_hi <= r_COLORxx_hi[(spr_vis || r_HOMOD) ? (spr_clut) : bpl_clut[3:0]];
    r_clut_lo <= r_COLORxx_lo[bpl_clut[3:0]];

    if (c28m) begin
      // Tack our HAM even behind sprites
      if (w_pixel_clk && r_HOMOD) case (bpl_clut[5:4])
        2'b00 : r_rgb_ham       <= r_clut_lo;     // Select color
        2'b01 : r_rgb_ham[3:0]  <= bpl_clut[3:0]; // Modify blue
        2'b10 : r_rgb_ham[11:8] <= bpl_clut[3:0]; // Modify red
        2'b11 : r_rgb_ham[7:4]  <= bpl_clut[3:0]; // Modify green
      endcase
    end

    // Finally select our pixels
    // if (r_cblank && r_BRDRBLNK) begin
    //   r_rgb_out <= 12'h000;
    //   r_zd <= r_BRDNTRAN;

    // end else 
    if (c28m && spr_vis) begin
      r_rgb_out <= r_clut_hi;
      r_zd <= (r_COLOR_KEY[{1'b1, spr_clut}] & r_ZDCTEN);

    end else if (w_pixel_clk) begin
      if (r_HOMOD) begin
        r_zd <= r_zd_clut && ~(|bpl_clut[5:4]);

      end else if (bpl_clut[5] && ~r_KILLEHB) begin
        r_rgb_out <= (bpl_clut[4])
          ? { 1'b0, r_clut_hi[11:9], 1'b0, r_clut_hi[7:5], 1'b0, r_clut_hi[3:1] }
          : { 1'b0, r_clut_lo[11:9], 1'b0, r_clut_lo[7:5], 1'b0, r_clut_lo[3:1] };
        r_zd <= r_zd_clut;

      end else begin
        r_rgb_out <= (bpl_clut[4]) ? r_clut_hi : r_clut_lo;
        r_zd <= r_zd_clut;

      end
    end
  end

  // RGB output
  assign red     = r_HOMOD ? r_rgb_ham[11:8] : r_rgb_out[11:8];
  assign green   = r_HOMOD ? r_rgb_ham[7:4] : r_rgb_out[7:4];
  assign blue    = r_HOMOD ? r_rgb_ham[3:0] : r_rgb_out[3:0];
  assign zd      = r_zd;
  assign burst   = r_cburst;
endmodule
