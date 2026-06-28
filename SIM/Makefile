SHELL   := /bin/bash
RTL     := ../RTL
IV      := iverilog -g2012 -Wall
VVP     := vvp
GCC     := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
CFLAGS  := -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T link_default.ld

# ───────── RTL source lists ─────────
RTL_INFRA = $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv $(RTL)/irq_sync2ff.sv
RTL_MEM   = $(RTL)/imem.sv $(RTL)/dmem.sv

RTL_CPU   = $(RTL)/branch_predictor.sv \
            $(RTL)/if1_stage.sv $(RTL)/if1_if2_reg.sv \
            $(RTL)/if2_stage.sv $(RTL)/if2_id_reg.sv \
            $(RTL)/id_decoder.sv $(RTL)/register_file.sv $(RTL)/id_ex_reg.sv \
            $(RTL)/alu.sv $(RTL)/branch_comp.sv $(RTL)/addr_adder.sv \
            $(RTL)/forwarding_unit.sv $(RTL)/ex_stage.sv \
            $(RTL)/ex_mem1_reg.sv $(RTL)/mem1_stage.sv \
            $(RTL)/mem1_mem2_reg.sv $(RTL)/mem2_stage.sv \
            $(RTL)/mem2_wb_reg.sv $(RTL)/wb_stage.sv \
            $(RTL)/hazard_unit.sv $(RTL)/zicsr.sv

RTL_AXI   = $(RTL)/axi_interface.sv $(RTL)/axi_interconnect.sv $(RTL)/axi_sfr.sv $(RTL)/gpio_sfr.sv
RTL_AHB   = $(RTL)/ahb_interface.sv $(RTL)/ahb_interconnect.sv $(RTL)/ahb_sfr.sv
# Real peripheral modules (outside soc_top, plugged in testbench)
RTL_PERIPH = $(RTL)/timer_axi.sv $(RTL)/gpio_ahb.sv $(RTL)/uart_axi.sv

RTL_PLIC  = $(RTL)/plic.sv
RTL_ALL   = $(RTL_INFRA) $(RTL_MEM) $(RTL_CPU) $(RTL_PLIC) $(RTL_AXI) $(RTL_AHB) $(RTL)/soc_top.sv

# ───────── Unit Tests ─────────
.PHONY: unit_alu unit_branch unit_decoder unit_rf unit_fwd unit_haz unit_fifo unit_plic unit_ex unit_all
.PHONY: unit_irq_sync unit_gpio unit_zicsr unit_bp unit_timer unit_gpio_ahb unit_uart

unit_alu:
	@echo "=== tb_alu ==="
	$(IV) -o unit/tb_alu.vvp unit/tb_alu.sv $(RTL)/alu.sv
	$(VVP) unit/tb_alu.vvp

unit_branch:
	@echo "=== tb_branch_comp ==="
	$(IV) -o unit/tb_branch_comp.vvp unit/tb_branch_comp.sv $(RTL)/branch_comp.sv
	$(VVP) unit/tb_branch_comp.vvp

unit_decoder:
	@echo "=== tb_id_decoder ==="
	$(IV) -o unit/tb_id_decoder.vvp unit/tb_id_decoder.sv $(RTL)/id_decoder.sv
	$(VVP) unit/tb_id_decoder.vvp

unit_rf:
	@echo "=== tb_register_file ==="
	$(IV) -o unit/tb_register_file.vvp unit/tb_register_file.sv $(RTL)/register_file.sv
	$(VVP) unit/tb_register_file.vvp

unit_fwd:
	@echo "=== tb_forwarding_unit ==="
	$(IV) -o unit/tb_forwarding_unit.vvp unit/tb_forwarding_unit.sv $(RTL)/forwarding_unit.sv
	$(VVP) unit/tb_forwarding_unit.vvp

unit_haz:
	@echo "=== tb_hazard_unit ==="
	$(IV) -o unit/tb_hazard_unit.vvp unit/tb_hazard_unit.sv $(RTL)/hazard_unit.sv
	$(VVP) unit/tb_hazard_unit.vvp

unit_fifo:
	@echo "=== tb_async_fifo ==="
	$(IV) -o unit/tb_async_fifo.vvp unit/tb_async_fifo.sv $(RTL)/async_fifo.sv
	$(VVP) unit/tb_async_fifo.vvp

