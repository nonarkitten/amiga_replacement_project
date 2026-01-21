`timescale 10ns/10ns

module cia_internal_tb;
  // clock signals
  reg rst;
  reg clk;

  localparam [4:0] CIAA_PRA = 5'h00;
  localparam [4:0] CIAA_PRB = 5'h01;
  localparam [4:0] CIAA_DDRA = 5'h02;
  localparam [4:0] CIAA_DDRB = 5'h03;
  localparam [4:0] CIAA_TA_LO = 5'h04;
  localparam [4:0] CIAA_TA_HI = 5'h05;
  localparam [4:0] CIAA_TB_LO = 5'h06;
  localparam [4:0] CIAA_TB_HI = 5'h07;
  localparam [4:0] CIAA_TOD_LOW = 5'h08;
  localparam [4:0] CIAA_TOD_MID = 5'h09;
  localparam [4:0] CIAA_TOD_HI = 5'h0a;
  localparam [4:0] CIAA_SDR = 5'h0c;
  localparam [4:0] CIAA_ICR = 5'h0d;
  localparam [4:0] CIAA_CRA = 5'h0e;
  localparam [4:0] CIAA_CRB = 5'h0f;

  localparam [4:0] CIAB_PRA = 5'h10;
  localparam [4:0] CIAB_PRB = 5'h11;
  localparam [4:0] CIAB_DDRA = 5'h12;
  localparam [4:0] CIAB_DDRB = 5'h13;
  localparam [4:0] CIAB_TA_LO = 5'h14;
  localparam [4:0] CIAB_TA_HI = 5'h15;
  localparam [4:0] CIAB_TB_LO = 5'h16;
  localparam [4:0] CIAB_TB_HI = 5'h17;
  localparam [4:0] CIAB_TOD_LOW = 5'h18;
  localparam [4:0] CIAB_TOD_MID = 5'h19;
  localparam [4:0] CIAB_TOD_HI = 5'h1a;
  localparam [4:0] CIAB_SDR = 5'h1c;
  localparam [4:0] CIAB_ICR = 5'h1d;
  localparam [4:0] CIAB_CRA = 5'h1e;
  localparam [4:0] CIAB_CRB = 5'h1f;

  // cia A specific signals
  reg  ciaa_sel;
  wire ciaa_nirq_o;

  // cia B specific signals
  reg  ciab_sel;
  wire ciab_flag;
  wire ciab_nirq_o;

  reg tod_e;

  // will use timer B as tod source
  wire tod_i = tod_e ? cia_prb[7] : 1'b0;

  // cia A/B common signals
  reg        cia_we;
  reg  [3:0] cia_adr;
  reg  [7:0] cia_dat_i;
  reg  [7:0] cia_dat_r;
  wire [7:0] cia_dat = cia_we ? cia_dat_i : 8'bz;
  wire       cia_irq_o = ~ciaa_nirq_o | ~ciab_nirq_o;

  // used to connect both CIAs
  wire [7:0] cia_pra;
  wire [7:0] cia_prb;
  wire       cia_flag;
  wire       cia_cnt;
  wire       cia_sp;

  reg cnt_ovr;

  // will use timer B as cnt source
  assign cia_cnt = cnt_ovr ? cia_prb[6] : 1'bz;

  cia ciaa(
        .ECLK(clk),
        .nRES(~rst),
        .nCS(~ciaa_sel),
        .RW(~cia_we),
        .RS(cia_adr),
        .DB(cia_dat),
        .PA(cia_pra),
        .PB(cia_prb),
        .nFLAG(cia_flag),
        .SP(cia_sp),
        .CNT(cia_cnt),
        .TOD(tod_i),
        .nIRQ(ciaa_nirq_o)
      );

  pullup(ciab_flag);

  cia ciab(
        .ECLK(clk),
        .nRES(~rst),
        .nCS(~ciab_sel),
        .RW(~cia_we),
        .RS(cia_adr),
        .DB(cia_dat),
        .PA(cia_pra),
        .PB(cia_prb),
        .nFLAG(ciab_flag),
        .nPC(cia_flag),
        .SP(cia_sp),
        .CNT(cia_cnt),
        .TOD(tod_i),
        .nIRQ(ciab_nirq_o)
      );

  initial begin
    cia_we = 0;
    cia_adr = 0;
    cia_dat_i = 8'bx;

    ciaa_sel = 0;
    ciab_sel = 0;
    cnt_ovr = 0;
    tod_e = 0;
  end

  initial begin
    @(negedge clk);
    cia_test_rst();
    cia_test_pra();
    cia_test_prb();
    cia_test_timera();
    @(posedge clk) $finish;
  end

  task cia_test_timera();
    begin
      cia_write_cycle(CIAA_DDRB, 8'b00000000);
      cia_write_cycle(CIAB_DDRB, 8'b00111111);
      cia_write_cycle(CIAA_CRA, 8'b00001010); // sets oneshot, PB6ON, pulse
      cia_write_cycle(CIAA_CRB, 8'b00000010); // sets PB6ON
      cia_write_cycle(CIAA_PRB, 8'b00000000);
      cia_write_cycle(CIAB_PRB, 8'b00000000);
      @(posedge clk); // signal generated at port B
      @(posedge clk); // first stage port B sync
      cia_read_check(CIAA_PRB, 8'b00000000);
      cia_write_cycle(CIAA_TA_LO, 8'b00000000);
      cia_write_cycle(CIAA_TA_HI, 8'b00000000); // should start timer
      @(negedge clk); // Timer underflow
      @(posedge clk); // signal generated at port B
      @(posedge clk); // first stage port B sync
      cia_read_check(CIAB_PRB, 8'b01000000); // check output pulse from timer A (high)
      cia_read_check(CIAB_PRB, 8'b00000000); // check output pulse from timer A (low)
      cia_write_cycle(CIAA_CRA, 8'b00000011); // sets PB6ON, pulse, and restart counter (fast mode)
      @(negedge clk)
      #25 if (~cia_prb[6]) $display("fast pulse error");
      @(posedge clk)
      #25 if ( cia_prb[6]) $display("fast pulse error");
      @(negedge clk)
      #25 if (~cia_prb[6]) $display("fast pulse error");
      @(posedge clk)
      #25 if ( cia_prb[6]) $display("fast pulse error");
      cia_write_cycle(CIAA_CRA, 8'b00000111); // change to toggle output
      @(negedge clk);
      cia_read_check(CIAB_PRB, 8'b01000000); // check toggle output from timer A (high)
      cia_read_check(CIAB_PRB, 8'b00000000); // check toggle output from timer A (low)
      cia_read_check(CIAB_PRB, 8'b01000000); // check toggle output from timer A (high)
      cia_read_check(CIAB_PRB, 8'b00000000); // check toggle output from timer A (low)
      cia_read_check(CIAB_PRB, 8'b01000000); // check toggle output from timer A (high)
      cia_read_check(CIAB_PRB, 8'b00000000); // check toggle output from timer A (low)
      cia_write_cycle(CIAA_CRA, 8'b00001010); // stop timer, oneshot, PB6ON, pulse
      cia_write_cycle(CIAA_TA_LO, 8'd4);
      cia_write_cycle(CIAA_TA_HI, 8'b00000000); // should start timer
      cia_read_check(CIAA_TA_LO, 8'd4); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd3); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd2); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd1); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd0); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd4); // check toggle output from timer A (low)
      cia_write_cycle(CIAA_CRA, 8'b00000011); // start timer (continuous), PB6ON, pulse
      cia_read_check(CIAA_TA_LO, 8'd3); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd2); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd1); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd0); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd4); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd3); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd2); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd1); // check toggle output from timer A (low)
      cia_read_check(CIAA_TA_LO, 8'd0); // check toggle output from timer A (low)
      @(posedge clk);
      @(posedge clk);
      @(posedge clk);
      @(posedge clk);
    end
  endtask

  task cia_test_rst();
    begin
      // check powerup and reset state
      cia_read_check(CIAA_DDRA, 8'b00000000);
      cia_read_check(CIAA_DDRB, 8'b00000000);
      cia_read_check(CIAB_DDRA, 8'b00000000);
      cia_read_check(CIAB_DDRB, 8'b00000000);
      cia_read_check(CIAA_TA_LO, 8'b11111111);
      cia_read_check(CIAA_TA_HI, 8'b11111111);
      cia_read_check(CIAA_TB_LO, 8'b11111111);
      cia_read_check(CIAA_TB_HI, 8'b11111111);
      cia_read_check(CIAB_TA_LO, 8'b11111111);
      cia_read_check(CIAB_TA_HI, 8'b11111111);
      cia_read_check(CIAB_TB_LO, 8'b11111111);
      cia_read_check(CIAB_TB_HI, 8'b11111111);
      // force timer latch loads
      cia_write_cycle(CIAA_CRA, 8'b00010000);
      cia_write_cycle(CIAA_CRB, 8'b00010000);
      cia_write_cycle(CIAB_CRA, 8'b00010000);
      cia_write_cycle(CIAB_CRB, 8'b00010000);
      // ensure force load bit is a strobe
      cia_read_check(CIAA_CRA, 8'b00000000);
      cia_read_check(CIAA_CRB, 8'b00000000);
      cia_read_check(CIAB_CRA, 8'b00000000);
      cia_read_check(CIAB_CRB, 8'b00000000);
      // double check timer counters
      cia_read_check(CIAA_TA_LO, 8'b11111111);
      cia_read_check(CIAA_TA_HI, 8'b11111111);
      cia_read_check(CIAA_TB_LO, 8'b11111111);
      cia_read_check(CIAA_TB_HI, 8'b11111111);
      cia_read_check(CIAB_TA_LO, 8'b11111111);
      cia_read_check(CIAB_TA_HI, 8'b11111111);
      cia_read_check(CIAB_TB_LO, 8'b11111111);
      cia_read_check(CIAB_TB_HI, 8'b11111111);
      cia_read_check(CIAA_TOD_HI, 8'b00000000);
      cia_read_check(CIAA_TOD_MID, 8'b00000000);
      cia_read_check(CIAA_TOD_LOW, 8'b00000000);
      cia_read_check(CIAB_TOD_HI, 8'b00000000);
      cia_read_check(CIAB_TOD_MID, 8'b00000000);
      cia_read_check(CIAB_TOD_LOW, 8'b00000000);
      cia_read_check(CIAA_SDR, 8'b00000000);
      cia_read_check(CIAB_SDR, 8'b00000000);
      cia_read_check(CIAA_ICR, 8'b00000000);
      cia_read_check(CIAB_ICR, 8'b00000000);
    end
  endtask

  task cia_test_pra();
    begin
      cia_write_cycle(CIAA_DDRA, 8'b01010101);
      cia_read_check(CIAA_DDRA, 8'b01010101);
      cia_write_cycle(CIAB_DDRA, 8'b10101010);
      cia_read_check(CIAB_DDRA, 8'b10101010);
      cia_write_cycle(CIAA_PRA, 8'b11111111);
      cia_write_cycle(CIAB_PRA, 8'b00000000);
      @(posedge clk); // first stage sync
      @(posedge clk); // second stage sync
      cia_read_check(CIAA_PRA, 8'b01010101);
      cia_read_check(CIAB_PRA, 8'b01010101);
      cia_write_cycle(CIAA_PRA, 8'b00000000);
      cia_write_cycle(CIAB_PRA, 8'b11111111);
      @(posedge clk); // first stage sync
      @(posedge clk); // second stage sync
      cia_read_check(CIAA_PRA, 8'b10101010);
      cia_read_check(CIAB_PRA, 8'b10101010);
    end
  endtask

  task cia_test_prb();
    begin
      // same test (as done with PRA but include flag interrupt handling)
      cia_write_cycle(CIAA_DDRB, 8'b01010101);
      cia_read_check(CIAA_DDRB, 8'b01010101);
      cia_write_cycle(CIAB_DDRB, 8'b10101010);
      cia_read_check(CIAB_DDRB, 8'b10101010);
      cia_write_cycle(CIAB_PRB, 8'b00000000);
      cia_write_cycle(CIAA_PRB, 8'b11111111);
      cia_read_check(CIAA_ICR, 8'b00010000); // check flag interrupt occured
      @(posedge clk); // first stage sync
      @(posedge clk); // second stage sync
      cia_write_cycle(CIAA_ICR, 8'b10010000); // set flag interrupt
      cia_read_check(CIAB_PRB, 8'b01010101);
      cia_read_check(CIAA_PRB, 8'b01010101);
      @(negedge clk); // wait one more cycle for interrupt propagation
      cia_read_check(CIAA_ICR, 8'b10010000); // check flag interrupt occured (with ir flag)
      cia_write_cycle(CIAB_PRB, 8'b11111111);
      cia_write_cycle(CIAA_PRB, 8'b00000000);
      @(negedge clk); // wait one more cycle for interrupt propagation
      cia_write_cycle(CIAA_ICR, 8'b00010000); // clear flag interrupt (with pending interrupt)
      cia_read_check(CIAA_ICR, 8'b00010000); // check flag interrupt occured (without ir flag)
      @(posedge clk); // first stage sync
      @(posedge clk); // second stage sync
      cia_read_check(CIAB_PRB, 8'b10101010);
      cia_read_check(CIAA_PRB, 8'b10101010);
      cia_read_check(CIAA_ICR, 8'b00010000); // check flag interrupt occured
    end
  endtask

  task cia_read_cycle(
      input [4:0] adr_i
    );
    begin
      if (~clk)
        @(posedge clk);
      cia_adr = adr_i[3:0];
      cia_we = 0;
      #25 { ciaa_sel, ciab_sel } = { ~adr_i[4], adr_i[4] };
      @(negedge clk);
      cia_dat_r = cia_dat;
      #25 { ciaa_sel, ciab_sel } = 2'b0;
      //cia_adr[3:0] = 4'bx;
      cia_we = 0;
    end
  endtask

  task cia_read_check(
      input [4:0] adr_i,
      input [7:0] dat_i
    );
    begin
      cia_read_cycle(adr_i);

      if (cia_dat_r != dat_i) begin
        $display("read error : %t address 0x%h got %b expected %b", $time, adr_i, cia_dat_r, dat_i);
      end
    end
  endtask

  task cia_write_cycle(
      input [4:0] adr_i,
      input [7:0] dat_i
    );
    begin
      if (~clk)
        @(posedge clk);
      cia_dat_i = dat_i;
      cia_adr = adr_i[3:0];
      cia_we = 1;
      #25 { ciaa_sel, ciab_sel } = { ~adr_i[4], adr_i[4] };
      @(negedge clk);
      #25 { ciaa_sel, ciab_sel } = 2'b0;
      //cia_adr[3:0] = 4'bx;
      //cia_dat_i = 8'bx;
      cia_we = 0;
    end
  endtask

  initial begin
    $dumpfile ("cia_sim.vcd");
    $dumpvars;
  end

  initial
    #200000 $finish;

  // clocks generator
  initial begin
    clk = 0;
  end

  always
    #50 clk = ~clk;
endmodule
