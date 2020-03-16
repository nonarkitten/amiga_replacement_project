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

module rga_decodeer(
  input      [8:1] rga;
  output     [9:0] enable;	
  output reg [8:1] rga_out;
);

// Reset enable lines for edge detection
always @negedge(clk) begin
  enable <= 10'd0;
end

always @posedge(clk) begin
  wire sdat <= rga[2];
  
  rga_out <= rga;

  case (rga) inside
  
  // ORIGINAL ENABLE LINES FROM OCS PATENT, # INDICATE PATENT NOTE
  enable[0] <= (rga[8:1] == 8'b00000111 )  1'b1 : 1'b0 ; // 353 CLXDAT
  enable[1] <= (rga[8:1] == 8'b01001100 )  1'b1 : 1'b0 ; // 351 CLXCON
  enable[2] <= (rga[8:4] == 5'b10001    )  1'b1 : 1'b0 ; // 329 BPLxDAT
  enable[3] <= (rga[8:3] == 6'b100000   )  1'b1 : 1'b0 ; // 327 BPLCONx
  enable[4] <= (rga[8:3] ==             )  1'b1 : 1'b0 ; // 339 (Horz Sync)
  enable[5] <= (rga[8:6] == 3'b101      )  sdat : 1'b0 ; // 345 SPRxDATA/B
  enable[6] <= (rga[8:6] == 3'b101      ) !sdat : 1'b0 ; // 343 SPRxCTL/POS
  enable[7] <= (rga[8:1] ==             )  1'b1 : 1'b0 ; // 355 (Bitplane Priority)
  enable[8] <= (rga[8:6] == 3'b110      )  1'b1 : 1'b0 ; // 359 COLORxx
  enable[9] <= (rgb[8:1] == 3'b00000101 )  1'b1 : 1'b0 ; // 361 JOYxDAT (00A, 00C, 036)
end

endmodule
