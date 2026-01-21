/*
 * CIA 8520 module
 * Written by Rodolphe de Saint Léger (some code from Niklas Ekström).
 *
 * This implementation WILL NOT apply CIA undocumented features.
 *
 * Changes against CIA documented features :
 * - module is able of phi2 divided by 2 serial I/O (not available in original 8520)
 * - timer A/B will switch to half clock pulses if timer count and latch are both 0 and timer run continuously
 *
 * Design :
 * - reads are valid for one clock cycle, starting at posedge
 * - writes are done on negedge,
 * - irqs are detected on negedge and delivered (or cleared) on posedge,
 * - cnt, flag, sp and ports A/B are sampled at posedge
 * - tod is sampled at negedge
 * - outputs change on negedge (cnt, ps, sp, port A/B)
 * - timers decrement on posedges
 * - tod increment at negedge
 * - separate serial data register for input and output (documentation does not specify if only one register is used)
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

  input      SPi, // serial port in
  output reg SPo, // serial port out
  output     SPd, // serial port direction (1 = output, 0 = input)

  input      CNTi, // cnt in
  output reg CNTo, // cnt out

  input TOD, // TOD counter input

  output nIRQ // /IRQ output (active low)
);

localparam [3:0] REG_PRA     = 4'h0;
localparam [3:0] REG_PRB     = 4'h1;
localparam [3:0] REG_DDRA    = 4'h2;
localparam [3:0] REG_DDRB    = 4'h3;
localparam [3:0] REG_TA_LO   = 4'h4;
localparam [3:0] REG_TA_HI   = 4'h5;
localparam [3:0] REG_TB_LO   = 4'h6;
localparam [3:0] REG_TB_HI   = 4'h7;
localparam [3:0] REG_TOD_LOW = 4'h8;
localparam [3:0] REG_TOD_MID = 4'h9;
localparam [3:0] REG_TOD_HI  = 4'ha;
localparam [3:0] REG_SDR     = 4'hc;
localparam [3:0] REG_ICR     = 4'hd;
localparam [3:0] REG_CRA     = 4'he;
localparam [3:0] REG_CRB     = 4'hf;

// convert input signals to active high
wire rst_i = ~nRES;
wire sel_i = ~nCS;
wire we_i  = ~RW;

wire adr_pra   = RS == REG_PRA;
wire adr_prb   = RS == REG_PRB;
wire adr_ddra  = RS == REG_DDRA;
wire adr_ddrb  = RS == REG_DDRB;
wire adr_talo  = RS == REG_TA_LO;
wire adr_tahi  = RS == REG_TA_HI;
wire adr_tblo  = RS == REG_TB_LO;
wire adr_tbhi  = RS == REG_TB_HI;
wire adr_todlo = RS == REG_TOD_LOW;
wire adr_todmi = RS == REG_TOD_MID;
wire adr_todhi = RS == REG_TOD_HI;
wire adr_icr   = RS == REG_ICR;
wire adr_sdr   = RS == REG_SDR;
wire adr_cra   = RS == REG_CRA;
wire adr_crb   = RS == REG_CRB;

wire sel_cra = sel_i & adr_cra;
wire sel_crb = sel_i & adr_crb;

// cnt synchronization
reg [2:0] cnt_s;

wire cnt_pls = ~cnt_s[2] & cnt_s[1];

initial begin
  // powerup state
  cnt_s = 3'b0;
end

always @(posedge ECLK) begin
  // start cnt signal sync
  cnt_s[0] <= CNTi;
end

always @(negedge ECLK) begin
  // end cnt signal sync and trigger pulse for 1 clock cycle
  { cnt_s[2:1] } <= { cnt_s[1:0] };
end

// control register A

reg cra_strt;
reg cra_pbon;
reg cra_otmd;
reg cra_rnmd;
reg cra_inmd;
reg cra_spmd;

assign SPd = cra_spmd;

initial begin
  // powerup state
  cra_strt = 1'b0;
  cra_pbon = 1'b0;
  cra_otmd = 1'b0;
  cra_rnmd = 1'b0;
  cra_inmd = 1'b0;
  cra_spmd = 1'b0;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    cra_pbon <= 1'b0;
    cra_otmd <= 1'b0;
    cra_rnmd <= 1'b0;
    cra_inmd <= 1'b0;
    cra_spmd <= 1'b0;
  end
  else if (sel_cra & we_i) begin
    // handle write to cra (except for start and force load)
    cra_pbon <= DBi[1];
    cra_otmd <= DBi[2];
    cra_rnmd <= DBi[3];
    cra_inmd <= DBi[5];
    cra_spmd <= DBi[6];
  end
end

// control register B

reg       crb_strt;
reg       crb_pbon;
reg       crb_otmd;
reg       crb_rnmd;
reg [1:0] crb_inmd;
reg       crb_alrm;

initial begin
  // powerup state
  crb_strt = 1'b0;
  crb_pbon = 1'b0;
  crb_otmd = 1'b0;
  crb_rnmd = 1'b0;
  crb_inmd = 2'b0;
  crb_alrm = 1'b0;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    crb_pbon <= 1'b0;
    crb_otmd <= 1'b0;
    crb_rnmd <= 1'b0;
    crb_inmd <= 2'b0;
    crb_alrm <= 1'b0;
  end
  else if (sel_crb & we_i) begin
    // handle write to crb (except for start and force load)
    crb_pbon <= DBi[1];
    crb_otmd <= DBi[2];
    crb_rnmd <= DBi[3];
    crb_inmd <= DBi[6:5];
    crb_alrm <= DBi[7];
  end
end

// tod synchronization
reg [2:0] tod_s;

wire tod_pls = ~tod_s[2] & tod_s[1];

initial begin
  // powerup state
  tod_s = 3'b0;
end

always @(negedge ECLK) begin
  // start tod signal sync
  tod_s[0] <= TOD;
end

always @(posedge ECLK) begin
  // end tod signal sync and trigger pulse for 1 clock cycle
  { tod_s[2:1] } <= { tod_s[1:0] };
end

reg  [23:0] tod_latch;
reg  [23:0] tod_count;
reg  [23:0] tod_alrm;
wire [23:0] tod_nxt = tod_count + 1'd1;

reg tod_rd; // reading from tod
reg tod_wr; // writing to tod

reg alrm_pls;

wire sel_tod = sel_i & (adr_todlo | adr_todmi | adr_todhi);

initial begin
  // powerup state
  tod_latch = 24'b0;
  tod_count = 24'b0;
  tod_alrm  = 24'b0;

  tod_rd = 1'b0;
  tod_wr = 1'b0;

  alrm_pls = 1'b0;
end

always @(posedge ECLK) begin
  if (rst_i) begin
    tod_rd <= 1'b0;
    tod_wr <= 1'b0;
  end
  else begin
    if (~tod_rd)
      tod_latch <= tod_count;

    if (sel_i) begin
      // handle tod latch/write
      if (~we_i) begin
        if (adr_todhi)
          tod_rd <= 1'b1; // latch register when reading tod_hi
        if (adr_todlo)
          tod_rd <= 1'b0; // unlatch register when reading tod low
      end
      else if (~crb_alrm) begin
        if (adr_todhi | adr_todmi)
          tod_wr <= 1'b1; // stop tod when writing tod_hi/tod_mi
        if (adr_todlo)
          tod_wr <= 1'b0; // restart tod when writing tod_lo
      end
    end
  end
end

// tick the tod
wire tod_tck = tod_pls & ~tod_wr;

always @(negedge ECLK) begin
  if (rst_i) begin
    tod_count <= 24'b0;
  end
  else if (sel_tod & we_i & ~crb_alrm) begin
    if (adr_todlo)
      tod_count[7:0] <= DBi;
    if (adr_todmi)
      tod_count[15:8] <= DBi;
    if (adr_todhi)
      tod_count[23:16] <= DBi;
  end
  else if (tod_tck) begin
    // increment tod count
    tod_count <= tod_nxt;
  end
end

always @(negedge ECLK) begin
  if (rst_i) begin
    alrm_pls <= 1'b0;
  end
  else if (tod_tck)
    // check for alrm if tod running
    alrm_pls <= tod_alrm == tod_nxt;
  else
    alrm_pls <= 1'b0;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    tod_alrm <= 24'b0;
  end
  else if (sel_tod & we_i & crb_alrm) begin
    if (adr_todlo)
      tod_alrm[7:0] <= DBi;
    if (adr_todmi)
      tod_alrm[15:8] <= DBi;
    if (adr_todhi)
      tod_alrm[23:16] <= DBi;
  end
end

// Timer A

reg [15:0] ta_latch;
reg [15:0] ta_count;
reg ta_tgl; // timer toggle output
reg ta_run; // timer run flag (stable for read)
reg ta_tck; // timer tick flag
reg ta_fld; // force load

wire [16:0] ta_nxt = ta_count - 1'd1;
wire ta_z = ta_nxt[16]; // use borrow to detect zero

// timer fast and expiration flags
wire ta_fst = ~cra_inmd & ~cra_rnmd & ta_z & (ta_latch == 16'b0);
reg  ta_exp; // timer expiration flag (may be continuous)

// timer output pulse (on PB6)
wire ta_pls = ta_fst ? ta_exp & ~ECLK : ta_exp;

// timer input/output
wire ta_i = cra_inmd ? cnt_pls : 1'b1;
wire ta_o = cra_otmd ? ta_tgl : ta_pls;

initial begin
  // powerup state
  ta_latch = 16'hffff;
  ta_count = 16'hffff;
  ta_tgl = 1'b0;
  ta_run = 1'b0;
  ta_tck = 1'b0;
  ta_fld = 1'b0;
  ta_exp = 1'b0;
end

always @(posedge ECLK) begin
  if (rst_i) begin
    ta_run <= 1'b0;
    ta_tck <= 1'b0;
    ta_count <= 16'hffff;
  end
  else begin
    ta_run <= cra_strt;
    ta_tck <= cra_strt & ta_i;

    if (cra_strt & ta_i) begin
      ta_count <= ta_fld | ta_z ? ta_latch : ta_nxt[15:0];
    end
    else if (ta_fld) begin
      ta_count <= ta_latch;
    end
  end
end

// timer underflow flag (valid on negedge only)
wire ta_unfl = ta_z & ta_tck;

always @(negedge ECLK) begin
  // trigger timer expiration on underflow
  ta_exp <= ta_unfl;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    // toggle output is set low by reset
    ta_tgl <= 1'b0;
  end
  else if (sel_cra & we_i & DBi[0] & ~cra_strt) begin
    // toggle output is set high whenever the timer is started
    ta_tgl <= 1'b1;
  end
  else if (ta_unfl) begin
    // switch toggle output on underflow
    ta_tgl <= ~ta_tgl;
  end
end

always @(negedge ECLK) begin
  if (rst_i) begin
    ta_latch <= 16'hffff;
  end
  else if (sel_i & we_i) begin
    if (adr_talo)
      ta_latch[7:0]  <= DBi;
    if (adr_tahi)
      ta_latch[15:8] <= DBi;
  end
end

always @(negedge ECLK) begin
  if (rst_i) begin
    cra_strt <= 1'b0;
  end
  else if (sel_cra & we_i) // write to cra bit 1
    cra_strt <= DBi[0];
  else if (sel_i & adr_tahi & we_i & cra_rnmd & ~cra_strt) // write to TAHI when not running in oneshot mode
    cra_strt <= 1'b1;
  else if (ta_z & cra_rnmd) // oneshot timer expired
    cra_strt <= 1'b0;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    ta_fld <= 1'b0;
  end
  else if (sel_cra & we_i) // write to cra bit 4 (force load strobe)
    ta_fld <= DBi[4];
  else // timer is reloaded when it has expired or when TAHI is written and counter not running
    ta_fld <= ta_z | (sel_i & adr_tahi & we_i & ~cra_strt);
end

// Timer B

reg [15:0] tb_latch;
reg [15:0] tb_count;
reg tb_tgl; // timer toggle output
reg tb_run; // timer run flag (stable for read)
reg tb_tck; // timer tick flag
reg tb_fld; // force load

wire [16:0] tb_nxt = tb_count - 1'd1;
wire tb_z = tb_nxt[16]; // use borrow to detect zero

// timer fast and expiration flags
wire tb_fst = (crb_inmd == 2'b00) & ~crb_rnmd & tb_z & (tb_latch == 16'b0);
reg  tb_exp; // timer expiration flag (may be continuous)

// timer output pulse (on PB7)
wire tb_pls = tb_fst ? tb_exp & ~ECLK : tb_exp;

// timer input/output
reg  tb_i;
wire tb_o = crb_otmd ? tb_tgl : tb_pls;

always @(*) begin
  case(crb_inmd)
    default: // phi2 positive transitions
      tb_i = 1'b1;
    2'b01: // cnt rising edges
      tb_i = cnt_pls;
    2'b10: // timer A underflow
      tb_i = ta_exp;
    2'b11: // timer A underflow while cnt is high
      tb_i = ta_exp & cnt_s[1];
  endcase
end

initial begin
  // powerup state
  tb_latch = 16'hffff;
  tb_count = 16'hffff;
  tb_tgl = 1'b0;
  tb_run = 1'b0;
  tb_tck = 1'b0;
  tb_fld = 1'b0;
  tb_exp = 1'b0;
end

always @(posedge ECLK) begin
  if (rst_i) begin
    tb_run <= 1'b0;
    tb_tck <= 1'b0;
    tb_count <= 16'hffff;
  end
  else begin
    tb_run <= crb_strt;
    tb_tck <= crb_strt & tb_i;

    if (crb_strt & tb_i) begin
      tb_count <= tb_fld | tb_z ? tb_latch : tb_nxt;
    end
    else if (tb_fld) begin
      tb_count <= tb_latch;
    end
  end
end

// timer underflow flag (valid on negedge only)
wire tb_unfl = tb_z & tb_tck;

always @(negedge ECLK) begin
  // trigger timer expiration on underflow
  tb_exp <= tb_unfl;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    // toggle output is set low by reset
    tb_tgl <= 1'b0;
  end
  else if (sel_crb & we_i & DBi[0] & ~crb_strt) begin
    // toggle output is set high whenever the timer is started
    tb_tgl <= 1'b1;
  end
  else if (tb_unfl) begin
    // switch toggle output on underflow
    tb_tgl <= ~tb_tgl;
  end
end

always @(negedge ECLK) begin
  if (rst_i) begin
    tb_latch <= 16'hffff;
  end
  else if (sel_i & we_i) begin
    if (adr_tblo)
      tb_latch[7:0]  <= DBi;
    if (adr_tbhi)
      tb_latch[15:8] <= DBi;
  end
end

always @(negedge ECLK) begin
  if (rst_i) begin
    crb_strt <= 1'b0;
  end
  else if (sel_crb & we_i) // write to crb bit 1
    crb_strt <= DBi[0];
  else if (sel_i & adr_tbhi & we_i & crb_rnmd & ~crb_strt) // write to TBHI when not running in oneshot mode
    crb_strt <= 1'b1;
  else if (tb_z & crb_rnmd) // oneshot timer expired
    crb_strt <= 1'b0;
end

always @(negedge ECLK) begin
  if (rst_i) begin
    tb_fld <= 1'b0;
  end
  else if (sel_crb & we_i) // write to crb bit 4 (force load strobe)
    tb_fld <= DBi[4];
  else // timer is reloaded when it has expired or when TBHI is written and counter not running
    tb_fld <= tb_z | (sel_i & adr_tbhi & we_i & ~crb_strt);
end

// serial port input

reg [7:0] spi_dat; // serial input data register
reg [8:0] spi_shf; // serial shift register for input
reg [2:0] spi_cnt; // serial input shift count

wire [3:0] spi_nxt = { 1'b0, spi_cnt } + 1'd1;
reg        spi_rdy; // full byte is ready

always @(posedge ECLK) begin
  // sample serial input with CNTi (available at next clock edge)
  spi_shf[0] <= SPi;
end

always @(posedge ECLK) begin
  if (rst_i) begin
    spi_shf[8:1] <= 8'b0;
    spi_cnt <= 3'b0;
    spi_rdy <= 1'b0;
  end
  else if (~cra_spmd & cnt_pls) begin
    // shift data in
    spi_shf[8:1] <= spi_shf[7:0];
    spi_cnt <= spi_nxt[2:0];
    spi_rdy <= spi_nxt[3]; // use carry as ready flag
  end
  else if (spi_rdy) begin
    // keep ready flag on one clock cycle
    spi_rdy <= 1'b0;
  end
end

reg spi_pls;

always @(negedge ECLK) begin
  // detect end of transmission
  spi_pls <= spi_rdy;
end

always @(posedge ECLK) begin
  if (rst_i) begin
    spi_dat <= 8'b0;
  end
  else if (spi_rdy) begin
    spi_dat <= spi_shf[8:1];
  end
end

initial begin
  // powerup state
  spi_dat = 8'b0;
  spi_shf = 9'b0;
  spi_cnt = 3'b0;
  spi_rdy = 1'b0;
  spi_pls = 1'b0;
end

// serial port output

reg [7:0] spo_dat; // serial data register for output
reg       spo_pnd; // pending data in spo_dat
reg       spo_clr; // clear flag for spo_dat (set on negedge)

always @(negedge ECLK) begin
  if (rst_i) begin
    spo_pnd <= 1'b0;
    spo_dat <= 8'b0;
  end
  else if (adr_sdr & sel_i & we_i) begin // write to sdr register, mark data as pending
    spo_dat <= DBi;
    spo_pnd <= 1'b1;
  end
  else
    spo_pnd <= spo_pnd & ~spo_clr;
end

reg [7:0] spo_shf; // serial shift register for output
reg [3:0] spo_cnt; // shift count and cnt output clock (LSB)
reg       spo_bsy; // data shifting out

// next shift count, MSB is next value for spo_bsy
wire [4:0] spo_nxt = { 1'b0, spo_cnt } + 1'd1;

always @(posedge ECLK) begin
  if (rst_i) begin
    spo_bsy <= 1'b0;
    spo_shf <= 8'b0;
    spo_cnt <= 4'b0000;
  end
  else if (cra_spmd & ta_exp) begin
    if (spo_bsy) begin
      if (~spo_nxt[4] & spo_nxt[0])
        spo_shf <= { spo_shf[6:0], 1'b0 };

      spo_bsy <= ~spo_nxt[4];
      spo_cnt <= spo_nxt[3:0];
    end
    else if (spo_pnd) begin
      spo_shf <= spo_dat;
      spo_bsy <= spo_pnd;
      spo_cnt <= spo_nxt[3:0];
    end
  end
end

reg spo_pls;

always @(negedge ECLK) begin
  SPo <= spo_shf[7];
  CNTo <= spo_bsy ? ~spo_cnt[0] : 1'b1;
  spo_pls <= cra_spmd & ta_unfl & spo_nxt[4];
end

always @(posedge ECLK) begin
  spo_clr <= cra_spmd & spo_pnd & ta_exp & ~spo_bsy;
end

initial begin
  // powerup state
  spo_dat = 8'b0;
  spo_shf = 8'b0;
  spo_cnt = 4'b0;
  spo_bsy = 1'b0;
  spo_pnd = 1'b0;
  spo_clr = 1'b0;
  spo_pls = 1'b0;
end

// handshake stuff

reg [2:0] flag_s;

wire flag_pls = ~flag_s[2] & flag_s[1];

always @(negedge ECLK) begin
  // trigger PC low for 1 clock cycle following a read or write to PRB
  nPC <= ~(sel_i & adr_prb);
end

always @(posedge ECLK) begin
  // start flag signal sync
  flag_s[0] <= ~nFLAG;
end

always @(negedge ECLK) begin
  // end flag signal sync and trigger pulse for 1 clock cycle
  { flag_s[2], flag_s[1] } <= { flag_s[1], flag_s[0] };
end

initial begin
  // powerup state
  flag_s = 3'b0;
  nPC = 1'b1;
end

// Port A/B.
reg [7:0] pra;
reg [7:0] prb;

reg [7:0] ddra;
reg [7:0] ddrb;

initial begin
  // powerup state
  pra = 8'b0;
  prb = 8'b0;
  ddra = 8'b0;
  ddrb = 8'b0;
end

assign PRAd = ddra;
assign PRBd = { crb_pbon ? 1'b1 : ddrb[7], cra_pbon ? 1'b1 : ddrb[6], ddrb[5:0] };

assign PRAo = pra & PRAd;
assign PRBo = { crb_pbon ? tb_o : prb[7], cra_pbon ? ta_o : prb[6], prb[5:0] } & PRBd;

always @(negedge ECLK) begin
  if (rst_i) begin
    pra  <= 8'd0;
    prb  <= 8'd0;
    ddra <= 8'd0;
    ddrb <= 8'd0;
  end
  else if (sel_i & we_i) begin
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

always @(posedge ECLK) begin
  pra_s <= PRAi;
  prb_s <= PRBi;
end

always @(posedge ECLK) begin
  pra_r <= pra_s;
  prb_r <= prb_s;
end

// Interrupt handling.
reg [4:0] icr_m; // interrupts mask

reg icr_rst; // interrupts reset following read
reg icr_flg;
reg icr_sp;
reg icr_alrm;
reg icr_tb;
reg icr_ta;

initial begin
  // powerup state
  icr_m = 5'b0;
  icr_rst = 1'b0;
  icr_flg = 1'b0;
  icr_sp = 1'b0;
  icr_alrm = 1'b0;
  icr_tb = 1'b0;
  icr_ta = 1'b0;
end

wire [4:0] icr_d = { icr_flg, icr_sp, icr_alrm, icr_tb, icr_ta };
wire [4:0] icr_o = icr_m & icr_d;
wire       ir    = |(icr_o);

assign nIRQ = ~ir;

always @(negedge ECLK) begin
  if (rst_i) begin
    icr_m <= 5'b0;
    icr_rst <= 1'b0;
  end
  else if (sel_i & adr_icr) begin
    icr_rst <= ~we_i;

    if (we_i) begin
      if (DBi[7])
        icr_m <= icr_m |  DBi[4:0];
      else
        icr_m <= icr_m & ~DBi[4:0];
    end
  end
  else begin
    icr_rst <= &'b0;
  end
end

always @(posedge ECLK) begin
  if (rst_i) begin
    icr_flg  <= 1'b0;
    icr_sp   <= 1'b0;
    icr_alrm <= 1'b0;
    icr_tb   <= 1'b0;
    icr_ta   <= 1'b0;
  end
  else if (icr_rst) begin
    icr_flg <= flag_pls;
    icr_sp <= spo_pls | spi_pls;
    icr_alrm <= alrm_pls;
    icr_tb <= tb_exp;
    icr_ta <= ta_exp;
  end
  else begin
    icr_flg <= icr_flg | flag_pls;
    icr_sp <= icr_sp | spo_pls | spi_pls;
    icr_alrm <= icr_alrm| alrm_pls;
    icr_tb <= icr_tb | tb_exp;
    icr_ta <= icr_ta | ta_exp;
  end
end

reg [7:0] dat_r;

assign DBo = sel_i & ~we_i ? dat_r : 8'b0;

always @(*) begin
  case (RS)
    REG_PRA:
      dat_r = (pra_r & ~PRAd) | PRAo;
    REG_PRB:
      dat_r = (prb_r & ~PRBd) | PRBo;
    REG_DDRA:
      dat_r = ddra;
    REG_DDRB:
      dat_r = ddrb;
    REG_TA_LO:
      dat_r = ta_count[7:0];
    REG_TA_HI:
      dat_r = ta_count[15:8];
    REG_TB_LO:
      dat_r = tb_count[7:0];
    REG_TB_HI:
      dat_r = tb_count[15:8];
    REG_TOD_LOW:
      dat_r = tod_latch[7:0];
    REG_TOD_MID:
      dat_r = tod_latch[15:8];
    REG_TOD_HI:
      dat_r = tod_latch[23:16];
    REG_SDR:
      dat_r = spi_dat;
    REG_ICR:
      dat_r = { ir, 2'b00, icr_d[4:0] };
    REG_CRA:
      dat_r = {     1'b0, cra_spmd, cra_inmd, 1'b0, cra_rnmd, cra_otmd, cra_pbon, ta_run };
    REG_CRB:
      dat_r = { crb_alrm,           crb_inmd, 1'b0, crb_rnmd, crb_otmd, crb_pbon, tb_run };
    default:
      dat_r = 8'd0;
  endcase
end
endmodule
