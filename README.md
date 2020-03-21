# Amiga Replacement Project

_"To make replacements for all the custom chips of the AMIGA, useable in any real AMIGA."_

This is an attempt to make clean Verilog sources for each chip on the Amiga. Unlike MiniMig and related implementations, this seeks to maintain perfect compatibility with the whole chip and the whole chip only to serve as a second-source to the slowly disappearing stock of Amiga chips. These will be drop-in replacements.

To view the plan of record for each chip, please visit the README.md for each project.

Much of the work is based on the excellent efforts of Dennis van Weeren and Frederic Requin (https://github.com/fredrequin).

## OCS
Our OCS goal will include a 512KB Agnus, Denise and Paula supporting basic NTSC and PAL modes. OCS should be drop-in compatible with the Amiga 1000 "skinny" Agnus as well as the early "fat" Agnus on Amiga 500 and 2000 systems. Eventually we will have a DIP 48 solution for this as well.

## ECS
Expands the chip memory to 2MB with two common pin outs that are slightly incompatible with each other. Some bugs need to be supported but the weird limitations of productivity mode do not. The PLCC socketed PCB for Agnus will present a unique engineering challenge; the other chips remain DIP 48.

## AGA-on-ECS
This provides as much AGA functionality on either OCS or ECS based systems and retains the existing pinouts (and 16-bit data bus limitation). It should be possible to implement FP/EDO memory to get 2X increase and it might be possible to extend that to a 4X improvement with faster memory. We may also simply use SDRAM (3.3V SDR) and start with the fastest memory we can to achieve this.

## Vampire AGA
We'may also add to the AGA core some of the added features of the Vampire.
