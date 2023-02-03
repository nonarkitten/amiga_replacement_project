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

// When S is high, we pick the "B"
// When S is low, we pick the "A"
//
// 1A	M0V	V Pulse     CCK low
// 1B	M0V	VQ Pulse    CCK high
// 2A	M0H	H Pulese    CCK low
// 2B	M0H	HQ Pulse    CCK high
// 3A	M1V	V Pulse     CCK low
// 3B	M1V	VQ Pulse    CCK high
// 4A	M1H	H Pulese    CCK low
// 4B	M1H	HQ Pulse    CCK high
//
// CLK should sample on CCKQ
//
// in top:
// denise_quad m0h(cckq, m0h_in, r_JOY0DAT[7:0]);
// denise_quad m0v(cckq, m0v_in, r_JOY0DAT[15:8]);
// denise_quad m1h(cckq, m1h_in, r_JOY1DAT[7:0]);
// denise_quad m1v(cckq, m1v_in, r_JOY1DAT[15:8]);

reg [15:0] r_JOY0DAT;         // 8'b00000101
reg [15:0] r_JOY1DAT;         // 8'b00000110
reg [15:0] r_JOYTEST;         // 8'b00011011

module denise_quad
(
	input clk;
	input quadMux;
	output [7:0] count;
);
	reg [2:0] quadA_delayed, quadB_delayed;
	reg [7:0] count;
		
	always @(negedge clk) quadA_delayed <= { quadA_delayed[1:0], quadMux };
	always @(posedge clk) quadB_delayed <= { quadB_delayed[1:0], quadMux };

	wire count_enable    = quadA_delayed[1] ^ quadA_delayed[2] ^ quadB_delayed[1] ^ quadB_delayed[2];
	wire count_direction = quadA_delayed[1] ^ quadB_delayed[2];

	always @(posedge clk) begin
		if(count_enable) begin
			if(count_direction) count <= count+1; 
			else count <= count-1;
		end
	end
endmodule
