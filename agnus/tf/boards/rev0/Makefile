RTLFOLDER=../../rtl/
PROGRAMMER=pi@192.168.1.158

all: synth pnr binary
synth: reagnus.blif
pnr: synth reagnus.txt
binary: pnr reagnus.bin
upload: binary
	scp reagnus.bin $(PROGRAMMER):/tmp/
identify:
	ssh $(PROGRAMMER) "fomu-flash -i"
flash: upload identify
	ssh $(PROGRAMMER) "fomu-flash -u -w /tmp/reagnus.bin"
	ssh $(PROGRAMMER) "fomu-flash -u -f /tmp/reagnus.bin"
	ssh $(PROGRAMMER) "fomu-flash -r"
reagnus.blif: $(RTLFOLDER)/reagnus.v
	yosys -p 'synth_ice40 -top reagnus -blif reagnus.blif' $(RTLFOLDER)/reagnus.v
reagnus.txt:
	arachne-pnr -d 8k --package tq144:4k  -o reagnus.txt -p reagnus.pcf reagnus.blif
reagnus.bin: 
	icepack reagnus.txt reagnus.bin
clean:
	rm -rf *.blif reagnus.txt *.bin