unit_plic:
	@echo "=== tb_plic ==="
	$(IV) -o unit/tb_plic.vvp unit/tb_plic.sv $(RTL)/plic.sv
	$(VVP) unit/tb_plic.vvp

unit_ex:
	@echo "=== tb_ex_stage ==="
	$(IV) -o unit/tb_ex_stage.vvp unit/tb_ex_stage.sv \
	    $(RTL)/ex_stage.sv $(RTL)/forwarding_unit.sv \
	    $(RTL)/alu.sv $(RTL)/branch_comp.sv $(RTL)/addr_adder.sv
	$(VVP) unit/tb_ex_stage.vvp

unit_irq_sync:
	@echo "=== tb_irq_sync2ff ==="
	$(IV) -o unit/tb_irq_sync2ff.vvp unit/tb_irq_sync2ff.sv $(RTL)/irq_sync2ff.sv
	$(VVP) unit/tb_irq_sync2ff.vvp

unit_gpio:
	@echo "=== tb_gpio_sfr ==="
	$(IV) -o unit/tb_gpio_sfr.vvp unit/tb_gpio_sfr.sv \
	    $(RTL)/gpio_sfr.sv $(RTL)/axi_sfr.sv
	$(VVP) unit/tb_gpio_sfr.vvp

unit_zicsr:
	@echo "=== tb_zicsr ==="
	$(IV) -o unit/tb_zicsr.vvp unit/tb_zicsr.sv $(RTL)/zicsr.sv
	$(VVP) unit/tb_zicsr.vvp

unit_bp:
	@echo "=== tb_branch_predictor ==="
	$(IV) -o unit/tb_branch_predictor.vvp unit/tb_branch_predictor.sv \
	    $(RTL)/branch_predictor.sv
	$(VVP) unit/tb_branch_predictor.vvp

unit_timer:
	@echo "=== tb_timer_axi ==="
	$(IV) -o unit/tb_timer_axi.vvp unit/tb_timer_axi.sv $(RTL)/timer_axi.sv
	$(VVP) unit/tb_timer_axi.vvp

unit_gpio_ahb:
	@echo "=== tb_gpio_ahb ==="
	$(IV) -o unit/tb_gpio_ahb.vvp unit/tb_gpio_ahb.sv $(RTL)/gpio_ahb.sv
	$(VVP) unit/tb_gpio_ahb.vvp

unit_uart:
	@echo "=== tb_uart_axi ==="
	$(IV) -o unit/tb_uart_axi.vvp unit/tb_uart_axi.sv $(RTL)/uart_axi.sv
	$(VVP) unit/tb_uart_axi.vvp

unit_periph: unit_timer unit_gpio_ahb unit_uart

unit_all: unit_alu unit_branch unit_decoder unit_rf unit_fwd unit_haz unit_fifo unit_plic unit_ex \
          unit_irq_sync unit_gpio unit_zicsr unit_bp unit_timer unit_gpio_ahb unit_uart

# ───────── Integration Tests ─────────
.PHONY: integ_cpu integ_axi integ_ahb integ_all
.PHONY: p3_arithmetic p3_forwarding p3_load_store p3_branch_jump p3_csr p3_all

# Compile integration testbench once (depends on all RTL)
integration/tb_pipeline_cpu.vvp: integration/tb_pipeline_cpu.sv $(RTL_ALL)
	@echo "=== Compiling tb_pipeline_cpu ==="
	$(IV) -o $@ integration/tb_pipeline_cpu.sv $(RTL_ALL)

# Generic run (requires HEX=<path>)
integ_cpu: integration/tb_pipeline_cpu.vvp
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=$(HEX)

# Phase 3 programs
p3_arithmetic: programs/prog_arithmetic.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_arithmetic ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_arithmetic.hex

p3_forwarding: programs/prog_forwarding.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_forwarding ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_forwarding.hex

p3_load_store: programs/prog_load_store.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_load_store ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_load_store.hex

p3_branch_jump: programs/prog_branch_jump.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_branch_jump ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_branch_jump.hex

p3_csr: programs/prog_csr.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_csr ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_csr.hex

p3_ecall: programs/prog_ecall.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_ecall ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_ecall.hex

p3_msi: programs/prog_interrupt_msi.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_interrupt_msi ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_interrupt_msi.hex

p3_mei: programs/prog_interrupt_mei.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_interrupt_mei ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_interrupt_mei.hex

p3_load_fault: programs/prog_load_fault.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_load_fault ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_load_fault.hex

