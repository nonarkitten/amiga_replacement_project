`timescale 1ns/1ns

module cia_top_tb;
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
  localparam [4:0] CIAA_EXT = 5'h0b;
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
  localparam [4:0] CIAB_EXT = 5'h1b;
  localparam [4:0] CIAB_SDR = 5'h1c;
  localparam [4:0] CIAB_ICR = 5'h1d;
  localparam [4:0] CIAB_CRA = 5'h1e;
  localparam [4:0] CIAB_CRB = 5'h1f;

  // Clock and reset
  reg [1:0] clk_s;
  wire c2m = clk_s[0];
  reg c1m;
  reg rst_i;

  // cia A specific signals
  reg  ciaa_sel;
  wire ciaa_flag;
  wire ciaa_nirq_o;

  // cia B specific signals
  reg  ciab_sel;
  wire ciab_flag;
  wire ciab_nirq_o;

  reg tod_ovr;
  reg tod_drv;

  // enable tod pin
  wire tod_i = tod_ovr ? tod_drv : 1'b0;

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
  wire       cia_cnt;
  wire       cia_sp;

  reg cnt_ovr;

  // will use timer B as cnt source
  assign cia_cnt = cnt_ovr ? cia_prb[6] : 1'bz;

  cia ciaa(
        .ECLK(c1m),
        .nRES(~rst_i),
        .nCS(~ciaa_sel),
        .RW(~cia_we),
        .RS(cia_adr),
        .DB(cia_dat),
        .PA(cia_pra),
        .PB(cia_prb),
        .nFLAG(ciaa_flag),
        .SP(cia_sp),
        .CNT(cia_cnt),
        .TOD(tod_i),
        .nIRQ(ciaa_nirq_o)
      );

  pullup(ciab_flag);

  cia ciab(
        .ECLK(c1m),
        .nRES(~rst_i),
        .nCS(~ciab_sel),
        .RW(~cia_we),
        .RS(cia_adr),
        .DB(cia_dat),
        .PA(cia_pra),
        .PB(cia_prb),
        .nFLAG(ciab_flag),
        .nPC(ciaa_flag),
        .SP(cia_sp),
        .CNT(cia_cnt),
        .TOD(tod_i),
        .nIRQ(ciab_nirq_o)
      );

  initial
  begin
    cia_we = 0;
    cia_adr = 0;
    cia_dat_i = 8'bx;

    ciaa_sel = 0;
    ciab_sel = 0;
    cnt_ovr = 0;
    tod_ovr = 0;
  end

  // Test sequence
  initial
  begin
    $dumpfile("cia_top_tb.vcd");
    $dumpvars(0, cia_top_tb);

    repeat(4) @(posedge c2m); // small delay before starting tests

    pulse_reset();

    repeat(3) @(posedge c1m);

    cia_test_rst();
    cia_test_pra();
    cia_test_prb();
    cia_test_serial_a_to_b(8'b01010101, 0);
    cia_test_serial_a_to_b(8'b01010101, 1);
    cia_test_serial_b_to_a(8'b00000000, 0);
    cia_test_serial_b_to_a(8'b11111111, 1);
    cia_test_timera();
    cia_test_tod();
    $finish;
  end

  task cia_test_timera();
    begin
      // disable all extensions (vanilla CIA)
      cia_write_cycle(CIAA_EXT, 8'b00000000); // set CIA A extensions
      cia_write_cycle(CIAB_EXT, 8'b00000000); // set CIA B extensions

      // clear interrupts
      cia_read_cycle(CIAA_ICR);
      cia_read_cycle(CIAB_ICR);

      cia_write_cycle(CIAA_DDRB, 8'b00000000);
      cia_write_cycle(CIAB_DDRB, 8'b00111111);
      cia_write_cycle(CIAA_CRA, 8'b00001010); // sets oneshot, PB6ON, pulse
      cia_write_cycle(CIAA_CRB, 8'b00000010); // sets PB6ON
      cia_write_cycle(CIAA_PRB, 8'b00000000);
      cia_write_cycle(CIAB_PRB, 8'b00000000);
      @(posedge c1m) eoc();  // wait metastable sync
      cia_read_check(CIAA_PRB, 8'b00000000);
      cia_read_check(CIAB_PRB, 8'b00000000);

      // Test 1 : Basic countdown from 5 to underflow with pulse output

      cia_write_cycle(CIAA_TA_LO, 8'd5);
      cia_write_cycle(CIAA_TA_HI, 8'b00000000); // force load and start timer

      // first check timer only using external (cpu bus) interface
      cia_read_check(CIAA_TA_LO, 8'd5); // suppressed tick (due to force load)
      cia_read_check(CIAA_TA_LO, 8'd5);
      cia_read_check(CIAA_TA_LO, 8'd4);
      cia_read_check(CIAA_TA_LO, 8'd3);
      cia_read_check(CIAA_TA_LO, 8'd2);
      cia_read_check(CIAA_TA_LO, 8'd1);
      cia_read_check(CIAA_TA_LO, 8'd0);
      cia_read_check(CIAA_TA_LO, 8'd5);
      cia_read_check(CIAA_ICR, 8'b00010001);

      // ensure timer is not running anymore
      cia_read_check(CIAA_TA_LO, 8'd5);
      cia_read_check(CIAA_TA_LO, 8'd5);
      cia_read_check(CIAA_TA_LO, 8'd5);

      // recheck using internal signals
      cia_write_cycle(CIAA_TA_HI, 8'b00000000); // force load and start timer (again)

      // check internal signals (for precise timing)
      @(posedge ciaa.ciai.ta.run_s[1]) check_counter(16'd5);
      @(negedge c1m) check_counter(16'd5); // suppressed tick (due to force load)
      @(negedge c1m) check_counter(16'd4);
      @(negedge c1m) check_counter(16'd3);
      @(negedge c1m) check_counter(16'd2);
      @(negedge c1m) check_counter(16'd1);
      @(negedge c1m) check_counter(16'd0);

      @(posedge c1m); // switch edge to read outputs
      check_underflow(1'b1); // counter will underflow on next tick
      check_pulse(1'b0);
      check_port(1'b0);

      @(negedge c1m) check_counter(16'd5); // counter reload
      @(posedge c1m);

      check_underflow(1'b0); // ensure underflow is not asserted anymore
      check_pulse(1'b1); // output pulse is now generated
      check_port(1'b1);  // port output pulse has been generated also

      @(negedge c1m) check_counter(16'd5); // counter stopped
      @(posedge c1m);

      // ensure nothing is remaining
      check_underflow(1'b0);
      check_pulse(1'b0);
      check_port(1'b0);

      // Test 1a : Basic countdown from 5 to underflow with pulse output
      // This test uses latch from previous test

      cia_write_cycle(CIAA_CRA, 8'b00000011); // start in continuous, pulse

      // check internal signals (for precise timing)
      @(posedge ciaa.ciai.ta.run_s[1]) check_counter(16'd5);
      @(negedge c1m) check_counter(16'd4);
      @(negedge c1m) check_counter(16'd3);
      @(negedge c1m) check_counter(16'd2);
      @(negedge c1m) check_counter(16'd1);
      @(negedge c1m) check_counter(16'd0);

      @(posedge c1m); // switch edge to read outputs
      check_underflow(1'b1); // counter will underflow on next tick
      check_pulse(1'b0);
      check_port(1'b0);

      @(negedge c1m) check_counter(16'd5); // counter reload
      @(posedge c1m);

      check_underflow(1'b0); // ensure underflow is not asserted anymore
      check_pulse(1'b1); // output pulse is now generated
      check_port(1'b1);  // port output pulse has been generated also

      @(negedge c1m) check_counter(16'd5); // suppressed tick
      @(posedge c1m);

      // ensure nothing is remaining
      check_underflow(1'b0);
      check_pulse(1'b0);
      check_port(1'b0);

      @(negedge c1m) check_counter(16'd4);
      @(negedge c1m) check_counter(16'd3);
      @(negedge c1m) check_counter(16'd2);
      @(negedge c1m) check_counter(16'd1);
      @(negedge c1m) check_counter(16'd0);

      @(posedge c1m); // switch edge to read outputs
      check_underflow(1'b1); // counter will underflow on next tick
      check_pulse(1'b0);
      check_port(1'b0);

      @(negedge c1m) check_counter(16'd5); // counter reload
      @(posedge c1m);

      check_underflow(1'b0); // ensure underflow is not asserted anymore
      check_pulse(1'b1); // output pulse is now generated
      check_port(1'b1);  // port output pulse has been generated also

      @(negedge c1m) check_counter(16'd5); // suppressed tick
      @(posedge c1m);

      // ensure nothing is remaining
      check_underflow(1'b0);
      check_pulse(1'b0);
      check_port(1'b0);

      cia_write_cycle(CIAA_CRA, 8'b00000010); // stop timer

      // Test 2 : Toggle mode

      cia_write_cycle(CIAA_TA_LO, 8'd3); // load 3 in talo
      cia_write_cycle(CIAA_TA_HI, 8'b00000000); // force load timer (because not running)

      @(negedge ciaa.ciai.ta.fld_i) check_counter(16'd3);

      cia_write_cycle(CIAA_CRA, 8'b00000111); // start in continuous, toggle on pb

      @(posedge ciaa.ciai.ta.run_s[1]) check_counter(16'd3);
      @(negedge c1m) check_port(1'b1); // toggle must be high after start

      @(posedge ciaa.ciai.ta.pls_o); // await for registered underflow
      @(posedge c1m) check_port(1'b0); // reload and check toggle output (low)

      @(posedge ciaa.ciai.ta.pls_o); // await for registered underflow
      @(posedge c1m) check_port(1'b1); // reload and check toggle output (high)

      @(posedge ciaa.ciai.ta.pls_o); // await for registered underflow
      @(posedge c1m) check_port(1'b0); // reload and check toggle output (low)

      cia_write_cycle(CIAA_CRA, 8'b00000110); // stop timer

      repeat(2) @(posedge c1m) check_port(1'b0); // check toggle output (low, must not change after stop)

      // Test 2b: Toggle reset on restart

      cia_write_cycle(CIAA_TA_LO, 8'd2); // load 2 in talo
      cia_write_cycle(CIAA_CRA, 8'b00010111); // start timer with force load

      @(posedge ciaa.ciai.ta.run_s[1]) check_counter(16'd2);
      @(negedge c1m) check_port(1'b1); // toggle must be high after start

      @(posedge ciaa.ciai.ta.pls_o); // await for registered underflow
      @(posedge c1m) check_port(1'b0); // reload and check toggle output (low)

      @(posedge ciaa.ciai.ta.pls_o); // await for registered underflow
      @(posedge c1m) check_port(1'b1); // reload and check toggle output (high)

      cia_write_cycle(CIAA_CRA, 8'b00000110); // stop timer

      repeat(2) @(posedge c1m) check_port(1'b1); // check toggle output (high, must not change after stop)

      // Test 3: Stop mid-count

      cia_write_cycle(CIAA_TA_LO, 8'd10); // load 10 in talo
      cia_write_cycle(CIAA_CRA, 8'b00010111); // start timer with force load

      @(posedge ciaa.ciai.ta.run_s[1]) check_counter(16'd10);
      @(negedge c1m) check_counter(16'd10);
      @(negedge c1m) check_counter(16'd9);
      @(negedge c1m) check_counter(16'd8);

      cia_write_cycle(CIAA_CRA, 8'b00000110); // stop timer

      check_counter(16'd7);

      // Test 4: Fast pulse when latch == 0
      cia_write_cycle(CIAA_EXT, 8'b00000110); // set CIA A extensions (fast pulse and fast reload)
      cia_write_cycle(CIAA_TA_LO, 8'd00); // load 0 in talo
      cia_write_cycle(CIAA_CRA, 8'b00010011); // start timer with force load (with pulse)

      @(posedge ciaa.ciai.ta.run_s[1])

       // expect consecutive underflows with half-cycle pulses
       repeat(4)
       begin
         @(posedge c1m);
         check_underflow(1'b1);

         @(negedge c1m);
         @(negedge clk_s[0]);
         check_port(1'b1);

         @(posedge c1m);
         @(negedge clk_s[0]);
         check_port(1'b0);
       end

       cia_write_cycle(CIAA_CRA, 8'b00000110); // stop timer

      // disable all extensions (vanilla CIA)
      cia_write_cycle(CIAA_EXT, 8'b00000000); // set CIA A extensions

      // Test 5: Force load while running
      cia_write_cycle(CIAA_TA_LO, 8'd7); // load 7 in talo
      cia_write_cycle(CIAA_CRA, 8'b00010110); // force load (without start)
      cia_write_cycle(CIAA_TA_LO, 8'd9); // load 8 in talo
      cia_write_cycle(CIAA_CRA, 8'b00000111); // start timer

      @(posedge ciaa.ciai.ta.run_s[1]) check_counter(16'd7);
      @(negedge c1m) check_counter(16'd6);
      @(negedge c1m) check_counter(16'd5);

      cia_write_cycle(CIAA_CRA, 8'b00010111); // force load (already started)

      @(negedge ciaa.ciai.ta.fld_i);  // wait for counter to load
      check_counter(16'd9);
      cia_write_cycle(CIAA_CRA, 8'b00000110); // stop timer

    end
  endtask

  task cia_test_rst();
    begin
      // ports A/B can't be tested there
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
      @(posedge c1m) eoc();  // wait metastable sync
      cia_read_check(CIAA_PRA, 8'b01010101);
      cia_read_check(CIAB_PRA, 8'b01010101);
      cia_write_cycle(CIAA_PRA, 8'b00000000);
      cia_write_cycle(CIAB_PRA, 8'b11111111);
      @(posedge c1m) eoc();  // wait metastable sync
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
      cia_write_cycle(CIAA_PRB, 8'b11111111); // pc from CIA B goes low during this cycle
      @(posedge c1m) eoc();  // wait for flag to be settled (on cycle after read/write)
      cia_read_check(CIAA_ICR, 8'b00010000); // check flag interrupt occured
      @(posedge c1m) eoc();  // wait metastable sync
      cia_write_cycle(CIAA_ICR, 8'b10010000); // set flag interrupt
      cia_read_check(CIAB_PRB, 8'b01010101);
      cia_read_check(CIAA_PRB, 8'b01010101);
      @(posedge c1m) eoc();  // wait for flag to be settled (on cycle after read/write)
      cia_read_check(CIAA_ICR, 8'b10010000); // check flag interrupt occured (with ir flag)
      cia_write_cycle(CIAB_PRB, 8'b11111111);
      cia_write_cycle(CIAA_PRB, 8'b00000000);
      @(posedge c1m) eoc();  // wait metastable sync
      cia_write_cycle(CIAA_ICR, 8'b00010000); // clear flag interrupt (with pending interrupt)
      cia_read_check(CIAA_ICR, 8'b00010000); // check flag interrupt occured (without ir flag)
      @(posedge c1m) eoc();  // wait metastable sync
      cia_read_check(CIAB_PRB, 8'b10101010);
      cia_read_check(CIAA_PRB, 8'b10101010);
      @(posedge c1m) eoc();  // wait for flag to be settled (on cycle after read/write)
      cia_read_check(CIAA_ICR, 8'b00010000); // check flag interrupt occured
    end
  endtask

  task cia_test_serial_a_to_b(input [7:0] data, input fast);
    begin
      cia_write_cycle(CIAA_EXT, { 5'b00000, fast, 1'b0, fast}); // set CIA A extensions
      cia_write_cycle(CIAB_EXT, { 5'b00000, fast, 1'b0, fast}); // set CIA B extensions
      cia_write_cycle(CIAA_CRA, 8'b01000000); // set CIA A for serial output
      @(posedge c1m) eoc();  // wait cnt to be high
      cia_write_cycle(CIAB_CRA, 8'b00000000); // set CIA A for serial input
      cia_write_cycle(CIAA_SDR, data); // set data to be transmited
      cia_write_cycle(CIAA_TA_LO, 8'b00000000);
      cia_write_cycle(CIAA_TA_HI, 8'b00000000);
      cia_read_cycle(CIAA_ICR);
      cia_read_cycle(CIAB_ICR);
      cia_write_cycle(CIAA_CRA, 8'b01010001); // start timer

      @(negedge ciaa.ciai.serial.cnt_o); // wait for first bit to be out
      cia_write_cycle(CIAA_SDR, ~data); // set data to be transmited (second word)

      @(negedge ciaa.ciai.serial.spo_o); // await for serial interrupt (output)
      cia_read_check(CIAA_ICR, 8'b00001001); // check serial interrupt

      @(negedge ciab.ciai.serial.spi_o); // await for serial interrupt (input)
      cia_read_check(CIAB_ICR, 8'b00001000); // check serial interrupt

      cia_read_check(CIAB_SDR, data); // check received data

      @(negedge ciaa.ciai.serial.spo_o); // await for serial interrupt (output)
      cia_read_check(CIAA_ICR, 8'b00001001); // check serial interrupt

      @(negedge ciab.ciai.serial.spi_o); // await for serial interrupt (input)
      cia_read_check(CIAB_ICR, 8'b00001000); // check serial interrupt

      @(negedge c1m) eoc(); // await for sdr to be updated
      cia_read_check(CIAB_SDR, ~data); // check received data

      cia_write_cycle(CIAA_CRA, 8'b01010000); // stop timer
    end
  endtask

  task cia_test_serial_b_to_a(input [7:0] data, input fast);
    begin
      cia_write_cycle(CIAB_EXT, { 5'b00000, fast, 1'b0, fast}); // set CIA A extensions
      cia_write_cycle(CIAA_EXT, { 5'b00000, fast, 1'b0, fast}); // set CIA B extensions
      cia_write_cycle(CIAB_CRA, 8'b01000000); // set CIA A for serial output
      @(posedge c1m) eoc();  // wait cnt to be high
      cia_write_cycle(CIAA_CRA, 8'b00000000); // set CIA A for serial input
      cia_write_cycle(CIAB_SDR, data); // set data to be transmited
      cia_write_cycle(CIAB_TA_LO, 8'b00000000);
      cia_write_cycle(CIAB_TA_HI, 8'b00000000);
      cia_read_cycle(CIAA_ICR);
      cia_read_cycle(CIAB_ICR);
      cia_write_cycle(CIAB_CRA, 8'b01010001); // start timer

      @(negedge ciab.ciai.serial.cnt_o); // wait for first bit to be out
      cia_write_cycle(CIAB_SDR, ~data); // set data to be transmited (second word)

      @(negedge ciab.ciai.serial.spo_o); // await for serial interrupt (output)
      cia_read_check(CIAB_ICR, 8'b00001001); // check serial interrupt

      @(negedge ciaa.ciai.serial.spi_o); // await for serial interrupt (input)
      cia_read_check(CIAA_ICR, 8'b00001000); // check serial interrupt

      cia_read_check(CIAA_SDR, data); // check received data

      @(negedge ciab.ciai.serial.spo_o); // await for serial interrupt (output)
      cia_read_check(CIAB_ICR, 8'b00001001); // check serial interrupt

      @(negedge ciaa.ciai.serial.spi_o); // await for serial interrupt (input)
      cia_read_check(CIAA_ICR, 8'b00001000); // check serial interrupt

      @(negedge c1m) eoc(); // await for sdr to be updated
      cia_read_check(CIAA_SDR, ~data); // check received data

      cia_write_cycle(CIAB_CRA, 8'b01010000); // stop timer
    end
  endtask

  task cia_test_tod();
    begin
      // enable tod pin
      tod_drv = 1'b0;
      tod_ovr = 1'b1;

      // clear interrupts
      cia_read_cycle(CIAA_ICR);

      // Test 1 : Basic counting

      // set tod to 0x10
      cia_write_tod(24'h000010);

      repeat(5) pulse_tod();

      cia_read_check(CIAA_TOD_LOW, 8'h15);

      // Test 2 : Freeze and read the latch

      cia_read_check(CIAA_TOD_HI, 8'h00); // also freeze the latch

      repeat(5) pulse_tod();

      cia_read_check(CIAA_TOD_LOW, 8'h15); // must still return 15 (and unfreeze)
      cia_read_check(CIAA_TOD_HI, 8'h00); // also freeze the latch
      cia_read_check(CIAA_TOD_LOW, 8'h1a); // must return 1a

      // Test 3 : Stop / Restart the TOD

      cia_write_cycle(CIAA_TOD_HI, 8'b00000000); // stop the tod

      // pulse it
      repeat(5) pulse_tod();

      cia_read_check(CIAA_TOD_LOW, 8'h1a); // must return 1a

      cia_write_cycle(CIAA_TOD_LOW, 8'h20); // restart the tod as 0x20

      // pulse it again
      repeat(5) pulse_tod();

      cia_read_check(CIAA_TOD_LOW, 8'h25); // must return 25

      // Test 4 : tod alrm

      
      cia_write_alrm(24'h00002a);

      // pulse to 0x2a
      repeat(5) pulse_tod();

      cia_read_check(CIAA_ICR, 8'b00000100); // must return alrm
      cia_read_check(CIAA_TOD_LOW, 8'h2a); // must return 2a

      cia_write_cycle(CIAA_TOD_HI, 8'b00000000); // stop the tod

      // disable tod pin
      tod_drv = 1'b0;
      tod_ovr = 1'b0;
    end
  endtask

  task cia_write_cycle(
      input [4:0] adr_i,
      input [7:0] dat_i
    );
    begin
      // go to end of current cycle
      eoc();

      cia_dat_i = dat_i;
      cia_adr = adr_i[3:0];
      cia_we = 1;
      { ciaa_sel, ciab_sel } = { ~adr_i[4], adr_i[4] };

      @(negedge c1m);

      eoc();
      { ciaa_sel, ciab_sel } = 2'b0;
      cia_adr = 4'b0;
      cia_we = 0;
    end
  endtask

  task cia_read_cycle(
      input [4:0] adr_i
    );
    begin
      // go to end of current cycle
      eoc();

      cia_adr = adr_i[3:0];
      cia_we = 0;
      { ciaa_sel, ciab_sel } = { ~adr_i[4], adr_i[4] };

      @(negedge c1m) cia_dat_r = cia_dat;

      eoc();
      { ciaa_sel, ciab_sel } = 2'b0;
      cia_adr = 4'b0;
      cia_we = 0;
    end
  endtask

  task cia_read_check(
      input [4:0] adr_i,
      input [7:0] dat_i
    );
    begin
      cia_read_cycle(adr_i);

      if (cia_dat_r != dat_i)
      begin
        $display("read error : %t address 0x%h got %b expected %b", $time, adr_i, cia_dat_r, dat_i);
      end
    end
  endtask

  // Helper task: read counter (timer A)
  task check_counter(input [15:0] expected);
    reg [15:0] actual;
    begin
      actual = ciaa.ciai.ta.cnt_o;
      if (actual !== expected)
      begin
        $display("ERROR @%t: Counter mismatch! Expected=%04h, Got=%04h",
                 $time, expected, actual);
      end
      else
      begin
        $display("OK @%t: Counter=%04h", $time, actual);
      end
    end
  endtask

  // Helper task: check output pulse (timer A)
  task check_pulse(input expected);
    reg actual;
    begin
      actual = ciaa.ciai.ta.pls_o;
      if (actual !== expected)
      begin
        $display("ERROR @%t: Pulse mismatch! Expected=%b, Got=%b",
                 $time, expected, actual);
      end
      else
      begin
        $display("OK @%t: Pulse=%b", $time, actual);
      end
    end
  endtask

  // Helper task: check port output (timer A)
  task check_port(input expected);
    reg actual;
    begin
      actual = ciaa.ciai.ta.prb_o;
      if (actual !== expected)
      begin
        $display("ERROR @%t: Port mismatch! Expected=%b, Got=%b",
                 $time, expected, actual);
      end
      else
      begin
        $display("OK @%t: Port=%b", $time, actual);
      end
    end
  endtask

  // Helper task: check underflow output (timer A)
  task check_underflow(input expected);
    reg actual;
    begin
      actual = ciaa.ciai.ta.unfl_o;
      if (actual !== expected)
      begin
        $display("ERROR @%t: Underflow mismatch! Expected=%b, Got=%b",
                 $time, expected, actual);
      end
      else
      begin
        $display("OK @%t: Underflow=%b", $time, actual);
      end
    end
  endtask

  task pulse_tod();
    begin
      eoc();
      // generate tod pulse
      @(negedge c1m) tod_drv = 1'b1;
      // first stage sync passed (on posedge)
      @(negedge c1m) tod_drv = 1'b0;
      // second stage sync passed (on posedge, pulse generated)
      repeat(2) @(negedge c1m);
      eoc();
    end
  endtask

  task cia_write_tod(
      input [23:0] value
    );
    begin
      cia_write_cycle(CIAA_TOD_HI, value[23:16]);
      cia_write_cycle(CIAA_TOD_MID, value[15:8]);
      cia_write_cycle(CIAA_TOD_LOW, value[7:0]);
    end
  endtask

  task cia_write_alrm(
      input [23:0] value
    );
    begin
      // select ALRM register using CRB
      cia_write_cycle(CIAA_CRB, { 1'b1, ciaa.ciai.decoder.crb_i[6:0] });
      cia_write_cycle(CIAA_TOD_HI, value[23:16]);
      cia_write_cycle(CIAA_TOD_MID, value[15:8]);
      cia_write_cycle(CIAA_TOD_LOW, value[7:0]);
      cia_write_cycle(CIAA_CRB, { 1'b0, ciaa.ciai.decoder.crb_i[6:0] });
    end
  endtask

  // Helper task: pulse reset
  task pulse_reset();
    begin
      // go to end of current cycle
      eoc();

      rst_i = 1'b1;

      // consume 1 full cycle
      @(posedge c1m) eoc();

      rst_i = 1'b0;
    end
  endtask

  // Helper task: go to end of cycle
  task eoc();
    begin
      case(clk_s)
        2'd0,2'd1:
        begin
          @(negedge clk_s[0]);
          @(posedge clk_s[0]);
        end
        2'd2:
        begin
          @(posedge clk_s[0]);
        end
      endcase
    end
  endtask

  // Clock generation (1MHz phi2)
  initial
  begin
    clk_s = 0;
    c1m = 0;
    forever
      #250 clk_s = clk_s + 1; // 1us period = 2MHz
  end

  always @(posedge c2m)
  begin
    // divide by 2 for 1MHz period
    c1m = clk_s[1];
  end

  initial
  begin
    rst_i = 0;
  end

  // Timeout watchdog
  initial
  begin
    #600000; // 100us timeout
    $display("ERROR: Simulation timeout!");
    $finish;
  end
endmodule
