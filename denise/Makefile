PROJ    = denise
FILES   = $(wildcard src/*.v) $(wildcard src/*.sv)
PINMAP  = constraints/denise.pcf
DEVICE  = hx8k
PACKAGE = cb132

all: $(PROJ).bin

stats: $(FILES)
	yosys -p "tee -q hierarchy -top top; tee -q proc; tee -q opt; stat" $(FILES)

%.json: $(FILES)
	yosys -q -p "synth_ice40 -json $@ -top top" $(FILES)

%.asc: %.json $(PINMAP)
	nextpnr-ice40  --freq 57 --$(DEVICE) --package $(PACKAGE) --pcf $(PINMAP) --json $< --asc $@

%.bin: %.asc
	icepack $< $@

prog: $(PROJ).bin
	iceprog -d i:0x0403:0x6011 $<

clean:
	rm -f *.json *.asc *.bin

.PHONY: all prog clean stats