p3_all: p3_arithmetic p3_forwarding p3_load_store p3_branch_jump p3_csr \
        p3_ecall p3_msi p3_mei p3_load_fault

# Phase 5: Full SoC — AXI/AHB peripheral access + interrupt
.PHONY: p5_axi_sfr p5_ahb_sfr p5_axi_irq p5_ahb_irq p5_all

p5_axi_sfr: programs/prog_axi_sfr.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_axi_sfr ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_axi_sfr.hex

p5_ahb_sfr: programs/prog_ahb_sfr.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_ahb_sfr ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_ahb_sfr.hex

p5_axi_irq: programs/prog_axi_irq.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_axi_irq ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_axi_irq.hex

p5_ahb_irq: programs/prog_ahb_irq.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_ahb_irq ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_ahb_irq.hex

p5_all: p5_axi_sfr p5_ahb_sfr p5_axi_irq p5_ahb_irq

# Phase 0: Branch prediction correctness test
.PHONY: p0_branch_pred
p0_branch_pred: programs/prog_branch_pred.hex integration/tb_pipeline_cpu.vvp
	@echo "=== prog_branch_pred (branch prediction) ==="
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_branch_pred.hex

# Waveform shortcut: make p3_wave_<prog> PROG=<name>
p3_wave_%: programs/prog_%.hex integration/tb_pipeline_cpu.vvp
	$(VVP) integration/tb_pipeline_cpu.vvp +HEX=programs/prog_$*.hex \
	    +DUMP=integration/wave_$*.vcd

integ_axi:
	@echo "=== tb_axi_interface ==="
	$(IV) -o integration/tb_axi_interface.vvp \
	    integration/tb_axi_interface.sv models/axi_slave_model.sv \
	    $(RTL)/axi_interface.sv
	$(VVP) integration/tb_axi_interface.vvp

integ_ahb:
	@echo "=== tb_ahb_interface ==="
	$(IV) -o integration/tb_ahb_interface.vvp \
	    integration/tb_ahb_interface.sv models/ahb_slave_model.sv \
	    $(RTL)/ahb_interface.sv $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv
	$(VVP) integration/tb_ahb_interface.vvp

integ_axi_full:
	@echo "=== tb_axi_full (interface + interconnect + 3 SFRs) ==="
	$(IV) -o integration/tb_axi_full.vvp \
	    integration/tb_axi_full.sv \
	    $(RTL)/axi_interface.sv $(RTL)/axi_interconnect.sv $(RTL)/axi_sfr.sv
	$(VVP) integration/tb_axi_full.vvp

integ_ahb_full:
	@echo "=== tb_ahb_full (interface via CDC + interconnect + 3 SFRs) ==="
	$(IV) -o integration/tb_ahb_full.vvp \
	    integration/tb_ahb_full.sv \
	    $(RTL)/ahb_interface.sv $(RTL)/ahb_interconnect.sv $(RTL)/ahb_sfr.sv \
	    $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv
	$(VVP) integration/tb_ahb_full.vvp

integ_bus_err:
	@echo "=== tb_soc_bus_err (AXI bus error: BRESP/RRESP → store/load access fault) ==="
	$(IV) -o integration/tb_soc_bus_err.vvp integration/tb_soc_bus_err.sv $(RTL_ALL)
	$(VVP) integration/tb_soc_bus_err.vvp +HEX=programs/prog_bus_err.hex
	$(VVP) integration/tb_soc_bus_err.vvp +HEX=programs/prog_read_err.hex

integ_ahb_err:
	@echo "=== tb_soc_ahb_err (AHB bus error: HRESP → store/load access fault) ==="
	$(IV) -o integration/tb_soc_ahb_err.vvp integration/tb_soc_ahb_err.sv $(RTL_ALL)
	$(VVP) integration/tb_soc_ahb_err.vvp +HEX=programs/prog_ahb_store_err.hex
	$(VVP) integration/tb_soc_ahb_err.vvp +HEX=programs/prog_ahb_load_err.hex

integ_all: integ_cpu integ_axi integ_ahb integ_axi_full integ_ahb_full integ_bus_err integ_ahb_err

# ───────── System Tests (Phase 6) ─────────
.PHONY: system compliance_compile compliance p6_compliance p6_all rv32i_compliance

P6_PROGS = programs/prog_rv32i_shifts.hex programs/prog_rv32i_compare.hex \
           programs/prog_dmem_endurance.hex

