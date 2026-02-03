/*
 * CIA 8520 module
 * Written by Rodolphe de Saint Léger (original code from Niklas Ekström).
 *
 * This implementation WILL NOT apply CIA undocumented features.
 *
 * Changes against CIA documented features (available as extensions in spare register) :
 * - module is able of phi2 divided by 2 serial I/O (not available in original 8520)
 * - cnt input can be synchronized one clock earlier
 * - timer A/B can switch to half clock pulses if timer count and latch are both 0 and timer run continuously
 * - reload delay when timer A/B underflows can be removed
 *
 * the spare register is used to enable extensions:
 * - Bit 0 : short cnt sampling,
 * - Bit 1 : half clk pulses on port B (only visible if fast reload enabled)
 * - Bit 2 : fast reload (if enabled with short cnt sampling, enable fast serial as side effect)
 *
 * Design :
 * - reads are valid for one clock cycle, starting at posedge (combinatorial only)
 *   since data must be set shortly after posedge and shortly around negedge (internal cia clock signals)
 * - writes are done on negedge,
 * - irqs are detected on posedge and delivered on negedge (clear is done when releasing nCS after a read),
 * - tod, cnt, flag, sp and ports A/B are sampled at posedge
 * - outputs change on negedge (cnt, pc, sp, port A/B)
 * - timers decrement on posedges
 * - tod increment at negedges
 * - single serial data/shift register for input and output (documentation does not specify if only one register is used)
 */
