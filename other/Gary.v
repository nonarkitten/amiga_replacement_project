`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    20:24:47 10/29/2015 
// Design Name: 
// Module Name:    Gary 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module Gary(
    output nVPA,
    output nCDR,
    output nCDW,
    input nKRES,
    input nMTR,
    input nDKWD,
    input nDKWE,
    input nUDS,
    input nLDS,
    input RW,
    input nAS,
    input nBGACK,
    input nDBR,
    input nSEL0,
    output nRGAE,
    output nBLS,
    output nRAME,
    output nROME,
    output nRTCR,
    output nRTCW,
    output reg nLATCH,
    input nCDAC,
    input C3,
    input C1,
    input nOVR,
	 input OVL,
    input XRDY,
    input nEXP,
    input [23:17] A,
    inout nRESET,
    output nHALT,
    output nDTACK,
    output DKWEB,
    output DKWDB,
    output MTR0D,
    output MTRXD
    );
	 
	//internal registers
	reg AS_14D0,nDBR_D0;
	reg nDTACK_S, nCDR_S, nCDW_S,nBLS_S, MTR0_S;	
	reg [7:0]counter;
	//generate processor clock
	wire C7M = C3 ~^ C1; // c1 not xor c2 = 7mhz
	wire C14M = C7M ^ ~nCDAC; //14MHZ
	wire DS = ~nUDS | ~nLDS;

	wire chipram 	= (~OVL & A[23:21]==3'b000 
									//| A[23:19]>5'b00001
								);
	wire rom			= (	( OVL & A[23:21]==3'b000 ) //rom overlay during start
									| A[23:19]==5'b11111 	//F80000-FFFFFF
									| A[23:19]==5'b11100 );	//E00000-E7FFFF
	wire clock		= A[23:17]==7'b1101110;				//clock: D80000-DB0000
	wire cia			= A[23:21]==3'b101;					//cia: A00000-BFFFFF
	wire chipset	= (nEXP &								//expansion selected
								(A[23:20]==4'b1100			//C00000-CFFFFF
								|A[23:19]==5'b11010))|		//D00000-D7FFFF
								A[23:18]==6'b110111;			//chipset
	wire ranger		= ~nEXP &								//expansion selected
								(A[23:20]==4'b1100			//C00000-CFFFFF
								|A[23:19]==5'b11010)			//D00000-D7FFFF
								;
	//all others a bit later with AS_14D0
	wire other		=~chipram & ~rom & ~clock & ~ chipset & ~ranger & ~cia & ~AS_14D0;
	//reset generation
	assign nHALT = ~nKRES ? 0 : 1'bz;	
	assign nRESET = ~nKRES ? 0 : 1'bz;
		
	//assign simple signals
	assign DKWDB = ~nDKWD;
	assign DKWEB = nDKWE  & nRESET;
	assign MTRXD = ~nMTR  & nRESET;
	assign MTR0D = MTR0_S ;
	//select floppy motor
	always @(negedge nSEL0 ,negedge  nRESET)
	begin
		if( nRESET==0)
		begin
			MTR0_S <= 0;
		end
		else
		begin
			MTR0_S <= ~nMTR;
		end
	end
	
	//decode address and generate the internal signals
	always @(posedge C14M)
	begin
		//this replaces the nasty latch!
		nLATCH	<=	C3;
		AS_14D0	<= nAS;
		nDBR_D0	<= nDBR;
		if(nAS)
		begin
			nDTACK_S	<=1;
			nCDR_S	<=1;
			nCDW_S	<=1;
			nBLS_S	<=1;
			counter	<=8'h00;
		end
		else
		begin
		
			//count 7Mhz-flanks: odd falling even rising
			counter <=counter+1; // the cycle starts at S3: this time the first cycle is seen!
			
			if( 
				((~nDBR | ~nDBR_D0) &( //blitting
					chipram | chipset | ranger //Agnus	
					)					
				)					
				| cia //cia access
				& nDTACK_S //not asserted
				
				)
			begin
				nDTACK_S <= 1;
			end
			else 
			begin
				nDTACK_S <= ~XRDY; //ready to rambo					
			end
			
						
			//slow down blitter
			nBLS_S 	<= ~((	chipram | ranger | chipset) & (counter[1:0]>=2'b00 & counter[1:0]<=2'b01));

			//read from RAM / register	
			if(	counter>=8'h01 //minimum wait					
					& RW //read
					& nDBR_D0 & nDBR //no blitting
					& (chipset | chipram | ranger) //agnus-select
					& nCDR_S //not asseted
					)
			begin
				nCDR_S	<= 0;
			end
			
			//write to RAM / register
			if(	~RW //write
					& nDBR_D0 & nDBR //no blitting
					& (chipset | chipram | ranger) //agnus-select
					& nCDW_S //not asseted
					)
			begin
				nCDW_S	<= 0;
			end
			

		end
	end
	
	always @(posedge C14M)
	begin
	end
		
	//output signal generation
	assign nVPA = nOVR & ~nAS ? ~cia : 1'bz;
	assign nDTACK = (nOVR & ~nAS ) ? nDTACK_S : 1'bz;
	assign nROME = nOVR & ~nAS ? ~(rom & RW) : 1; //only on read!
	assign nRTCR = nOVR & ~nAS ? ~(clock &  RW &  DS) : 1;
	assign nRTCW = nOVR & ~nAS ? ~(clock & ~RW &  DS) : 1;
	assign nRAME = nOVR & ~nAS ? ~(chipram | ranger ) : 1;
	assign nCDR  = nOVR & ~nAS ? nCDR_S : 1;
	assign nCDW  = nOVR & ~nAS ? nCDW_S : 1;
	assign nRGAE = nOVR & ~nAS ? ~chipset : 1;
	assign nBLS	 = nOVR & ~nAS ? nBLS_S : 1;
	


endmodule