P7_PROGS = programs/prog_plic_basic.hex programs/prog_plic_priority.hex \
           programs/prog_plic_threshold.hex

P8_PROGS = programs/prog_csr_hazard.hex

SYSTEM_PROGS = programs/prog_arithmetic.hex programs/prog_forwarding.hex \
               programs/prog_load_store.hex programs/prog_branch_jump.hex \
               programs/prog_csr.hex programs/prog_ecall.hex \
               programs/prog_interrupt_msi.hex programs/prog_interrupt_mei.hex \
               programs/prog_load_fault.hex \
               programs/prog_axi_sfr.hex programs/prog_ahb_sfr.hex \
               programs/prog_axi_irq.hex programs/prog_ahb_irq.hex \
               $(P6_PROGS) $(P7_PROGS) $(P8_PROGS)

# Phase 6a / 7: system batch test (all 20 programs)
system/tb_soc_top.vvp: system/tb_soc_top.sv $(RTL_ALL)
	@echo "=== Compiling tb_soc_top ==="
	$(IV) -o $@ system/tb_soc_top.sv $(RTL_ALL)

system: system/tb_soc_top.vvp $(SYSTEM_PROGS)
	@echo "=== System Batch Test (20 programs) ==="
	$(VVP) system/tb_soc_top.vvp

# Phase 6b: compliance testbench
system/tb_compliance.vvp: system/tb_compliance.sv $(RTL_ALL)
	@echo "=== Compiling tb_compliance ==="
	$(IV) -o $@ system/tb_compliance.sv $(RTL_ALL)

compliance_compile: system/tb_compliance.vvp

# Run a single ELF through compliance framework
compliance: compliance_compile
	bash scripts/run_one_test.sh $(ELF)

# Phase 6b: run compliance programs through tb_compliance
p6_compliance: system/tb_compliance.vvp $(P6_PROGS)
	@echo "=== prog_rv32i_shifts ==="
	$(VVP) system/tb_compliance.vvp +HEX=programs/prog_rv32i_shifts.hex
	@echo "=== prog_rv32i_compare ==="
	$(VVP) system/tb_compliance.vvp +HEX=programs/prog_rv32i_compare.hex
	@echo "=== prog_dmem_endurance ==="
	$(VVP) system/tb_compliance.vvp +HEX=programs/prog_dmem_endurance.hex

p6_all: system p6_compliance

# ───────── Metrics (IPC + stall breakdown + branch hit rate + AHB latency) ─────────
.PHONY: metrics

METRICS_PROGS = programs/prog_forwarding.hex programs/prog_branch_pred.hex \
                programs/prog_ahb_sfr.hex programs/prog_fib.hex

system/tb_metrics.vvp: system/tb_metrics.sv $(RTL_ALL)
	@echo "=== Compiling tb_metrics ==="
	$(IV) -o $@ system/tb_metrics.sv $(RTL_ALL)

metrics: system/tb_metrics.vvp $(METRICS_PROGS)
	@echo "=== Pipeline Metrics (IPC / Stall / Branch Predictor / AHB Latency) ==="
	$(VVP) system/tb_metrics.vvp

# ───────── Task 1: Real Peripherals (Timer AXI + GPIO AHB) ─────────
.PHONY: periph_timer periph_gpio periph_uart periph_all

system/tb_periph.vvp: system/tb_periph.sv $(RTL_ALL) $(RTL_PERIPH)
	@echo "=== Compiling tb_periph ==="
	$(IV) -o $@ system/tb_periph.sv $(RTL_ALL) $(RTL_PERIPH)

periph_timer: programs/prog_timer.hex system/tb_periph.vvp
	@echo "=== prog_timer (Timer AXI compare-match IRQ) ==="
	$(VVP) system/tb_periph.vvp +HEX=programs/prog_timer.hex

periph_gpio: programs/prog_gpio_ahb.hex system/tb_periph.vvp
	@echo "=== prog_gpio_ahb (GPIO AHB loopback + IRQ) ==="
	$(VVP) system/tb_periph.vvp +HEX=programs/prog_gpio_ahb.hex

periph_uart: programs/prog_uart.hex system/tb_periph.vvp
	@echo "=== prog_uart (UART AXI TX/RX loopback + IRQ) ==="
	$(VVP) system/tb_periph.vvp +HEX=programs/prog_uart.hex

periph_all: periph_timer periph_gpio periph_uart

