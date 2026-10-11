# hello_world -- UART greeting for the Nandland Go Board (iCE40HX1K-VQ100)
#
# Build targets follow the sibling projects in ~/git/verilog (syn/pnr/pack/prog)
# but `all` deliberately does NOT program the board -- run `make prog` for that.

top       = hello_world
build_dir = build

rtl       = rtl/hello_world.v rtl/uart_tx.v
tb        = sim/tb_hello_world.v
pcf       = constraints/hello_world.pcf

# Override any of these to point at a different toolchain install.
YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ice40
ICEPACK   ?= icepack
ICEPROG   ?= iceprog
IVERILOG  ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator
SBY       ?= sby
GTKWAVE   ?= gtkwave

# Go Board part and timing target.
device    = hx1k
package   = vq100
freq_mhz  = 25

.PHONY: all clean syn pnr pack prog lint sim wave formal test help

all: pack

syn:  $(build_dir)/$(top).json
pnr:  $(build_dir)/$(top).asc
pack: $(build_dir)/$(top).bin

$(build_dir)/$(top).json: $(rtl) | $(build_dir)
	$(YOSYS) -p "synth_ice40 -top $(top) -json $@; stat" $(rtl)

$(build_dir)/$(top).asc: $(build_dir)/$(top).json $(pcf)
	$(NEXTPNR) --$(device) --freq $(freq_mhz) --package $(package) \
		--pcf $(pcf) --json $< --asc $@ \
		--report $(build_dir)/$(top)_timing.json

$(build_dir)/$(top).bin: $(build_dir)/$(top).asc
	$(ICEPACK) $< $@

prog: $(build_dir)/$(top).bin
	$(ICEPROG) $<

# ---- Verification ----

# PROCASSINIT is waived because declaring a power-on value and also assigning
# it in the reset branch is intentional. The two are not redundant: iCE40
# flip-flops are cleared by the global reset during configuration, so a
# declared initializer never reaches the bitstream -- it seeds simulation, and
# the reset branch is what fixes the power-on state in hardware. Every other
# -Wall warning is treated as an error.
VERILATOR_FLAGS = -Wall -Wno-PROCASSINIT

lint:
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module $(top) $(rtl)

$(build_dir)/$(top).vvp: $(rtl) $(tb) | $(build_dir)
	$(IVERILOG) -g2012 -Wall -s tb_hello_world -o $@ $(rtl) $(tb)

sim: $(build_dir)/$(top).vvp
	$(VVP) $<

$(build_dir)/$(top)_waves.vvp: $(rtl) $(tb) | $(build_dir)
	$(IVERILOG) -g2012 -Wall -DWAVES -s tb_hello_world -o $@ $(rtl) $(tb)

wave: $(build_dir)/$(top)_waves.vvp
	$(VVP) $<
	$(GTKWAVE) $(build_dir)/$(top).vcd

formal:
	$(SBY) -f --prefix $(build_dir)/uart_tx formal/uart_tx.sby

test: lint sim formal

# ---- Housekeeping ----

$(build_dir):
	mkdir -p $(build_dir)

clean:
	-rm -rf $(build_dir)
	-rm -rf formal/uart_tx_bmc* formal/uart_tx_cover*

help:
	@echo "make          build the bitstream (syn + pnr + pack)"
	@echo "make prog     write build/$(top).bin to the board's SPI flash"
	@echo "make sim      run the self-checking testbench (prints the greeting)"
	@echo "make wave     run the testbench with a VCD and open gtkwave"
	@echo "make lint     verilator lint of the RTL"
	@echo "make formal   SymbiYosys bounded proof of the UART transmitter"
	@echo "make test     lint + sim + formal"
	@echo "make clean    remove build products"
