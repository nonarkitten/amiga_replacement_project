# Denise
Denise is the display chip of the Amiga. It is known to be stateless and does not require reset. There are three main variations of Denise; OCS Denise, ECS Denise and in the AGA era was expanded to 32-bit and renamed Lisa.

## Denise OCS
This will be a drop-in replacement for Amiga 1000 and early Amiga 500 and 2000 machines. This must support
- clocking from 7M and CCK only, ideally avoiding PLL
- quadrature decoding of both mouse inputs (MxH/MxV)
- 32-colour look up table with dual port memory (CLUT)
- planar bit plane and sprite output with dual-playfield
- genlocking using the transparency bit in the CLUT
- generation of proper NTSC and PAL outputs
- hold-and-modify and extra-half-bright modes

### Advanced Denise OCS
This will retain the strict mode compatibility of Denise OCS but add scan doubling, permitting the simple connection to more modern displays with a pasive Amiga to SVGA adapter. 
- scan doubling of 240P modes
- bob deinterlaing of 480i modes
- optional 'scan line' effect

## Denise ECS
While Amiga uses will claim ECS is nothing more than OCS, it adds proper VGA productivity modes with super-hires and opened the door for the sprite doubling trick. To create these modes, the chip gained an extra single, CDAC, which can be XORed with the 7M clock to provide a 14M clock and 28M event. Some support for known bugs include:
- playfield inversion bug
- 7 bit plane bug

### Advanced Denise ECS
This will retain all expected function of the ECS chipset, plus:
- the scan doubling Advanced Denise OCS had
- pass through of real productivity modes
- no reduction in colour accuracy in ECS productivity modes

## Lisa (32-bit Denise AGA)
AGA is broadly divided into two new hardware features; new memory access (double cas and 32-bit width) which results in improved throughput as well as the collection of new modes, colours and bit depths.

While many of the modes depend on the improvement in bandwidth, not all of them do -- 256 colours and 8-bit lowres was possible on ECS. Further, some enhancements to ECS productivity modes also do no depend on more throughput unless the mode exceeds the capacity of ECS.

### AGA Bandwidth
There are two steps that could open up better bandwidth and require that Agnus have it's own RAM.
1. use FP/EDO DRAM; this allows double-CAS mode that is 1/2 way to full AGA; I do not expect this to fail -- it might be better to jump the shark here though and use SDRAM which would open up more opportunities later; note that SDRAM is the highest tech level we can use before voltage differences become a big problem
2. use faster data bus; this requires 70ns memory to reach full AGA speed; however, quad data rate on the data bus might not be possible with the parasitic capacitance of 1980's level tech; if this works, it would be the simplest solution to hit AGA speeds on ECS motherboards
3. split the data bus from DRAM and use lower voltages and/or differential signalling between the chips; this of course adds latency AND greatly complicates the data bus handling but may be required if the hardware doesn't like QDR.

### Advanced Lisa
Additionally, the improvements from the Vampire AGA may be added.
- multicolor sprites allowing four 8-pixel bit planes instead for two 16-pixel bit planes
- sprite-repeat mode that allows a single sprite to occupy the entire scan line
- sprite-flip mode that horizontally flips the sprite image