# ───────── D2/D3: Misaligned Exception + MTIP path ─────────
.PHONY: integ_misaligned integ_mtip integ_d2_d3

integ_misaligned: programs/prog_misaligned.hex system/tb_periph.vvp
	@echo "=== prog_misaligned (D2: misaligned load/store → mcause 4/6) ==="
	$(VVP) system/tb_periph.vvp +HEX=programs/prog_misaligned.hex

integ_mtip: programs/prog_mtip.hex system/tb_periph.vvp
	@echo "=== prog_mtip (D3: MTIP path — mip[7] via timer, mcause=0x80000007) ==="
	$(VVP) system/tb_periph.vvp +HEX=programs/prog_mtip.hex

integ_d2_d3: integ_misaligned integ_mtip
	@echo ""
	@echo "=== D2 + D3: 2/2 PASS ==="

# RV32I Formal Compliance (riscv-arch-test old-framework-2.x)
# Runs 38 tests, reports PASS/SKIP/FAIL
rv32i_compliance:
	@echo "=== RV32I Compliance Tests (riscv-arch-test old-framework-2.x) ==="
	cd $(dir $(abspath $(lastword $(MAKEFILE_LIST)))) && bash compliance/run_compliance.sh

# ───────── Hex Program Build ─────────
programs/%.hex: programs/%.s
	$(GCC) $(CFLAGS) -o programs/$*.elf $<
	$(OBJCOPY) -O verilog --verilog-data-width 4 programs/$*.elf programs/$*.hex
	@echo "Built: programs/$*.hex"

programs/%.dump: programs/%.elf
	$(OBJDUMP) -d -M numeric $< > $@

# ───────── Formal Verification (SymbiYosys) ─────────
SBY := ~/.local/bin/sby
FORMAL_DIR := formal

.PHONY: formal_x0 formal_fifo formal_uart formal_axi formal_plic formal_reg_wbr formal_stall formal_all
.PHONY: formal_alu formal_decoder formal_mem1_addr formal_axi_route formal_ahb_route

formal_x0:
	@echo "=== Formal: register_file x0 always-zero ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_reg_x0.sby

formal_fifo:
	@echo "=== Formal: async_fifo Gray-code + data integrity ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_fifo_gray.sby

formal_uart:
	@echo "=== Formal: uart_axi 8N1 frame boundaries + pulse-width + RX counter ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_uart_proto.sby

formal_axi:
	@echo "=== Formal: axi_interface AXI4-Lite VALID-stability ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_axi_handshake.sby

formal_plic:
	@echo "=== Formal: plic priority encoder correctness ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_plic_priority.sby

formal_reg_wbr:
	@echo "=== Formal: register_file write-before-read bypass ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_reg_wbr.sby

formal_stall:
	@echo "=== Formal: pipeline stall coherence (hazard_unit + IF1/IF2 + IF2/ID + ID/EX regs) ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_stall_coherence.sby

formal_alu:
	@echo "=== Formal: ALU arithmetic/logic correctness (12 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_alu.sby

formal_decoder:
	@echo "=== Formal: id_decoder encoding correctness (8 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_decoder.sby

formal_mem1_addr:
	@echo "=== Formal: mem1_stage address decode + misaligned detection (7 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_mem1_addr.sby

formal_axi_route:
	@echo "=== Formal: AXI interconnect routing mutex + correctness (6 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_axi_route.sby

formal_ahb_route:
	@echo "=== Formal: AHB interconnect routing mutex + correctness (5 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f fv_ahb_route.sby

formal_datapath: formal_alu formal_decoder formal_mem1_addr formal_axi_route formal_ahb_route
	@echo ""
	@echo "=== Formal datapath: 5/5 PROVED ==="

formal_all: formal_x0 formal_fifo formal_uart formal_axi formal_plic formal_reg_wbr formal_stall formal_datapath
	@echo ""
	@echo "=== Formal verification: 12/12 PROVED (7 infra + 5 datapath) ==="

# ───────── Run All ─────────
.PHONY: all clean

all: unit_all
	@echo ""
	@echo "==============================="
	@echo " Unit tests complete"
	@echo "==============================="

clean:
	rm -f unit/*.vvp integration/*.vvp system/*.vvp
	rm -f *.vcd unit/*.vcd integration/*.vcd system/*.vcd
	rm -f programs/*.elf programs/*.hex programs/*.dump
