TOPLEVEL_LANG ?= verilog
SIM ?= icarus

TOPLEVEL := rpga_companion_core
MODULE := test_rpga_companion
KALMAN_COVARIANCE ?= 0
export KALMAN_COVARIANCE

ifeq ($(KALMAN_COVARIANCE),1)
COMPILE_ARGS += -D RPGA_KALMAN_COVARIANCE
endif

ROOT := $(abspath ..)
VERILOG_SOURCES += $(ROOT)/sim/ice40_cells_sim.v
VERILOG_SOURCES += $(ROOT)/rtl/ram.v
VERILOG_SOURCES += $(ROOT)/rtl/dsp_mac16.v
VERILOG_SOURCES += $(ROOT)/rtl/tiny_cpu.v
VERILOG_SOURCES += $(ROOT)/rtl/rpga_companion_core.v

include $(shell cocotb-config --makefiles)/Makefile.sim
