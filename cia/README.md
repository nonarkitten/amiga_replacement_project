# CIA 8520 implementation

Original Verilog implementation was done by Niklas Ekström (https://github.com/niklasekstrom/cia-verilog).
Cross checked with the CIA dissection (http://forum.6502.org/viewtopic.php?f=4&t=7368)
This implementation playground is available at (https://www.edaplayground.com/x/aYYC)

It has been reimplemented to offer the following features:
- separate modules to split core logic from I/O buffering (tri-state handling).
- dual-edge sensitive design (the CIA internally generates two non-overlapping clock phases).
- optional extensions (disabled by default, enabled via spare register to preserve compatibility).

The implementation is split across several modules to improve readability, verification, and maintainability. Further work will make the design more FPGA-friendly (e.g. use of a single internal FPGA clock with clock-enable signals instead of relying directly on phi2).

The following modules are available:
- [cia_top.v](cia_top.v) : CIA 8520 wrapper. This module is the verilog representation of the real chip pins including tri-state ones. It still requires external pull-ups (or equivalent FPGA I/O constraints).
- [cia8520.v](cia8520.v) : CIA Implementation top module. It is responsible for visible register reads and writes as well as CNT/SP synchronization. 
- [cia_decoder.v](cia_decoder.v) : Purely combinational address decoder. Selects the target register and routes enables to the appropriate submodule.
- [cia_handshake.v](cia_handshake.v) : Implements flag interrupt pulse and PC pulse following PRB
- [cia_interrupts.v](cia_interrupts.v) : Retrieve interrupts from submodules and generate interrupt register value 
- [cia_serial.v](cia_serial.v) : Perform serial transfers. synchronization of CNT/SP is handled by CIA top module (not the wrapper). In input the data is made available and is transferred by the top module to the SDR register. In output, the top module signals the serial module that new data is available to be transferred. This module differs in implementation with the real CIA (real CIA uses counter for bits in/out, this version uses a stop bit in the shift register).
- [cia_timer.v](cia_timer.v) : Timer implementation. The top module handle additional timer mechanics (autostart/autoload when writing TAHI, forceload strobe, etc...) as well as latch register
- [cia_tod.v](cia_tod.v) : TOD latch implementation. Top module is responsible to maintain TOD counter and ALRM. This submodule only handles strobe and ALRM comparison.

A test bench is provided to validate most of the features.
