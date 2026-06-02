PROJECT := rpga_companion_core
TOP := rpga_companion_core
DEVICE ?= u4k
PACKAGE ?= sg48
FREQ ?= 16
KALMAN_COVARIANCE ?= 0
PCF := common/io.pcf
RTL := rtl/ram.v rtl/dsp_mac16.v rtl/tiny_cpu.v rtl/rpga_companion_core.v
DEFINES :=
BUILD_SUFFIX :=

ifeq ($(KALMAN_COVARIANCE),1)
DEFINES += -D RPGA_KALMAN_COVARIANCE
BUILD_SUFFIX := _cov
endif

BUILD ?= build$(BUILD_SUFFIX)

.PHONY: all clean prog sim timing

all: $(BUILD)/$(PROJECT).bin

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/$(PROJECT).json: $(RTL) | $(BUILD)
	yosys $(DEFINES) -p "synth_ice40 -dsp -abc2 -top $(TOP) -json $@" $(RTL)

$(BUILD)/$(PROJECT).asc: $(BUILD)/$(PROJECT).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --json $(BUILD)/$(PROJECT).json --pcf $(PCF) --asc $@

$(BUILD)/$(PROJECT).bin: $(BUILD)/$(PROJECT).asc
	icepack $< $@

timing: $(BUILD)/$(PROJECT).asc
	icetime -d $(DEVICE) -c $(FREQ) -mtr $(BUILD)/$(PROJECT).rpt $<

sim:
	$(MAKE) -C tests KALMAN_COVARIANCE=$(KALMAN_COVARIANCE)

prog: $(BUILD)/$(PROJECT).bin
	iceprog $<

clean:
	rm -rf build build_cov
