`include "arg_defs.vh"

module sdram_ctrl
(
  //--------------------
  // Clocks and reset --
  //--------------------
  // Global reset
  input             rst,
  // Controller clock
  input             clk,
  // Sequencer cycles
  input      [11:0] seq_cyc,
  // Sequencer phase
  input             seq_ph,
  // Refresh cycle
  input             refr_cyc,
  //------------------------
  // Access port #1 (CPU) --
  //------------------------
  // RAM select
  input             ap1_ram_sel,
  // Address bus
  input      [23:1] ap1_address,
  // Read enable
  input             ap1_rden,
  // Write enable
  input             ap1_wren,
  // Byte enable
  input       [1:0] ap1_bena,
  // Data bus (read)
  output     [15:0] ap1_rddata,
  // Data bus (write)
  input      [15:0] ap1_wrdata,
  // Burst size
  input       [2:0] ap1_bst_siz,
  // Read burst active
  output reg        ap1_rd_bst_act,
  // Write burst active
  output            ap1_wr_bst_act,
  //------------------------
  // Access port #2 (GPU) --
  //------------------------
  // RAM select
  input             ap2_ram_sel,
  // Address bus
  input      [23:1] ap2_address,
  // Read enable
  input             ap2_rden,
  // Write enable
  input             ap2_wren,
  // Byte enable
  input       [1:0] ap2_bena,
  // Data bus (read)
  output     [15:0] ap2_rddata,
  // Data bus (write)
  input      [15:0] ap2_wrdata,
  // Burst size
  input       [2:0] ap2_bst_siz,
  // Read burst active
  output reg        ap2_rd_bst_act,
  // Write burst active
  output            ap2_wr_bst_act,
  //------------------------
  // Access port #3 (CTL) --
  //------------------------
  // RAM select
  input             ap3_ram_sel,
  // Address bus
  input      [23:1] ap3_address,
  // Read enable
  input             ap3_rden,
  // Write enable
  input             ap3_wren,
  // Byte enable
  input       [1:0] ap3_bena,
  // Data bus (read)
  output     [15:0] ap3_rddata,
  // Data bus (write)
  input      [15:0] ap3_wrdata,
  // Burst size
  input       [2:0] ap3_bst_siz,
  // Read burst active
  output reg        ap3_rd_bst_act,
  // Write burst active
  output            ap3_wr_bst_act,
  //------------------------
  // SDRAM memory signals --
  //------------------------
  // SDRAM controller ready
  output reg        sdram_rdy,
  // SDRAM chip select
  output reg        sdram_cs_n,
  // SDRAM row address strobe
  output reg        sdram_ras_n,
  // SDRAM column address strobe
  output reg        sdram_cas_n,
  // SDRAM write enable
  output reg        sdram_we_n,
  // SDRAM DQ masks
  output reg  [1:0] sdram_dqm_n,
  // SDRAM bank address
  output reg  [1:0] sdram_ba,
  // SDRAM address
  output reg [11:0] sdram_addr,
  // SDRAM data
  inout      [15:0] sdram_dq
);

// SDRAM memory size
parameter SDRAM_SIZE     = 16;
// SDRAM operational frequency
parameter SDRAM_FREQ     = 85909090;
// Hidden refresh mode
parameter HIDDEN_REFRESH = 0;
// MODE REGISTER SET value (RS = 00, WB = 0, OP = 00, CL = 010, BT = 0, BL = 011)
parameter MRS_VALUE = 12'b000000100011;
// Refresh period
parameter REF_COUNT = ((SDRAM_FREQ / ((12 * 64000)))) - 1;
// Clock-to-output delay
parameter Tco_dly = 4.5;

// Port select signals
reg   [2:0] r_psel;       // Port select (one hot)
reg   [2:0] r_psel_dly;   // Port select delayed

// Refresh signals
reg         r_refr_req;   // Refresh requested
reg         r_refr_act;   // Refresh active
reg         r_refr_ack;   // Refresh acknowledged
reg  [31:0] r_refr_ctr;   // Refresh counter

// Port multiplexer signals
wire        w_rden;       // Read enable
reg         r_rd_reg;     // Registered read enable
reg         r_rd_act;     // Read active
wire        w_wren;       // Write enable
reg         r_wr_reg;     // Registered write enable
reg         r_wr_act;     // Write active
wire        w_ram_sel;    // RAM select
reg   [2:0] r_rd_bctr;    // Read burst counter
reg   [2:0] r_wr_bctr;    // Write burst counter
wire  [2:0] w_bst_siz;    // Burst size (load value of burst counters)
reg   [2:0] r_bst_stp;    // Burst stop
wire  [1:0] w_dqm;        // Bytes masks
wire [23:1] w_addr;       // Address
reg  [15:0] r_rddata;     // Data read
wire [15:0] w_wrdata;     // Data written
reg         r_out_ena;    // Data output enable
reg         r_out_ena_d;  // Data output enable (delayed)
reg  [15:0] r_data_out;   // Data output
reg  [15:0] r_data_out_d; // Data output (delayed)

// SDRAM speed adjustment
wire        w_rd_start;   // Read start condition
wire        w_wr_start;   // Write start condition
wire  [3:0] w_rd_cycle;   // First read cycle number

// Initialization signals
reg   [2:0] r_init_fsm;   // SDRAM initialization state machine
reg  [10:0] r_init_tmr;   // SDRAM initialization timer

// Output registers
reg         r_sdram_cs_n;  // SDRAM chip select
reg         r_sdram_ras_n; // SDRAM row address strobe
reg         r_sdram_cas_n; // SDRAM column address strobe
reg         r_sdram_we_n;  // SDRAM write enable
reg   [1:0] r_sdram_dqm_n; // SDRAM DQ masks
reg   [1:0] r_sdram_ba;    // SDRAM bank address
reg  [11:0] r_sdram_addr;  // SDRAM address

  // Signal multiplexing based on the port select
  assign w_wren         = (ap1_wren & r_psel[0])
                        | (ap2_wren & r_psel[1])
                        | (ap3_wren & r_psel[2]);
  assign w_rden         = (ap1_rden & r_psel[0])
                        | (ap2_rden & r_psel[1])
                        | (ap3_rden & r_psel[2]);
  assign w_ram_sel      = (HIDDEN_REFRESH == 1)
                        ? (r_psel[0] | r_psel[1] | r_psel[2])
                        : (r_psel[0] | r_psel[1] | r_psel[2]) & ~r_refr_req;
  assign w_dqm[0]       = (ap1_bena[0] & r_psel[0])
                        | (ap2_bena[0] & r_psel[1])
                        | (ap3_bena[0] & r_psel[2]);
  assign w_dqm[1]       = (ap1_bena[1] & r_psel[0])
                        | (ap2_bena[1] & r_psel[1])
                        | (ap3_bena[1] & r_psel[2]);
  assign w_bst_siz[2]   = (ap1_bst_siz[2] & r_psel[0])
                        | (ap2_bst_siz[2] & r_psel[1])
                        | (ap3_bst_siz[2] & r_psel[2]);
  assign w_bst_siz[1]   = (ap1_bst_siz[1] & r_psel[0])
                        | (ap2_bst_siz[1] & r_psel[1])
                        | (ap3_bst_siz[1] & r_psel[2]);
  assign w_bst_siz[0]   = (ap1_bst_siz[0] & r_psel[0])
                        | (ap2_bst_siz[0] & r_psel[1])
                        | (ap3_bst_siz[0] & r_psel[2]);
  assign w_addr[23:1]   = (ap1_address[23:1] & {23{r_psel[0]}})
                        | (ap2_address[23:1] & {23{r_psel[1]}})
                        | (ap3_address[23:1] & {23{r_psel[2]}});
  assign w_wrdata[15:0] = (ap1_wrdata[15:0] & {16{r_psel[0]}})
                        | (ap2_wrdata[15:0] & {16{r_psel[1]}})
                        | (ap3_wrdata[15:0] & {16{r_psel[2]}});

  // SDRAM speed adjustment
  assign w_rd_cycle = (SDRAM_FREQ < 50000000) ? 4'd2 : 4'd3;
  assign w_rd_start = (SDRAM_FREQ < 50000000) ? (seq_cyc[2] & r_rd_reg) : (seq_cyc[4] & r_rd_reg);
  assign w_wr_start = (SDRAM_FREQ < 50000000) ? (seq_cyc[0] & w_wren & w_ram_sel) : (seq_cyc[1] & r_wr_reg);
  
  // Write burst active flags, one cycle before "r_wr_act"
  assign ap1_wr_bst_act = (r_wr_bctr[0] | r_wr_bctr[1] | r_wr_bctr[2] | w_wr_start) & r_psel[0];
  assign ap2_wr_bst_act = (r_wr_bctr[0] | r_wr_bctr[1] | r_wr_bctr[2] | w_wr_start) & r_psel[1];
  assign ap3_wr_bst_act = (r_wr_bctr[0] | r_wr_bctr[1] | r_wr_bctr[2] | w_wr_start) & r_psel[2];
  
  // SDRAM data read
  assign ap1_rddata = r_rddata;
  assign ap2_rddata = r_rddata;
  assign ap3_rddata = r_rddata;
  
  // Hidden refresh / port select :
  //-------------------------------
  // rst         : Global reset
  // clk         : SDRAM controller clock
  // seq_cyc     : Sequencer cycle (0 to 11)
  // seq_ph      : Sequencer phase (0 or 1)
  // r_refr_req  : Internal refresh cycle request
  // r_refr_ack  : Internal refresh cycle acknowledge
  // r_refr_ctr  : Internal refresh counter
  // r_psel      : Port select (one hot)
  // r_psel_dly  : Delayed port select
  // ap1_ram_sel : Port #1 access
  // ap2_ram_sel : Port #2 access
  // ap3_ram_sel : Port #3 access
  always @(negedge rst or posedge clk) begin
    if (rst) begin
      // Refresh counter
      r_refr_ctr <= REF_COUNT;
      // Refresh cycle request
      r_refr_req <= 1'b0;
    end else begin
      // Hidden refresh case
      if (HIDDEN_REFRESH == 1) begin
        // Sequencer cycle #11
        if (seq_cyc[11]) begin
          // Internal refresh counter
          if (r_refr_ctr == 0) begin
            r_refr_req <= 1'b1;
            r_refr_ctr <= REF_COUNT;
          end
          else begin
            r_refr_ctr <= r_refr_ctr - 1;
          end
        end
        // When refresh cycle is acknowledged
        if (r_refr_ack == 1'b1) begin
          // Clear the refresh cycle request
          r_refr_req <= 1'b0;
        end
      end else begin
        // External refresh
        r_refr_req <= refr_cyc;
      end
    end
    
    if (rst) begin
      // Port select
      r_psel     <= 3'b000;
      r_psel_dly <= 3'b000;
    end else begin
      // Access port select
      if (seq_cyc[11]) begin
        if (!seq_ph) begin
          // Phase #0 : select port #1 (CPU) -> #3 (CTL) -> none
          r_psel[0] <= ap1_ram_sel;
          r_psel[1] <= 1'b0;
          r_psel[2] <= ap3_ram_sel & ~ap1_ram_sel;
        end
        else begin
          // Phase #1 : select port #2 (GPU) -> #1 (CPU) -> #3 (CTL) -> none
          r_psel[0] <= ap1_ram_sel & ~ap2_ram_sel;
          r_psel[1] <= ap2_ram_sel;
          r_psel[2] <= ap3_ram_sel & ~(ap1_ram_sel | ap2_ram_sel);
        end
      end
      // Delayed port select for data read multiplexer
      if (seq_cyc[1]) begin
        r_psel_dly <= r_psel;
      end
    end
  end

  // Burst activities :
  //-------------------
  // rst        : Global reset
  // clk        : SDRAM controller clock
  // w_rd_start : Read start conditions
  // w_wr_start : Write start conditions
  // r_rd_reg   : Read mode (registered)
  // r_rd_act   : Read active
  // r_wr_act   : Write active
  // r_rd_bctr  : Burst read counter
  // r_wr_bctr  : Burst write counter
  // r_psel_dly : Port select delayed
  always @(negedge rst or posedge clk) begin
    if (rst) begin
      // Burst signals
      r_rd_act       <= 1'b0;
      r_wr_act       <= 1'b0;
      r_rd_bctr      <= 3'b000;
      r_wr_bctr      <= 3'b000;
      ap1_rd_bst_act <= 1'b0;
      ap2_rd_bst_act <= 1'b0;
      ap3_rd_bst_act <= 1'b0;
      // Data bus
      r_rddata       <= 16'h0000;
      r_sdram_dqm_n    <= 2'b11;
      r_out_ena      <= 1'b0;
      r_data_out     <= 16'h0000;
    end else begin
      // Prepare write burst cycles
      if (w_wr_start) begin
        // Set the active bits
        r_wr_act  <= 1'b1;
        // Start the burst counter
        r_wr_bctr <= w_bst_siz;
      end
      // Prepare read burst cycles
      if (w_rd_start) begin
        // Set the active bits
        r_rd_act  <= 1'b1;
        // Start the burst counter
        r_rd_bctr <= r_bst_stp;
      end
      // Read burst counter management
      if (r_rd_act) begin
        if (r_rd_bctr == 0) begin
          // Burst finished : clear the active bit
          r_rd_act <= 1'b0;
        end
        else begin
          r_rd_bctr <= r_rd_bctr - 3'b1;
        end
      end
      // Write burst counter management
      if (r_wr_act) begin
        if (r_wr_bctr == 0) begin
          // Burst finished : clear the active bit
          r_wr_act <= 1'b0;
        end
        else begin
          r_wr_bctr <= r_wr_bctr - 3'b1;
        end
      end
      // Read burst active flags, one cycle after "r_rd_act"
      ap1_rd_bst_act <= r_rd_act & r_psel_dly[0];
      ap2_rd_bst_act <= r_rd_act & r_psel_dly[1];
      ap3_rd_bst_act <= r_rd_act & r_psel_dly[2];
      // Read SDRAM data
      r_rddata <= sdram_dq;
      // Write SDRAM data / DQM management
      if (r_wr_act) begin
        r_sdram_dqm_n[0] <= ~w_dqm[0];
        r_sdram_dqm_n[1] <= ~w_dqm[1];
        r_out_ena      <= 1'b1;
        r_data_out     <= w_wrdata;
      end
      else begin
        r_sdram_dqm_n[0] <= ~r_rd_reg;
        r_sdram_dqm_n[1] <= ~r_rd_reg;
        r_out_ena      <= 1'b0;
        r_data_out     <= 16'h0000;
      end
    end
  end

  // SDRAM controller state machine :
  //---------------------------------
  //  rst        : Global reset
  //  clk        : SDRAM controller clock
  //  seq_cyc    : Sequencer cycle
  //  r_refr_req : Refresh cycle requested
  //  r_refr_act : Refresh cycle active
  //  r_refr_ack : Refresh cycle acknowledge
  //  w_ram_sel  : SDRAM selected
  //  w_rden     : Read enable flag
  //  w_wren     : Write enable flag
  //  r_rd_reg   : Read mode (registered)
  //  r_wr_reg   : Write mode (registered)
  //  w_bst_siz  : Burst size (1 to 8 words)
  //  r_bst_stp  : Burst stop cycle
  //  r_init_fsm : SDRAM initialization state
  //  r_init_tmr : SDRAM initialization timer (>100 us)
  always @(negedge rst or posedge clk) begin
    if (rst) begin
      // SDRAM outputs
      r_sdram_cs_n  <= 1'b1;
      r_sdram_ras_n <= 1'b1;
      r_sdram_cas_n <= 1'b1;
      r_sdram_we_n  <= 1'b1;
      r_sdram_ba    <= 2'b00;
      r_sdram_addr  <= 12'b000000000000;
      // Controller state
      r_rd_reg      <= 1'b0;
      r_wr_reg      <= 1'b0;
      r_bst_stp     <= 3'b000;
      sdram_rdy     <= 1'b0;
      r_refr_ack    <= 1'b0;
      r_refr_act    <= 1'b0;
      // 1024 * 12 cycles > 100 us
      r_init_tmr    <= 11'd0;
      r_init_fsm    <= 3'b000;
    end else begin
      // Default : NOPs
      r_sdram_ras_n <= 1'b1;
      r_sdram_cas_n <= 1'b1;
      r_sdram_we_n  <= 1'b1;
      if (r_init_fsm[2]) begin
        // Chip select management
        if (seq_cyc[0]) begin
          // RAM selected or refresh request
          r_sdram_cs_n <= ~(w_ram_sel | r_refr_req);
        end
        // If there is an active refresh
        if (r_refr_act) begin
          //------------------
          // Refresh cycles --
          //------------------
          // Cycle #0 : clear read/write enable signals
          r_rd_reg <= 1'b0;
          r_wr_reg <= 1'b0;
          // Cycle #2 : prepare AUTO REFRESH cmd for cycle #3
          if (seq_cyc[2]) begin
            r_sdram_ras_n <= 1'b0;
            r_sdram_cas_n <= 1'b0;
          end
          // Cycle #9 : acknowledge the refresh request
          if (seq_cyc[9]) begin
            // Hidden refresh case
            if (HIDDEN_REFRESH == 1) begin
              r_refr_ack <= 1'b1;
            end
            r_refr_act <= 1'b0;
          end
        end
        else begin
          //-----------------
          // Normal cycles --
          //-----------------
          // Hidden refresh case
          if (HIDDEN_REFRESH == 1) begin
            // Clear any refresh acknowledge
            r_refr_ack <= 1'b0;
          end
          if (seq_cyc[0]) begin
            // If no access, activate refresh
            r_refr_act <= ~((w_rden | w_wren) & w_ram_sel) & r_refr_req;
            // Register read/write enable signals
            r_rd_reg   <= w_rden & w_ram_sel;
            r_wr_reg   <= w_wren & w_ram_sel;
            // Register the burst stop
            r_bst_stp  <= w_bst_siz;
          end
          // Cycle #0 : prepare ACTIVATE cmd for cycle #1
          //            set the row address and the bank number
          if ((seq_cyc[0]) && (w_ram_sel) && ((w_rden) || (w_wren))) begin
            r_sdram_ras_n <= 1'b0;
            if (SDRAM_SIZE == 16) begin
              // 4096 rows : 12 address lines
              r_sdram_addr  <= w_addr[23:12];
              // 4 banks : 2 address lines
              r_sdram_ba    <= w_addr[11:10];
            end else begin
              // 4096 rows : 12 address lines
              r_sdram_addr  <= w_addr[22:11];
              // 4 banks : 2 address lines
              r_sdram_ba    <= w_addr[10:9];
            end
          end
          // Cycle #1/2 : prepare READ/WRITE cmd for next cycle
          //              set the column address and the bank number
          if ((seq_cyc[w_rd_cycle - 1]) && ((r_rd_reg) || (r_wr_reg))) begin
            r_sdram_cas_n <= 1'b0;
            r_sdram_we_n  <= ~r_wr_reg;
            if (SDRAM_SIZE == 16)
              // 512 columns : 9 address lines
              r_sdram_addr  <= {3'b010, w_addr[9:1]};
            else
              // 256 columns : 8 address lines
              r_sdram_addr  <= {4'b0100, w_addr[8:1]};
          end
          // Cycles #2/3+ : prepare the PRECHARGE cmd (burst stop)
          //if ((seq_cyc[w_rd_cycle + r_bst_stp]) && ((r_rd_reg) || (r_wr_reg))) begin
          //  r_sdram_ras_n <= 1'b0;
          //  r_sdram_we_n  <= 1'b0;
          //end
        end
      end
      else begin
        //---------------
        // Init cycles --
        //---------------
        if (r_init_tmr[10]) begin
          // Select SDRAM
          r_sdram_cs_n <= 1'b0;
          case (r_init_fsm[1:0])
            2'd0 : begin
              // Prepare PRECHARGE ALL cmd
              if (seq_cyc[3]) begin
                r_sdram_ras_n    <= 1'b0;
                r_sdram_we_n     <= 1'b0;
                r_sdram_addr[10] <= 1'b1;
              end
            end
            2'd1 : begin
              // Prepare AUTO REFRESH cmd
              if (seq_cyc[3]) begin
                r_sdram_ras_n <= 1'b0;
                r_sdram_cas_n <= 1'b0;
              end
            end
            2'd2 : begin
              // Prepare AUTO REFRESH cmd
              if (seq_cyc[3]) begin
                r_sdram_ras_n <= 1'b0;
                r_sdram_cas_n <= 1'b0;
              end
            end
            2'd3 : begin
              // Prepare MODE REGISTER SET value
              if (seq_cyc[1]) begin
                r_sdram_addr <= MRS_VALUE;
              end
              // Prepare MODE REGISTER SET cmd
              if (seq_cyc[3]) begin
                r_sdram_ras_n <= 1'b0;
                r_sdram_cas_n <= 1'b0;
                r_sdram_we_n  <= 1'b0;
              end
              // SDRAM is initialized
              if (seq_cyc[10]) begin
                sdram_rdy <= 1'b1;
              end
            end
            default : begin
            end
          endcase
          // Cycle #11 : next state
          if (seq_cyc[11]) begin
            r_init_fsm <= r_init_fsm + 3'd1;
          end
        end
        else begin
          // Deselect SDRAM
          r_sdram_cs_n <= 1'b1;
          // Cycle #11 : timer management
          if (seq_cyc[11]) begin
            r_init_tmr <= r_init_tmr + 11'd1;
          end
        end
      end
    end
  end
  
  // TCO delay on all outputs
  always@(r_sdram_cs_n or r_sdram_ras_n or r_sdram_cas_n or r_sdram_we_n or
          r_sdram_dqm_n or r_sdram_ba or r_sdram_addr or r_out_ena or r_data_out) begin
  `ifdef SIMULATION
    sdram_cs_n   <= #Tco_dly r_sdram_cs_n;
    sdram_ras_n  <= #Tco_dly r_sdram_ras_n;
    sdram_cas_n  <= #Tco_dly r_sdram_cas_n;
    sdram_we_n   <= #Tco_dly r_sdram_we_n;
    sdram_dqm_n  <= #Tco_dly r_sdram_dqm_n;
    sdram_ba     <= #Tco_dly r_sdram_ba;
    sdram_addr   <= #Tco_dly r_sdram_addr;
    r_out_ena_d  <= #Tco_dly r_out_ena;
    r_data_out_d <= #Tco_dly r_data_out;
  `else
    sdram_cs_n   <= r_sdram_cs_n;
    sdram_ras_n  <= r_sdram_ras_n;
    sdram_cas_n  <= r_sdram_cas_n;
    sdram_we_n   <= r_sdram_we_n;
    sdram_dqm_n  <= r_sdram_dqm_n;
    sdram_ba     <= r_sdram_ba;
    sdram_addr   <= r_sdram_addr;
    r_out_ena_d  <= r_out_ena;
    r_data_out_d <= r_data_out;
  `endif
  end

  // SDRAM data write
  assign sdram_dq = r_out_ena_d ? r_data_out_d : 16'bZ;

  // Setup and hold times check for DQ
  reg r_dq_noti;

  specify
    specparam
      Tsu_dly =  0.7, // Input setup time
      Th_dly  = -0.5; // Input hold time
    $setuphold(posedge clk, sdram_dq, Tsu_dly, Th_dly, r_dq_noti);
  endspecify

  always @(r_dq_noti)
  begin
    $display($realtime, " ns : Setup/Hold time violation on DQ inputs");
  end

endmodule
