# CIA 8520 implementation

Full CIA implementation.

Initial work has been done by Niklas Ekström (https://github.com/niklasekstrom/cia-verilog).

It has been reimplemented to offer the following features:
- separate modules to split core logic and the I/O buffering (tri-state).
- dual edge sensitive design (for faster signal syncs).
- additional 'fast pulse' when timer and latch are zero.
- serial port can be faster.

