// Copyright 2011, 2012 Frederic Requin; part of the MCC216 project
// Copyright 2020, Renee Cousins; part of the Amiga Replacement Project
//
// Denise re-implementation is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Denise re-implementation is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// This file implements the dual port SRAM for the color look up table

// CLUT Latency is :
// -----------------
// 28 MHz : 1 cycle
// CDAC_n : 0.5 cycles

module color_table
(
  input         clk,
  input         cpu_wr,
  input   [4:0] cpu_idx,
  input  [11:0] cpu_rgb,
  input         clut_rd,
  input   [4:0] clut_idx,
  output [11:0] clut_rgb
);

//`ifdef SIMULATION

// Infered block RAM
reg  [11:0] r_mem_clut [0:31];

// Write port
always@(posedge clk) begin
  if (cpu_wr) begin
    r_mem_clut[cpu_idx] <= cpu_rgb;
  end
end

reg  [11:0] r_q_p0;
reg  [11:0] r_q_p1;

// Read port
always@(posedge clk) begin
  if (clut_rd)
    r_q_p0 <= r_mem_clut[clut_idx];
  r_q_p1 <= r_q_p0;
end

assign clut_rgb = r_q_p1;

// `else

// // Declared Altera block RAM
// altsyncram U_altsyncram_32x12
// (
//   // Port A : write side (Copper or CPU)
//   .clock0    (clk),
//   .wren_a    (cpu_wr),
//   .address_a (cpu_idx),
//   .data_a    (cpu_rgb),
//   // Port B : read side (Bitplanes or Sprites)
//   .clock1    (clk),
//   .rden_b    (clut_rd),
//   .address_b (clut_idx),
//   .q_b       (clut_rgb)
// );
// defparam 
//   U_altsyncram_32x12.operation_mode = "DUAL_PORT",
//   U_altsyncram_32x12.width_a        = 12,
//   U_altsyncram_32x12.widthad_a      = 5,
//   U_altsyncram_32x12.width_b        = 12,
//   U_altsyncram_32x12.widthad_b      = 5,
//   U_altsyncram_32x12.outdata_reg_b  = "CLOCK1";

// `endif

endmodule
