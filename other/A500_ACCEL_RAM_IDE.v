`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Create Date:    21:28:36 11/05/2017 
// Design Name:    Amiga 500 in socket 68000 Accelerator, FastRAM and IDE Interface	 
// Module Name:    A500_ACCEL_RAM_IDE 
//
// Designer Name:  Paul Raspa
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

module A500_ACCEL_RAM_IDE(
    // Control Inputs
    
    /* Currently disabled to keep it simple -----  
    input [1:0] MEMORY_SIZE,
    ----- */

    input RESET,
    input CLK,
    input RW,
    input AS,
    input UDS,
    input LDS,
    
    // Address Inputs
    input [7:0] ADDRESS_LOW,
    input [23:16] ADDRESS_HIGH,
    
    // Data Inputs / Outputs
    inout [15:12] DATA,
    
    // RAM Control Outputs
    output CE_LOW, CE_HIGH,
    output OE_LOW, OE_HIGH,
    output WE_LOW, WE_HIGH
    );

reg readCycle = 1'b0;
reg writeCycle = 1'b0;
reg configured = 1'b0;
reg shutup = 1'b0;
reg [3:0] autoConfigData = 4'b0000;
reg [7:0] autoConfigBase = 8'b00000000;

// Hard coded declerations. Thanks Stephen J. Leary for this nice logic for determining the AUTOCONFIG_RANGE and RAM_ACCESS logic.
wire AUTOCONFIG_RANGE = ~({ADDRESS_HIGH[23:16]} != {8'hE8}) | AS | shutup | configured;
wire RAM_ACCESS = ~({ADDRESS_HIGH[23:16]} != {autoConfigBase[7:0]}) | AS | ~configured;

// Detect if current cycle is READ or WRITE.
always @(posedge CLK, posedge AS) begin
    if (AS == 1'b1) begin
        // Rising edge of /AS indicates end of current cycle. Use this to clear flags
        readCycle  <= 1'b0;
        writeCycle <= 1'b0;
    end else begin
        if (AS == 1'b0) begin
            // Falling edge of /AS indicates end of S2 of current cycle. Use this to determine READ or WRITE
            if (RW == 0)
                readCycle <= 1'b1;
            else
                writeCycle <= 1'b1;
        end
    end
end

// Enable (or disable) AUTOCONFIG cycle.
always @(posedge writeCycle, negedge RESET) begin
    if (RESET == 1'b0) begin
        configured <= 1'b0;
        shutup <= 1'b0;
    end else begin
        if (AUTOCONFIG_RANGE == 1'b1) begin
            // AutoConfig Write sequence. Here is where we receive from the OS the base address for the RAM.
            case (ADDRESS_LOW)
                8'b01001000: // $48
                    autoConfigBase[7:4] <= DATA[15:12];
                8'b01001010: // $4A
                    autoConfigBase[3:0] <= DATA[15:12];
                8'b01001100: begin // $4C                
                    shutup <= 1'b1;
                    configured <= 1'b1;
                end
                8'b01001110: begin // $4E                                
                    shutup <= 1'b1;
                    configured <= 1'b1;
                end
                default: begin
                    shutup <= 1'b1;
                    configured <= 1'b1;
                end
            endcase
        end
    end
end

// Evaluate autoConfigData data based on user-selectable memory configuration
always @(posedge readCycle) begin
    if (AUTOCONFIG_RANGE == 1'b1) begin
        // AutoConfig Read sequence. Here is where we publish the RAM Size and Hardware attributes.
        case (ADDRESS_LOW)
            8'b00000000: // $00
                autoConfigData <= 4'b1110;
            8'b00000001: // $02
                // 1 MB Configuration
                autoConfigData <= 4'b0101;

                /* Currently disabled to keep it simple -----                
                
                if (MEMORY_SIZE == 2'b00)
                    // 1 MB Configuration
                    autoConfigData <= 4'b0101;
                else if (MEMORY_SIZE == 2'b01)
                    // 2 MB Configuration
                    autoConfigData <= 4'b0110;
                else if (MEMORY_SIZE == 2'b10)
                    // 4 MB Configuration
                    autoConfigData <= 4'b0111;
                else if (MEMORY_SIZE == 2'b11)
                    // 8 MB Configuration
                    autoConfigData <= 4'b0000;
                else
                    autoConfigData <= 4'b0101;
                    
                ----- */
            
            8'b00000010: // $04
                autoConfigData <= 4'h0;
            8'b00000011: // $06
                autoConfigData <= 4'h0;
            
            8'b00000100: // $08
                autoConfigData <= 4'h0;
            8'b00000101: // $0A
                autoConfigData <= 4'h0;

            8'b00001000: // $10
                autoConfigData <= 4'h0;
            8'b00001001: // $12
                autoConfigData <= 4'h0;
            
            8'b00001010: // $14
                autoConfigData <= 4'h0;
            8'b00001011: // $16
                autoConfigData <= 4'h0;

            8'b00100000: // $40
                autoConfigData <= 4'b0000;
            8'b00100001: // $42
                autoConfigData <= 4'b0000;    
        
            default:
                autoConfigData <= 4'b1111;
        endcase
    end
end

// Output specific AUTOCONFIG data.
assign DATA = (readCycle == 1'b1 && AUTOCONFIG_RANGE == 1'b1 && configured == 1'b0) ? 4'bZZZZ : autoConfigData;

// RAM Control arbitration.
assign CE_LOW = ~(RAM_ACCESS & (readCycle == 1'b1 | writeCycle == 1'b1) & ~LDS);
assign CE_HIGH = ~(RAM_ACCESS & (readCycle == 1'b1 | writeCycle == 1'b1) & ~UDS);
assign OE_LOW = ~(RAM_ACCESS & (readCycle == 1'b1) & ~LDS);
assign OE_HIGH = ~(RAM_ACCESS & (readCycle == 1'b1) & ~UDS);
assign WE_LOW = ~(RAM_ACCESS & (writeCycle == 1'b1) & ~LDS);
assign WE_HIGH = ~(RAM_ACCESS & (writeCycle == 1'b1) & ~UDS);

endmodule