module cia8520(
    input nRES, // /RES input (active low)
    input ECLK, // phi2 clock input

    input        nCS, // /cs input (active low)
    input  [3:0] RS,  // RS3-RS0 register address
    input        RW,  // R/W input (high for read, low for write)
    input  [7:0] DBi, // data input
    output [7:0] DBo, // data output

    input  [7:0] PRAi, // port A input
    output [7:0] PRAo, // port A output
    output [7:0] PRAd, // port A direction

    input  [7:0] PRBi, // port B input
    output [7:0] PRBo, // port B output
    output [7:0] PRBd, // port B direction

    input      nFLAG, // /FLAG input (active low)
    output reg nPC,   // /PC output (active low)

    input  SPi, // serial port in
    output SPo, // serial port out
    output SPd, // serial port direction (1 = output, 0 = input)

    input      CNTi, // cnt in
    output reg CNTo, // cnt out

    input TOD, // TOD counter input

    output nIRQ // /IRQ output (active low)
  );

  // convert input signals to active high
  wire rst_i = ~nRES;
  wire sel_i = ~nCS;
  wire we_i  = ~RW;

  wire adr_pra;
  wire adr_prb;
  wire adr_ddra;
  wire adr_ddrb;
  wire adr_talo;
  wire adr_tahi;
  wire adr_tblo;
  wire adr_tbhi;
  wire adr_todlo;
  wire adr_todmi;
  wire adr_todhi;
  wire adr_ext;
  wire adr_sdr;
  wire adr_icr;
  wire adr_cra;
  wire adr_crb;

  // extensions register

  wire sel_ext = sel_i & adr_ext;

  reg fcnt_r; // enable fast cnt sync
  reg fste_r; // enable half pulses on port B (for timer A/B)
  reg frle_r; // enable fast timer reload (no dead cycle on timer A/B)

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      fcnt_r <= 1'b0;
      fste_r <= 1'b0;
      frle_r <= 1'b0;
    end
    else if (sel_ext & we_i)
    begin
      // handle write to extension register
      fcnt_r <= DBi[0];
      fste_r <= DBi[1];
      frle_r <= DBi[2];
    end
  end

  // cnt/sp synchronization
  reg [3:0] cnt_s;
  reg [2:0] spi_s;

  wire cnt_pls = ~cnt_s[3] & cnt_s[2];

  always @(posedge ECLK)
  begin
    // start cnt signal sync
    cnt_s[0] <= CNTi;
    spi_s[0] <= SPi;

    // wait one extra posedge unless fast cnt sync is enabled
    cnt_s[1] <= fcnt_r ? CNTi : cnt_s[0];
    spi_s[1] <= fcnt_r ? SPi : spi_s[0];
  end

  always @(negedge ECLK)
  begin
    // end cnt signal sync and trigger pulse for 1 clock cycle
    { cnt_s[3:2] } <= { cnt_s[2:1] };
    spi_s[2] <= spi_s[1];
  end

  // control register A

  wire sel_cra = sel_i & adr_cra;

  reg cra_strt;
  reg cra_pbon;
  reg cra_otmd;
  reg cra_rnmd;
  reg cra_inmd;
  reg cra_spmd;

  assign SPd = cra_spmd;

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      cra_pbon <= 1'b0;
      cra_otmd <= 1'b0;
      cra_rnmd <= 1'b0;
      cra_inmd <= 1'b0;
      cra_spmd <= 1'b0;
    end
    else if (sel_cra & we_i)
    begin
      // handle write to cra (except for start and force load)
      cra_pbon <= DBi[1];
      cra_otmd <= DBi[2];
      cra_rnmd <= DBi[3];
      cra_inmd <= DBi[5];
      cra_spmd <= DBi[6];
    end
  end

  // control register B

  wire sel_crb = sel_i & adr_crb;

  reg       crb_strt;
  reg       crb_pbon;
  reg       crb_otmd;
  reg       crb_rnmd;
  reg [1:0] crb_inmd;
  reg       crb_alrm;

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      crb_pbon <= 1'b0;
      crb_otmd <= 1'b0;
      crb_rnmd <= 1'b0;
      crb_inmd <= 2'b0;
      crb_alrm <= 1'b0;
    end
    else if (sel_crb & we_i)
    begin
      // handle write to crb (except for start and force load)
      crb_pbon <= DBi[1];
      crb_otmd <= DBi[2];
      crb_rnmd <= DBi[3];
      crb_inmd <= DBi[6:5];
      crb_alrm <= DBi[7];
    end
  end

  // TOD counter

  wire [23:0] tod_latch; // tod_latch from tod helper
  wire        alrm_pls;  // alrm pulse from tod helper
  wire        tod_tck;   // tod count enable from tod helper

  reg  [23:0] tod_count; // tod counter
  reg  [23:0] tod_alrm;  // tod alrm
  reg         tod_pls;

  wire sel_tod = sel_i & (adr_todlo | adr_todmi | adr_todhi);

  cia_tod tod(
            .clk_i(ECLK),
            .rst_i(rst_i),
            .tod_i(TOD),
            .sel_i(sel_tod),
            .we_i(we_i),
            .sel_alrm_i(crb_alrm),
            .sel_todlo_i(adr_todlo),
            .sel_todmi_i(adr_todmi),
            .sel_todhi_i(adr_todhi),
            .alrm_i(tod_alrm),
            .count_i(tod_count),
            .latch_o(tod_latch),
            .cnt_o(tod_tck),
            .cnt_i(tod_pls),
            .pls_o(alrm_pls)
          );

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      tod_count <= 24'b0;
      tod_pls <= 1'b0;
    end
    else if (sel_tod & we_i & ~crb_alrm)
    begin
      tod_pls <= 1'b0;

      if (adr_todlo)
        tod_count[7:0] <= DBi;
      if (adr_todmi)
        tod_count[15:8] <= DBi;
      if (adr_todhi)
        tod_count[23:16] <= DBi;
    end
    else
    begin
      tod_pls <= tod_tck;
      tod_count <= tod_count + tod_tck;
    end
  end

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      tod_alrm <= 24'b0;
    end
    else if (sel_tod & we_i & crb_alrm)
    begin
      if (adr_todlo)
        tod_alrm[7:0] <= DBi;
      if (adr_todmi)
        tod_alrm[15:8] <= DBi;
      if (adr_todhi)
        tod_alrm[23:16] <= DBi;
    end
  end


  // Timer A

  reg  [15:0] ta_latch;
  wire [15:0] ta_count;
  reg  ta_fld; // force load
  wire ta_run; // timer run flag (stable for read)

  // timer underflow strobes
  wire ta_ufl; // underflow flag useable on phi2 posedge
  wire ta_pls; // underflow pulse useable on phi2 negedge

  // timer input/output (for PRB)
  wire ta_i = cra_inmd ? cnt_pls : 1'b1;
  wire ta_o;

  cia_timer ta(
              .clk_i(ECLK),
              .rst_i(rst_i),
              .cnt_i(ta_i),
              .omd_i(cra_otmd),
              .str_i(cra_strt),
              .fld_i(ta_fld),
              .fste_i(fste_r),
              .frle_i(frle_r),
              .lch_i(ta_latch),
              .cnt_o(ta_count),
              .run_o(ta_run),
              .pls_o(ta_pls),
              .prb_o(ta_o),
              .unfl_o(ta_ufl)
            );

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      ta_latch <= 16'hffff;
    end
    else if (sel_i & we_i)
    begin
      if (adr_talo)
        ta_latch[7:0]  <= DBi;
      if (adr_tahi)
        ta_latch[15:8] <= DBi;
    end
  end

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      cra_strt <= 1'b0;
    end
    else if (sel_cra & we_i) // write to cra bit 1
      cra_strt <= DBi[0];
    else if (sel_i & adr_tahi & we_i & cra_rnmd & ~cra_strt) // write to TAHI when in oneshot mode and not already running
      cra_strt <= 1'b1;
    else if (ta_pls & cra_rnmd) // oneshot timer expired
      cra_strt <= 1'b0;
  end

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      ta_fld <= 1'b0;
    end
    else if (sel_cra & we_i) // write to cra bit 4 (force load strobe)
      ta_fld <= DBi[4];
    else // timer is reloaded when TAHI is written and counter not running
      ta_fld <= sel_i & adr_tahi & we_i & ~cra_strt;
  end

  // Timer B

  reg  [15:0] tb_latch;
  wire [15:0] tb_count;
  reg  tb_fld; // force load
  wire tb_run; // timer run flag (stable for read)

  // timer underflow strobes
  wire tb_ufl; // underflow flag useable on phi2 posedge
  wire tb_pls; // underflow pulse useable on phi2 negedge

  // timer input/output
  reg  tb_i;
  wire tb_o;

  always @(*)
  begin
    case(crb_inmd)
      default: // phi2 positive transitions
        tb_i = 1'b1;
      2'b01: // cnt rising edges
        tb_i = cnt_pls;
      2'b10: // timer A underflow
        tb_i = ta_ufl;
      2'b11: // timer A underflow while cnt is high
        tb_i = ta_ufl & cnt_s[2];
    endcase
  end

  cia_timer tb(
              .clk_i(ECLK),
              .rst_i(rst_i),
              .cnt_i(tb_i),
              .omd_i(crb_otmd),
              .str_i(crb_strt),
              .fld_i(tb_fld),
              .fste_i(fste_r),
              .frle_i(frle_r),
              .lch_i(tb_latch),
              .cnt_o(tb_count),
              .run_o(tb_run),
              .pls_o(tb_pls),
              .prb_o(tb_o),
              .unfl_o(tb_ufl)
            );

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      tb_latch <= 16'hffff;
    end
    else if (sel_i & we_i)
    begin
      if (adr_tblo)
        tb_latch[7:0]  <= DBi;
      if (adr_tbhi)
        tb_latch[15:8] <= DBi;
    end
  end

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      crb_strt <= 1'b0;
    end
    else if (sel_crb & we_i) // write to crb bit 1
      crb_strt <= DBi[0];
    else if (sel_i & adr_tbhi & we_i & crb_rnmd & ~crb_strt) // write to TBHI when in oneshot mode and not already running
      crb_strt <= 1'b1;
    else if (tb_pls & crb_rnmd) // oneshot timer expired
      crb_strt <= 1'b0;
  end

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      tb_fld <= 1'b0;
    end
    else if (sel_crb & we_i) // write to crb bit 4 (force load strobe)
      tb_fld <= DBi[4];
    else // timer is reloaded when TBHI is written and counter not running
      tb_fld <= sel_i & adr_tbhi & we_i & ~crb_strt;
  end

  // serial port

  reg  [7:0] sdr_r; // actual data in sdr register
  wire [7:0] sdr_w; // incoming data from module
  wire spi_pls; // serial input pulse
  wire spo_pls; // serial output pulse

  reg  spoe_o;
  wire spoe_i;

  cia_serial serial(
               .clk_i(ECLK),
               .rst_i(rst_i),
               .dat_i(sdr_r),
               .dat_o(sdr_w),
               .unfl_i(ta_ufl),
               .cnt_i(cnt_pls),
               .cnt_o(CNTo),
               .sp_i(spi_s[2]),
               .sp_o(SPo),
               .spmd_i(cra_spmd),
               .spoe_i(spoe_o),
               .spoe_o(spoe_i),
               .spo_o(spo_pls),
               .spi_o(spi_pls)
             );

  // handle writes to sdr
  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      sdr_r  <= 8'd0;
      spoe_o <= 1'd0;
    end
    else if (sel_i & we_i & adr_sdr)
    begin
      // handle bus write to sdr register
      sdr_r <= DBi;
      spoe_o <= ~spoe_i;
    end
    else if (spi_pls)
    begin
      // handle incoming serial data
      sdr_r <= sdr_w;
    end
  end

  // handshake stuff

  wire flag_pls;

  cia_handshake handshake(
                  .clk_i(ECLK),
                  .prb_i(sel_i & adr_prb),
                  .flg_ni(nFLAG),
                  .pls_o(flag_pls),
                  .pc_no(nPC)
                );

  // Port A/B.
  reg [7:0] pra;
  reg [7:0] prb;

  reg [7:0] ddra;
  reg [7:0] ddrb;

  assign PRAd = ddra;
  assign PRBd = { crb_pbon | ddrb[7], cra_pbon | ddrb[6], ddrb[5:0] };

  assign PRAo = pra & PRAd;
  assign PRBo = { crb_pbon ? tb_o : prb[7], cra_pbon ? ta_o : prb[6], prb[5:0] } & PRBd;

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      pra  <= 8'd0;
      prb  <= 8'd0;
      ddra <= 8'd0;
      ddrb <= 8'd0;
    end
    else if (sel_i & we_i)
    begin
      if (adr_pra)
        pra   <= DBi;
      if (adr_prb)
        prb   <= DBi;
      if (adr_ddra)
        ddra  <= DBi;
      if (adr_ddrb)
        ddrb  <= DBi;
    end
  end

  // clock domain crossing for port A/B inputs
  reg [7:0] pra_s;
  reg [7:0] prb_s;

  reg [7:0] pra_r;
  reg [7:0] prb_r;

  always @(posedge ECLK)
  begin
    pra_s <= PRAi;
    prb_s <= PRBi;
  end

  always @(posedge ECLK)
  begin
    pra_r <= pra_s;
    prb_r <= prb_s;
  end

  // Interrupt handling.
  reg [4:0] icr_m; // interrupts mask
  reg       icr_rst; // interrupts reset following read
  reg       irq_d; // interrupts delay (if active)

  wire [4:0] icr_o;
  wire       ir;

  cia_irq irqs(
            .clk_i(ECLK),
            .rst_i(rst_i),
            .ta_i(ta_ufl),
            .tb_i(tb_ufl),
            .alrm_i(alrm_pls),
            .sp_i(spo_pls | spi_pls),
            .flg_i(flag_pls),
            .msk_i(icr_m),
            .clr_i(icr_rst),
            .icr_o(icr_o),
            .irq_o(ir)
          );

  assign nIRQ = irq_d;

  always @(negedge ECLK)
  begin
    irq_d <= ~ir;
  end

  always @(negedge ECLK)
  begin
    if (rst_i)
    begin
      icr_m <= 5'b0;
      icr_rst <= 1'b0;
    end
    else if (sel_i & adr_icr)
    begin
      icr_rst <= ~we_i;

      if (we_i)
      begin
        if (DBi[7])
          icr_m <= icr_m |  DBi[4:0];
        else
          icr_m <= icr_m & ~DBi[4:0];
      end
    end
    else
    begin
      icr_rst <= 1'b0;
    end
  end

  wire [7:0] dat_w;

  cia_decoder decoder(
                .adr_i(RS),
                .pra_i((pra_r & ~PRAd) | PRAo),
                .prb_i((prb_r & ~PRBd) | PRBo),
                .ddra_i(ddra),
                .ddrb_i(ddrb),
                .talo_i(ta_count[7:0]),
                .tahi_i(ta_count[15:8]),
                .tblo_i(tb_count[7:0]),
                .tbhi_i(tb_count[15:8]),
                .todlo_i(tod_latch[7:0]),
                .todmid_i(tod_latch[15:8]),
                .todhi_i(tod_latch[23:16]),
                .ext_i({ 5'b0, frle_r, fste_r, fcnt_r }),
                .sdr_i(sdr_r),
                .icr_i({ ir, 2'b00, icr_o[4:0] }),
                .cra_i({     1'b0, cra_spmd, cra_inmd, 1'b0, cra_rnmd, cra_otmd, cra_pbon, ta_run }),
                .crb_i({ crb_alrm,           crb_inmd, 1'b0, crb_rnmd, crb_otmd, crb_pbon, tb_run }),
                .dat_o(dat_w),
                .pra_o(adr_pra),
                .prb_o(adr_prb),
                .ddra_o(adr_ddra),
                .ddrb_o(adr_ddrb),
                .talo_o(adr_talo),
                .tahi_o(adr_tahi),
                .tblo_o(adr_tblo),
                .tbhi_o(adr_tbhi),
                .todlo_o(adr_todlo),
                .todmid_o(adr_todmi),
                .todhi_o(adr_todhi),
                .ext_o(adr_ext),
                .sdr_o(adr_sdr),
                .icr_o(adr_icr),
                .cra_o(adr_cra),
                .crb_o(adr_crb)
              );

  assign DBo = sel_i & ~we_i ? dat_w : 8'b0;
endmodule
