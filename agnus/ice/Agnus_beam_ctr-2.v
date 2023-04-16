module Agnus_beam_ctr
(
    input  wire        rst,           // Global synchronous reset
    input  wire        clk,           // Master clock (28/56/85 MHz)
    
    input  wire        cck_r,         // CCK rising edge
    input  wire        cck_f,         // CCK falling edge
    input  wire        cdac_r,        // CDAC rising edge
    
    input  wire        reg_vposr,     // VPOSR access
    input  wire        reg_vposw,     // VPOSW access
    input  wire        reg_vhposr,    // VHPOSR access
    input  wire        reg_vhposw,    // VHPOSW access
    input  wire        reg_hhposr,    // HHPOSR access
    input  wire        reg_hhposw,    // HHPOSW access
    input  wire        reg_bplcon0,   // BPLCON0 access
    input  wire        reg_beamcon0,  // BEAMCON0 access
    input  wire        reg_htotal,    // HTOTAL access
    input  wire        reg_hsstop,    // HSSTOP access
    input  wire        reg_hsstrt,    // HSSTRT access
    input  wire        reg_hbstop,    // HBSTOP access
    input  wire        reg_hbstrt,    // HBSTRT access
    input  wire        reg_hcenter,   // HCENTER access
    input  wire        reg_vtotal,    // VTOTAL access
    input  wire        reg_vsstop,    // VSSTOP access
    input  wire        reg_vsstrt,    // VSSTRT access
    input  wire        reg_vbstop,    // VBSTOP access
    input  wire        reg_vbstrt,    // VBSTRT access
    
    input  wire [15:0] db_i,          // Data bus input
    output wire [15:0] db_o,          // Data bus output
    
    output wire  [8:1] hpos_ctr_o,    // Horizontal position
    output wire [10:0] vpos_ctr_o,    // Vertical position
    output wire        vblank_o,      // Vertical blanking
    output wire        start_o,       // DMA / scanline start
    
    input  wire        hsync_i,       // Horizontal synchro input (genlock)
    output wire        hsync_o,       // Horizontal synchro output
    input  wire        vsync_i,       // Vertical synchro input (genlock)
    output wire        vsync_o,       // Vertical synchro output
    output wire        csync_o,       // Composite synchro output
    
    input  wire        ntsc_n_i,      // PAL (1), NTSC (0)
    input  wire        lpen_n_i       // Light pen trigger
);
    parameter [6:0] CHIP_ID = 7'h22;
    
    // ========================================================================
    // Chip registers read
    // ========================================================================
    
    // Regular VPOSR / VHPOSR / HHPOS registers
    wire [15:0] w_VPOSR =
    {
        r_LOF,
        CHIP_ID[6:5], ~ntsc_n_i, CHIP_ID[3:0],
        r_LOL,
        4'b0000,
        r_VPOS[10:8]
    };
    wire [15:0] w_VHPOSR =
    {
        r_VPOS[7:0],
        r_HPOS[8:1]
    };
    wire [15:0] w_HHPOSR =
    {
        8'b00000000,
        r_HHPOS[8:1]
    };
    // Light pen VPOSR / VHPOSR / HHPOS registers
    wire [15:0] w_VPOSR_lp =
    {
        r_LOF_lp,
        CHIP_ID[6:5], ~ntsc_n_i, CHIP_ID[3:0],
        r_LOL_lp,
        4'b0000,
        r_VPOS_lp[10:8]
    };
    wire [15:0] w_VHPOSR_lp =
    {
        r_VPOS_lp[7:0],
        r_HPOS_lp[8:1]
    };
    wire [15:0] w_HHPOSR_lp =
    {
        8'b00000000,
        r_HHPOS_lp[8:1]
    };
    
    // Register read
    assign db_o =
        w_VPOSR     & {16{reg_vposr  &  r_LPENDIS}} |
        w_VPOSR_lp  & {16{reg_vposr  & ~r_LPENDIS}} |
        w_VHPOSR    & {16{reg_vhposr &  r_LPENDIS}} |
        w_VHPOSR_lp & {16{reg_vhposr & ~r_LPENDIS}} |
        w_HHPOSR    & {16{reg_hhposr &  r_LPENDIS}} |
        w_HHPOSR_lp & {16{reg_hhposr & ~r_LPENDIS}};
    
    // ========================================================================
    // Chip registers write
    // ========================================================================
    
    // BPLCON0[3:1]
    reg         r_LPEN;      // Bit #3
    reg         r_ERSY;      // Bit #2 (TBD)
    reg         r_LACE;      // Bit #1
    
    always @ (posedge clk) begin : BPLCON0_REG
    
        if (rst) begin
            r_LPEN <= 1'b0;
            r_ERSY <= 1'b0;
            r_LACE <= 1'b0;
        end
        else begin
            if (reg_bplcon0) begin
                r_LPEN <= db_i[3];
                r_ERSY <= db_i[2];
                r_LACE <= db_i[1];
            end
        end
    end

    // ========================================================================
    
    // BEAMCON0[14:0]
    reg         r_HARDDIS;   // Bit #14 (TBD)
    reg         r_LPENDIS;   // Bit #13
    reg         r_VARVBEN;   // Bit #12
    reg         r_LOLDIS;    // Bit #11
    reg         r_CSCBEN;    // Bit #10
    reg         r_VARVSYEN;  // Bit #9
    reg         r_VARHSYEN;  // Bit #8
    reg         r_VARBEAMEN; // Bit #7
    reg         r_DUAL;      // Bit #6
    reg         r_PAL;       // Bit #5
    reg         r_VARCSYEN;  // Bit #4
    reg         r_BLANKEN;   // Bit #3
    reg         r_CSYTRUE;   // Bit #2
    reg         r_VSYTRUE;   // Bit #1
    reg         r_HSYTRUE;   // Bit #0
    
    always @ (posedge clk) begin : BEAMCON0_REG
    
        if (rst) begin
            r_HARDDIS   <= 1'b0;
            r_LPENDIS   <= 1'b0;
            r_VARVBEN   <= 1'b0;
            r_LOLDIS    <= 1'b0;
            r_CSCBEN    <= 1'b0;
            r_VARVSYEN  <= 1'b0;
            r_VARHSYEN  <= 1'b0;
            r_VARBEAMEN <= 1'b0;
            r_DUAL      <= 1'b0;
            r_PAL       <= ~ntsc_n_i;
            r_VARCSYEN  <= 1'b0;
            r_BLANKEN   <= 1'b0;
            r_CSYTRUE   <= 1'b0;
            r_VSYTRUE   <= 1'b0;
            r_HSYTRUE   <= 1'b0;
        end
        else begin
            if (reg_beamcon0) begin
                r_HARDDIS   <= db_i[14];
                r_LPENDIS   <= db_i[13];
                r_VARVBEN   <= db_i[12];
                r_LOLDIS    <= db_i[11];
                r_CSCBEN    <= db_i[10];
                r_VARVSYEN  <= db_i[9];
                r_VARHSYEN  <= db_i[8];
                r_VARBEAMEN <= db_i[7];
                r_DUAL      <= db_i[6];
                r_PAL       <= db_i[5];
                r_VARCSYEN  <= db_i[4];
                r_BLANKEN   <= db_i[3];
                r_CSYTRUE   <= db_i[2];
                r_VSYTRUE   <= db_i[1];
                r_HSYTRUE   <= db_i[0];
            end
        end
    end
    
    // ========================================================================
    
    // HTOTAL[7:0]
    reg   [7:0] r_HTOTAL;
    // HSSTOP[7:0]
    reg   [7:0] r_HSSTOP;
    // HSSTRT[7:0]
    reg   [7:0] r_HSSTRT;
    // HBSTOP[7:0]
    reg   [7:0] r_HBSTOP;
    // HBSTRT[7:0]
    reg   [7:0] r_HBSTRT;
    // HCENTER[7:0]
    reg   [7:0] r_HCENTER;
    
    always @ (posedge clk) begin : HBEAM_REG
    
        if (rst) begin
            r_HTOTAL  <= 8'd226; // To have HHPOS following HPOS
            r_HSSTOP  <= 8'd0;
            r_HSSTRT  <= 8'd0;
            r_HBSTOP  <= 8'd0;
            r_HBSTRT  <= 8'd0;
            r_HCENTER <= 8'd0;
        end
        else begin
            if (reg_htotal)  r_HTOTAL  <= db_i[7:0];
            if (reg_hsstop)  r_HSSTOP  <= db_i[7:0];
            if (reg_hsstrt)  r_HSSTRT  <= db_i[7:0];
            if (reg_hbstop)  r_HBSTOP  <= db_i[7:0];
            if (reg_hbstrt)  r_HBSTRT  <= db_i[7:0];
            if (reg_hcenter) r_HCENTER <= db_i[7:0];
        end
    end
    
    // ========================================================================
    
    // VTOTAL[10:0]
    reg  [10:0] r_VTOTAL;
    // HSSTOP[10:0]
    reg  [10:0] r_VSSTOP;
    // HSSTRT[10:0]
    reg  [10:0] r_VSSTRT;
    // HBSTOP[10:0]
    reg  [10:0] r_VBSTOP;
    // HBSTRT[10:0]
    reg  [10:0] r_VBSTRT;
    
    always @ (posedge clk) begin : VBEAM_REG
    
        if (rst) begin
            r_VTOTAL <= 11'd0;
            r_VSSTOP <= 11'd0;
            r_VSSTRT <= 11'd0;
            r_VBSTOP <= 11'd0;
            r_VBSTRT <= 11'd0;
        end
        else begin
            if (reg_vtotal)  r_VTOTAL  <= db_i[10:0];
            if (reg_vsstop)  r_VSSTOP  <= db_i[10:0];
            if (reg_vsstrt)  r_VSSTRT  <= db_i[10:0];
            if (reg_vbstop)  r_VBSTOP  <= db_i[10:0];
            if (reg_vbstrt)  r_VBSTRT  <= db_i[10:0];
        end
    end
    
    // ========================================================================
    // Clock domain crossing for HSYNC
    // ========================================================================
    
    reg [2:0] r_hsync_cc;
    
    always @ (posedge clk) begin : HSYNC_CC
    
        r_hsync_cc[0] <= hsync_i;
        r_hsync_cc[1] <= r_hsync_cc[0];
        
        // Synchronize on CCK's rising edge
        // Take care of the polarity
        if (cck_r) begin
            r_hsync_cc[2] <= r_hsync_cc[1] ^ ~r_HSYTRUE;
        end
    end
    
    // ========================================================================
    // Horizontal counter
    // ========================================================================
    
    // Long line flip-flop
    reg         r_LOL;
    // Horizontal counter
    reg   [8:1] r_HPOS;
    
    always @ (posedge clk) begin : HPOS_CTR
        reg v_hend;
    
        if (rst) begin
            r_HPOS <= 8'd0;
            r_LOL  <= 1'b0;
            v_hend <= 1'b0;
        end
        else begin
            // Load HPOS when VHPOSW is written
            if (reg_vhposw) begin
                r_HPOS <= db_i[7:0];
            end
            else if (cck_f) begin
                r_HPOS <= (v_hend) ? 8'd0 : r_HPOS + 8'd1;
            end
            
            // Horizontal end
            v_hend <= (r_LOL)
                    ? r_HC227 | r_HEND_d & r_VARBEAMEN  // Long line
                    : r_HC226 | r_HEND   & r_VARBEAMEN; // Short line
                
            // Clear LOL flag in PAL mode or when VPOSW is written
            if (r_PAL | r_LOLDIS | reg_vposw) begin
                r_LOL <= 1'b0;
            end
            // Otherwise, toggle LOL flag when HPOS = 1
            else begin
                r_LOL <= r_LOL ^ (r_HC1 & cck_f);
            end
        end
    end
    
    assign hpos_ctr_o = r_HPOS;
    
    // ========================================================================
    // Second horizontal counter
    // ========================================================================
    
    // Second horizontal counter
    reg   [8:1] r_HHPOS;
    
    always @ (posedge clk) begin : HHPOS_CTR
        reg v_hend;
    
        if (rst) begin
            r_HHPOS <= 8'd0;
            v_hend <= 1'b0;
        end
        else begin
            // Load HPOS when VHPOSW is written
            if (reg_hhposw) begin
                r_HHPOS <= db_i[7:0];
            end
            else if (cck_f) begin
                r_HHPOS <= (v_hend) ? 8'd0 : r_HHPOS + 8'd1;
            end
            
            // Horizontal end
            v_hend <= (r_LOL)  // HHPOS should have its own LOL flag ???
                    ? r_HEND_d // Long line
                    : r_HEND;  // Short line
        end
    end
    
    // ========================================================================
    // Horizontal counter comparators
    // ========================================================================
    
    // Those specific HPOS values follow NTSC/PAL Agnus datasheet page 39
    wire w_HC0   = (r_HPOS == 8'd0)   ? 1'b1 : 1'b0;
    wire w_HC1   = (r_HPOS == 8'd1)   ? 1'b1 : 1'b0;
    wire w_HC9   = (r_HPOS == 8'd9)   ? 1'b1 : 1'b0;
    wire w_HC18  = (r_HPOS == 8'd18)  ? 1'b1 : 1'b0;
    wire w_HC26  = (r_HPOS == 8'd26)  ? 1'b1 : 1'b0;
    wire w_HC35  = (r_HPOS == 8'd35)  ? 1'b1 : 1'b0;
    wire w_HC115 = (r_HPOS == 8'd115) ? 1'b1 : 1'b0;
    wire w_HC132 = (r_HPOS == 8'd132) ? 1'b1 : 1'b0;
    wire w_HC140 = (r_HPOS == 8'd140) ? 1'b1 : 1'b0;
    wire w_HC226 = (r_HPOS == 8'd226) ? 1'b1 : 1'b0;

    // ========================================================================
    
    // Start of line :
    // Freeze HPOS when GENLOCK is active and no HSYNC
    reg         r_HC0;
    // LOL flag toggle
    // VPOS management
    // Start of fixed DMAs
    // VB pulse (de-)assertion
    // Serration pulse de-assertion
    reg         r_HC1;
    // VE pulse assertion (Odd field, PAL & NTSC)
    // VE pulse de-assertion (Even field PAL, Odd field NTSC)
    reg         r_HC9; // a.k.a VR1
    // HSYNC pulse assertion (PAL & NTSC)
    // 1st equalization pulse assertion (PAL & NTSC)
    // 1st serration pulse assertion (PAL & NTSC)
    reg         r_HC18; // a.k.a SHS
    // 1st equalization pulse de-assertion (PAL)
    reg         r_HC26; // a.k.a VER1_P
    // 1st equalization pulse de-assertion (NTSC)
    reg         r_HC27; // a.k.a VER1_N
    // HSYNC pulse de-assertion (PAL & NTSC)
    reg         r_HC35; // a.k.a RHS
    // VE pulse assertion (Even field, PAL & NTSC)
    // VE pulse de-assertion (Odd field PAL, Even field NTSC)
    // 1st serration pulse de-assertion (PAL & NTSC)
    reg         r_HC115; // a.k.a VR2
    // 2nd serration pulse assertion (PAL & NTSC)
    // 2nd equalization pulse assertion (PAL & NTSC)
    reg         r_HC132; // a.k.a CEN
    // 2nd equalization pulse de-assertion (PAL)
    reg         r_HC140; // a.k.a VER2_P
    // 2nd equalization pulse de-assertion (NTSC)
    reg         r_HC141; // a.k.a VER2_N
    // End of PAL line
    // End of NTSC short line
    reg         r_HC226;
    // End of NTSC long line
    reg         r_HC227;
    
    // End of line
    reg         r_HEND;   // LOL = 0
    reg         r_HEND_d; // LOL = 1
    // Middle of line
    reg         r_HMID;
    // HSYNC de-assertion
    reg         r_HS_clr;
    // HSYNC assertion
    reg         r_HS_set;
    // HBLANK de-assertion
    reg         r_HB_clr;
    // HBLANK assertion
    reg         r_HB_set;
    // DUAL mode
    wire  [8:1] w_hpos = (r_DUAL) ? r_HHPOS : r_HPOS;
    
    always @ (posedge clk) begin : HCOMPARE_REG
    
        if (cck_r) begin
            r_HC0    <= w_HC0;
            r_HC1    <= w_HC1;
            r_HC9    <= w_HC9;
            r_HC18   <= w_HC18;
            r_HC26   <= w_HC26 & r_VE & ~r_OLDVSY;
            r_HC35   <= w_HC35;
            r_HC115  <= w_HC115;
            r_HC132  <= w_HC132;
            r_HC140  <= w_HC140 & r_VE & ~r_OLDVSY;
            r_HC226  <= w_HC226 & ~r_VARBEAMEN;
            
            // Delayed horizontal compare (it saves some LUTs)
            r_HC27   <= r_HC26;
            r_HC141  <= r_HC140;
            r_HC227  <= r_HC226;
            r_HEND_d <= r_HEND;
            
            // Variable beam compare
            r_HEND   <= (w_hpos == r_HTOTAL)  ? 1'b1 : 1'b0;
            r_HMID   <= (w_hpos == r_HCENTER) ? 1'b1 : 1'b0;
            r_HS_clr <= (w_hpos == r_HSSTOP)  ? 1'b1 : 1'b0;
            r_HS_set <= (w_hpos == r_HSSTRT)  ? 1'b1 : 1'b0;
            r_HB_clr <= (w_hpos == r_HBSTOP)  ? 1'b1 : 1'b0;
            r_HB_set <= (w_hpos == r_HBSTRT)  ? 1'b1 : 1'b0;
        end
    end
    
    assign start_o = r_HC1;

    // ========================================================================
    // Vertical counter
    // ========================================================================
    
    // Long field flip-flop
    reg         r_LOF;
    // Vertical counter
    reg  [10:0] r_VPOS;
    
    always @ (posedge clk) begin : VPOS_CTR
        reg v_vend;
        reg v_cout;
    
        if (rst) begin
            r_VPOS <= 11'd0;
            r_LOF  <= 1'b0;
            v_vend <= 1'b0;
            v_cout <= 1'b0;
        end
        else begin
            // Load VPOS LSB when VHPOSW is written
            if (reg_vhposw) begin
                r_VPOS[7:0] <= db_i[15:8];
            end
            // VPOS LSB management when HPOS = 1
            else if (r_HC1 & cck_f) begin
                if (v_vend) begin
                    r_VPOS[7:0] <= 8'd0;
                end
                else begin
                    r_VPOS[7:0] <= r_VPOS[7:0] + 8'd1;
                end
            end
            
            // Load VPOS MSB and LOF when VPOSW is written
            if (reg_vposw) begin
                r_VPOS[10:8] <= db_i[2:0];
                r_LOF        <= db_i[15];
            end
            // VPOS MSB management when HPOS = 1
            else if (r_HC1 & cck_f) begin
                if (v_vend) begin
                    r_VPOS[10:8] <= 3'd0;
                    r_LOF        <= ~r_LOF & r_LACE;
                end
                else begin
                    r_VPOS[10:8] <= r_VPOS[10:8] + { 2'b00, v_cout };
                end
            end
            
            // Vertical end : reset VPOS counter
            if (r_LOF) begin
                // Long field vertical end
                v_vend <= r_VC262 | r_VC312 | r_VEND_d;
            end
            else begin
                // Short field vertical end
                v_vend <= r_VC261 | r_VC311 | r_VEND;
            end
            
            // LSB -> MSB carry out
            v_cout <= &r_VPOS[7:0];
        end
    end
    
    assign vpos_ctr_o = r_VPOS;
    
    // ========================================================================
    // Vertical counter comparators
    // ========================================================================
    
    // Those specific VPOS values follow NTSC/PAL Agnus datasheet page 39
    wire w_VC0   = (r_VPOS == 11'd0  ) ? 1'b1 : 1'b0;
    wire w_VC2   = (r_VPOS == 11'd2  ) ? 1'b1 : 1'b0;
    wire w_VC5   = (r_VPOS == 11'd5  ) ? 1'b1 : 1'b0;
    wire w_VC20  = (r_VPOS == 11'd20 ) ? 1'b1 : 1'b0;
    wire w_VC25  = (r_VPOS == 11'd25 ) ? 1'b1 : 1'b0;
    wire w_VC261 = (r_VPOS == 11'd261) ? 1'b1 : 1'b0;
    wire w_VC311 = (r_VPOS == 11'd311) ? 1'b1 : 1'b0;
    
    // ========================================================================
    
    // PAL or NTSC vertical equalization start
    reg         r_VC0;
    // PAL vertical synchro start (short field)
    reg         r_VC2;
    // PAL vertical synchro start (long field)
    // NTSC vertical synchro start (both fields)
    reg         r_VC3;
    // PAL vertical synchro stop (both fields)
    reg         r_VC5;
    // NTSC vertical synchro stop (both fields)
    reg         r_VC6;
    // PAL vertical equalization stop (short field)
    reg         r_VC7;
    // PAL vertical equalization stop (long field)
    reg         r_VC8;
    // NTSC vertical equalization stop (both fields)
    reg         r_VC9;
    // NTSC vertical blanking stop
    reg         r_VC20; // a.k.a RVB_N
    // PAL vertical blanking stop
    reg         r_VC25; // a.k.a RVB_P
    // NTSC vertical end (short field)
    reg         r_VC261;
    // NTSC vertical end (long field)
    reg         r_VC262;
    // PAL vertical end (short field)
    reg         r_VC311;
    // PAL vertical end (long field)
    reg         r_VC312;
    
    // End of field
    reg         r_VEND;   // LOF = 0
    reg         r_VEND_d; // LOF = 1
    // VSYNC de-assertion
    reg         r_VS_clr;
    // VSYNC assertion
    reg         r_VS_set;
    // VBLANK de-assertion
    reg         r_VB_clr;
    // VBLANK assertion
    reg         r_VB_set;
    
    always @ (posedge clk) begin : VCOMPARE_REG
    
        if (cck_r) begin
            r_VC0    <= w_VC0;
            r_VC2    <= w_VC2;
            r_VC5    <= w_VC5;
            r_VC20   <= w_VC20 & ~r_PAL;
            r_VC25   <= w_VC25 &  r_PAL;
            r_VC261  <= w_VC261 & ~r_PAL & ~r_VARBEAMEN;
            r_VC311  <= w_VC311 &  r_PAL & ~r_VARBEAMEN;
            
            // Variable beam compare (when HPOS = 1)
            r_VEND   <= (r_VPOS == r_VTOTAL) ? r_VARBEAMEN : 1'b0;
            r_VS_clr <= (r_VPOS == r_VSSTOP) ?        1'b1 : 1'b0;
            r_VS_set <= (r_VPOS == r_VSSTRT) ?        1'b1 : 1'b0;
            r_VB_clr <= (r_VPOS == r_VBSTOP) ?        1'b1 : 1'b0;
            r_VB_set <= (r_VPOS == r_VBSTRT) ?        1'b1 : 1'b0;
            
            // Delayed vertical compare (it saves some LUTs)
            if (r_HC0) begin
                r_VC3    <= r_VC2;
                r_VC6    <= r_VC5;
                r_VC7    <= r_VC6;
                r_VC8    <= r_VC7;
                r_VC9    <= r_VC8;
                r_VC262  <= r_VC261;
                r_VC312  <= r_VC311;
                r_VEND_d <= r_VEND & r_LOF;
            end
        end
    end
    
    // ========================================================================
    // Horizontal synchronization
    // ========================================================================
    
    // OCS HSYNC (PAL or NTSC)
    reg         r_OLDHSY;
    // ECS HSYNC (new video modes)
    reg         r_VARHSY;
    // Muxed HSYNC / CSYNC
    reg         r_MUXHSY;
    // Delayed HSYNC (Long line support)
    reg         r_LOLHSY;
    // HSYNC pin output
    reg         r_HSY;
    
    always @ (posedge clk) begin : HSYNC_REG
    
        if (rst) begin
            r_OLDHSY <= 1'b0;
            r_VARHSY <= 1'b0;
            r_MUXHSY <= 1'b0;
            r_LOLHSY <= 1'b0;
            r_HSY    <= 1'b0;
        end
        else begin
            // Re-synchronize HSYNC with CDAC clock
            if (cdac_r) begin
                // Take into account LOL state and signal polarity
                r_HSY <= ((r_LOL) ? r_LOLHSY : r_MUXHSY) ^ ~r_HSYTRUE;
            end
            
            // Half CCK cycle delay for LOL support
            if (cck_f) begin
                r_LOLHSY <= r_MUXHSY;
            end
            
            if (cck_f) begin
                // PAL or NTSC HSYNC
                r_OLDHSY <= (r_OLDHSY | r_HC18) & ~r_HC35;
                // Variable HSYNC
                r_VARHSY <= (r_VARHSY | r_HS_set) & ~r_HS_clr;
            end
            
            // Select the correct HSYNC / CSYNC signal
            casez ({ r_CSCBEN, r_VARHSYEN })
                2'b00 : r_MUXHSY <= r_OLDHSY; // PAL or NTSC
                2'b?1 : r_MUXHSY <= r_VARHSY; // New video modes
                2'b10 : r_MUXHSY <= r_VARCSY; // Dual mode
            endcase
        end
    end
    
    assign hsync_o = r_HSY;
    
    // ========================================================================
    // Composite synchronization
    // ========================================================================
    
    // OCS CSYNC (PAL or NTSC)
    reg         r_OLDCSY;
    // ECS CSYNC (new video modes)
    reg         r_VARCSY;
    // Muxed CSYNC / CBLANK
    reg         r_MUXCSY;
    // Delayed CSYNC (Long line support)
    reg         r_LOLCSY;
    // CSYNC pin output
    reg         r_CSY;
    
    always @ (posedge clk) begin : CSYNC_REG
        reg v_clr_e;
        reg v_clr_o;
        reg v_set_o;
        reg v_clr_v;
        reg v_set_v;
    
        if (rst) begin
            r_OLDCSY <= 1'b0;
            r_VARCSY <= 1'b0;
            r_MUXCSY <= 1'b0;
            r_LOLCSY <= 1'b0;
            r_CSY    <= 1'b0;
            v_clr_e  <= 1'b0;
            v_clr_o  <= 1'b0;
            v_set_o  <= 1'b0;
            v_clr_v  <= 1'b0;
            v_set_v  <= 1'b0;
        end
        else begin
            // Re-synchronize CSYNC with CDAC clock
            if (cdac_r) begin
                // Take into account LOL state and signal polarity
                r_CSY <= ((r_LOL) ? r_LOLCSY : r_MUXCSY) ^ ~r_CSYTRUE;
            end
            
            // Half CCK cycle delay for LOL support
            if (cck_f) begin
                r_LOLCSY <= r_MUXCSY;
            end
            
            if (cck_f) begin
                // PAL or NTSC CSYNC
                r_OLDCSY <= (r_OLDCSY | v_set_o) & ~(v_clr_e | v_clr_o);
                // Variable CSYNC
                r_VARCSY <= (r_VARCSY | v_set_v) & ~v_clr_v;
            end
            
            // Select the correct CSYNC / CBLANK signal
            casez ({ r_BLANKEN, r_VARCSYEN })
                2'b00 : r_MUXCSY <= r_OLDCSY; // PAL or NTSC
                2'b?1 : r_MUXCSY <= r_VARCSY; // New video modes
                2'b10 : r_MUXCSY <= r_VARCB;  // Composite blanking to Denise
            endcase
            
            // CSYNC clear (during equalization)
            if (r_PAL) begin
                // PAL : cycle #26 or cycle #140
                v_clr_e <= r_HC26 | r_HC140;
            end
            else begin
                // NTSC : cycle #27 or cycle #141
                v_clr_e <= r_HC27 | r_HC141;
            end
            
            // CSYNC clear : cycle #1 or cycle #115 (during VSYNC) otherwise, cycle #35
            v_clr_o <= (r_OLDVSY) ? r_HC1 | r_HC115 : r_HC35;
            // CSYNC set : cycle #18 or cycle #132 (during equalization)
            v_set_o <= r_HC18 | r_HC132 & r_VE;
            
            // VARCSY clear
            v_clr_v <= (r_PREVSY) ? r_HB_clr | r_HB_set : r_HS_clr;
            // VARCSY set
            v_set_v <= (r_PREVSY) ? r_HS_set | r_HMID   : r_HS_set;
        end
    end
    
    assign csync_o = r_CSY;
    
    // ========================================================================
    // Vertical synchronization
    // ========================================================================
    
    // OCS VSYNC (PAL or NTSC)
    reg         r_OLDVSY;
    // ECS VSYNC (new video modes)
    reg         r_PREVSY; // Used by VARCSY
    reg         r_VARVSY;
    // Muxed VSYNC / CBLANK
    reg         r_MUXVSY;
    // VSYNC pin output
    reg         r_VSY;
    
    always @ (posedge clk) begin : VSYNC_REG
        reg v_clr_o;
        reg v_set_o;
        reg v_clr_v;
        reg v_set_v;
        
        if (rst) begin
            r_OLDVSY <= 1'b0;
            r_PREVSY <= 1'b0;
            r_VARVSY <= 1'b0;
            r_MUXVSY <= 1'b0;
            r_VSY    <= 1'b0;
            v_clr_o  <= 1'b0;
            v_set_o  <= 1'b0;
            v_clr_v  <= 1'b0;
            v_set_v  <= 1'b0;
        end
        else begin
            // Re-synchronize VSYNC with CDAC clock
            if (cdac_r) begin
                // Take into account the signal polarity
                // No LOL support !
                r_VSY <= r_MUXVSY ^ ~r_VSYTRUE;
            end
            
            if (cck_f) begin
                // PAL or NTSC VSYNC
                r_OLDVSY <= (r_OLDVSY | v_set_o) & ~v_clr_o;
                // Variable VSYNC
                r_VARVSY <= r_PREVSY;
            end
            
            // Select the correct VSYNC / CBLANK signal
            casez ({ r_CSCBEN, r_VARVSYEN })
                2'b00 : r_MUXVSY <= r_OLDVSY; // PAL or NTSC
                2'b?1 : r_MUXVSY <= r_VARVSY; // New video modes
                2'b10 : r_MUXVSY <= r_VARCB;  // Dual mode
            endcase
            
            // VSYNC clear and set
            if (r_PAL) begin
                // PAL case
                v_clr_o <= (r_LOF) ? r_HC132 & r_VC5 : r_HC18 & r_VC5;
                v_set_o <= (r_LOF) ? r_HC18 & r_VC3 : r_HC132 & r_VC2;
            end
            else begin
                // NTSC case
                v_clr_o <= (r_LOF) ? r_HC132 & r_VC6 : r_HC18 & r_VC6;
                v_set_o <= (r_LOF) ? r_HC132 & r_VC3 : r_HC18 & r_VC3;
            end
            
            // Variable VSYNC
            r_PREVSY <= (r_VARVSY | v_set_v) & ~v_clr_v;
            v_clr_v  <= (r_LOF) ? r_HMID & r_VS_clr : r_HS_set & r_VS_clr;
            v_set_v  <= (r_LOF) ? r_HMID & r_VS_set : r_HS_set & r_VS_set;
        end
    end
    
    assign vsync_o = r_VSY;
    
    // ========================================================================
    // Vertical equalization
    // ========================================================================
    
    // Vertical equalization flag for CSYNC generation (PAL or NTSC)
    reg         r_VE;
    
    always @ (posedge clk) begin : VEQUAL_REG
        reg v_set;
        reg v_clr;
    
        if (rst) begin
            r_VE  <= 1'b0;
            v_clr <= 1'b0;
            v_set <= 1'b0;
        end
        else begin
            if (cck_f) begin
                r_VE <= (r_VE | v_set) & ~v_clr;
            end
            
            // Vertical equalization clear
            if (r_PAL) begin
                // PAL mode
                v_clr <= (r_LOF) ? r_HC9 & r_VC8 : r_HC115 & r_VC7;
            end
            else begin
                // NTSC mode
                v_clr <= (r_LOF) ? r_HC115 & r_VC9 : r_HC9 & r_VC9;
            end
            
            // Vertical equalization set
            v_set <= (r_LOF) ? r_HC115 & r_VC0 : r_HC9 & r_VC0;
        end
    end
    
    // ========================================================================
    // Horizontal and composite blanking
    // ========================================================================
    
    // ECS HBLANK
    reg         r_VARHB;
    // ECS CBLANK
    reg         r_VARCB;
    
    always @ (posedge clk) begin : HCBLANK_REG
    
        if (rst) begin
            r_VARHB <= 1'b0;
            r_VARCB <= 1'b0;
        end
        else begin
            if (cck_f) begin
                // Variable HBLANK
                r_VARHB <= (r_VARHB | r_HB_set) & ~r_HB_clr;
                // Variable CBLANK
                r_VARCB <= r_VARVB | ((r_VARHB | r_HB_set) & ~r_HB_clr);
            end
        end
    end
    
    // ========================================================================
    // Vertical blanking
    // ========================================================================
    
    // OCS VBLANK (PAL or NTSC)
    reg         r_OLDVB;
    // ECS VBLANK (new video modes)
    reg         r_VARVB;
    
    always @ (posedge clk) begin : VBLANK_REG
        reg v_vend;
    
        if (rst) begin
            r_OLDVB <= 1'b1;
            r_VARVB <= 1'b0;
        end
        else begin
            if (r_LOF) begin
                // Short field vertical end
                v_vend = r_VC262 | r_VC312;
            end
            else begin
                // Long field vertical end
                v_vend = r_VC261 | r_VC311;
            end
            
            // NTSC blanking lines : 261/262, 0 .. 19
            // PAL blanking lines : 311/312, 0 .. 24
            r_OLDVB <= (r_OLDVB | v_vend) & ~(r_VC20 | r_VC25);
            // Variable VBLANK
            r_VARVB <= (r_VARVB | r_VB_set) & ~r_VB_clr;
        end
    end
    
    assign vblank_o = (r_VARVBEN) ? r_VARVB : r_OLDVB;
    
    // ========================================================================
    // Light pen coordinates
    // ========================================================================
    
    // Latch enable
    reg         r_HVL;
    // HPOS latch
    reg   [8:1] r_HPOS_lp;
    // LOL latch
    reg         r_LOL_lp;
    // VPOS latch
    reg  [10:0] r_VPOS_lp;
    // LOF latch
    reg         r_LOF_lp;
    // HHPOS latch
    reg   [8:1] r_HHPOS_lp;
    
    always @ (posedge clk) begin : LPEN_REG
        reg [1:0] v_lpen_cc;
    
        if (rst) begin
            r_HVL      <= 1'b0;
            r_HPOS_lp  <= 8'd0;
            r_LOL_lp   <= 1'b0;
            r_VPOS_lp  <= 11'd0;
            r_LOF_lp   <= 1'b0;
            r_HHPOS_lp <= 8'd0;
            v_lpen_cc  <= 2'b11;
        end
        else begin
            // Latch light pen coordinates
            if (r_HVL & r_LPEN & cck_r) begin
                r_HPOS_lp  <= r_HPOS;
                r_LOL_lp   <= r_LOL;
                r_VPOS_lp  <= r_VPOS;
                r_LOF_lp   <= r_LOF;
                r_HHPOS_lp <= r_HHPOS;
            end
            
            // HPOS / VPOS / HHPOS latch enable
            if (cck_r) begin
                r_HVL <= ~(v_lpen_cc[1] | r_HC0 | r_HC1 | (r_VARVBEN) ? r_VARVB : r_OLDVB);
            end
            
            // Clock domain crossing
            v_lpen_cc <= { v_lpen_cc[0], lpen_n_i };
        end
    end
    
endmodule
