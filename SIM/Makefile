SHELL   := /bin/bash
RTL     := ../RTL
IV      := iverilog -g2012 -Wall
VVP     := vvp
GCC     := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
OBJDUMP := riscv64-unknown-elf-objdump
CFLAGS  := -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T link_default.ld

# Out-of-tree build output — created once at parse time so -o targets never fail
$(shell mkdir -p build/unit build/integration build/system build/formal build/compliance programs/bin)

# ───────── RTL source lists ─────────
RTL_INFRA = $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv $(RTL)/irq_sync2ff.sv
RTL_MEM   = $(RTL)/imem.sv $(RTL)/dmem.sv

RTL_CPU   = $(RTL)/branch_predictor.sv \
            $(RTL)/if1_stage.sv $(RTL)/if1_if2_reg.sv \
            $(RTL)/if2_stage.sv $(RTL)/if2_id_reg.sv \
            $(RTL)/id_decoder.sv $(RTL)/register_file.sv $(RTL)/id_ex_reg.sv \
            $(RTL)/alu.sv $(RTL)/branch_unit.sv \
            $(RTL)/forwarding_unit.sv \
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
.PHONY: unit_alu unit_branch unit_decoder unit_rf unit_fwd unit_haz unit_fifo unit_plic unit_all
.PHONY: unit_irq_sync unit_gpio unit_zicsr unit_bp unit_timer unit_gpio_ahb unit_uart

unit_alu:
	@echo "=== tb_alu ==="
	$(IV) -o build/unit/tb_alu.vvp unit/tb_alu.sv $(RTL)/alu.sv
	$(VVP) build/unit/tb_alu.vvp

unit_branch:
	@echo "=== tb_branch_comp ==="
	$(IV) -o build/unit/tb_branch_comp.vvp unit/tb_branch_comp.sv $(RTL)/branch_unit.sv
	$(VVP) build/unit/tb_branch_comp.vvp

unit_decoder:
	@echo "=== tb_id_decoder ==="
	$(IV) -o build/unit/tb_id_decoder.vvp unit/tb_id_decoder.sv $(RTL)/id_decoder.sv
	$(VVP) build/unit/tb_id_decoder.vvp

unit_rf:
	@echo "=== tb_register_file ==="
	$(IV) -o build/unit/tb_register_file.vvp unit/tb_register_file.sv $(RTL)/register_file.sv
	$(VVP) build/unit/tb_register_file.vvp

unit_fwd:
	@echo "=== tb_forwarding_unit ==="
	$(IV) -o build/unit/tb_forwarding_unit.vvp unit/tb_forwarding_unit.sv $(RTL)/forwarding_unit.sv
	$(VVP) build/unit/tb_forwarding_unit.vvp

unit_haz:
	@echo "=== tb_hazard_unit ==="
	$(IV) -o build/unit/tb_hazard_unit.vvp unit/tb_hazard_unit.sv $(RTL)/hazard_unit.sv
	$(VVP) build/unit/tb_hazard_unit.vvp

unit_fifo:
	@echo "=== tb_async_fifo ==="
	$(IV) -o build/unit/tb_async_fifo.vvp unit/tb_async_fifo.sv $(RTL)/async_fifo.sv
	$(VVP) build/unit/tb_async_fifo.vvp

unit_plic:
	@echo "=== tb_plic ==="
	$(IV) -o build/unit/tb_plic.vvp unit/tb_plic.sv $(RTL)/plic.sv
	$(VVP) build/unit/tb_plic.vvp

unit_irq_sync:
	@echo "=== tb_irq_sync2ff ==="
	$(IV) -o build/unit/tb_irq_sync2ff.vvp unit/tb_irq_sync2ff.sv $(RTL)/irq_sync2ff.sv
	$(VVP) build/unit/tb_irq_sync2ff.vvp

unit_gpio:
	@echo "=== tb_gpio_sfr ==="
	$(IV) -o build/unit/tb_gpio_sfr.vvp unit/tb_gpio_sfr.sv \
	    $(RTL)/gpio_sfr.sv $(RTL)/axi_sfr.sv
	$(VVP) build/unit/tb_gpio_sfr.vvp

unit_zicsr:
	@echo "=== tb_zicsr ==="
	$(IV) -o build/unit/tb_zicsr.vvp unit/tb_zicsr.sv $(RTL)/zicsr.sv
	$(VVP) build/unit/tb_zicsr.vvp

unit_bp:
	@echo "=== tb_branch_predictor ==="
	$(IV) -o build/unit/tb_branch_predictor.vvp unit/tb_branch_predictor.sv \
	    $(RTL)/branch_predictor.sv
	$(VVP) build/unit/tb_branch_predictor.vvp

unit_timer:
	@echo "=== tb_timer_axi ==="
	$(IV) -o build/unit/tb_timer_axi.vvp unit/tb_timer_axi.sv $(RTL)/timer_axi.sv
	$(VVP) build/unit/tb_timer_axi.vvp

unit_gpio_ahb:
	@echo "=== tb_gpio_ahb ==="
	$(IV) -o build/unit/tb_gpio_ahb.vvp unit/tb_gpio_ahb.sv $(RTL)/gpio_ahb.sv
	$(VVP) build/unit/tb_gpio_ahb.vvp

unit_uart:
	@echo "=== tb_uart_axi ==="
	$(IV) -o build/unit/tb_uart_axi.vvp unit/tb_uart_axi.sv $(RTL)/uart_axi.sv
	$(VVP) build/unit/tb_uart_axi.vvp

unit_periph: unit_timer unit_gpio_ahb unit_uart

unit_all: unit_alu unit_branch unit_decoder unit_rf unit_fwd unit_haz unit_fifo unit_plic \
          unit_irq_sync unit_gpio unit_zicsr unit_bp unit_timer unit_gpio_ahb unit_uart

# ───────── Integration Tests ─────────
.PHONY: integ_cpu integ_axi integ_ahb integ_all
.PHONY: p3_arithmetic p3_forwarding p3_load_store p3_branch_jump p3_csr p3_all

# Compile integration testbench once (depends on all RTL)
build/integration/tb_pipeline_cpu.vvp: integration/tb_pipeline_cpu.sv $(RTL_ALL)
	@echo "=== Compiling tb_pipeline_cpu ==="
	$(IV) -o $@ integration/tb_pipeline_cpu.sv $(RTL_ALL)

# Generic run (requires HEX=<path>)
integ_cpu: build/integration/tb_pipeline_cpu.vvp
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=$(HEX)

# Phase 3 programs
p3_arithmetic: programs/bin/prog_arithmetic.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_arithmetic ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_arithmetic.hex

p3_forwarding: programs/bin/prog_forwarding.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_forwarding ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_forwarding.hex

p3_load_store: programs/bin/prog_load_store.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_load_store ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_load_store.hex

p3_branch_jump: programs/bin/prog_branch_jump.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_branch_jump ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_branch_jump.hex

p3_csr: programs/bin/prog_csr.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_csr ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_csr.hex

p3_ecall: programs/bin/prog_ecall.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_ecall ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_ecall.hex

p3_msi: programs/bin/prog_interrupt_msi.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_interrupt_msi ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_interrupt_msi.hex

p3_mei: programs/bin/prog_interrupt_mei.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_interrupt_mei ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_interrupt_mei.hex

p3_load_fault: programs/bin/prog_load_fault.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_load_fault ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_load_fault.hex

p3_all: p3_arithmetic p3_forwarding p3_load_store p3_branch_jump p3_csr \
        p3_ecall p3_msi p3_mei p3_load_fault

# Phase 5: Full SoC — AXI/AHB peripheral access + interrupt
.PHONY: p5_axi_sfr p5_ahb_sfr p5_axi_irq p5_ahb_irq p5_all

p5_axi_sfr: programs/bin/prog_axi_sfr.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_axi_sfr ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_axi_sfr.hex

p5_ahb_sfr: programs/bin/prog_ahb_sfr.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_ahb_sfr ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_ahb_sfr.hex

p5_axi_irq: programs/bin/prog_axi_irq.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_axi_irq ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_axi_irq.hex

p5_ahb_irq: programs/bin/prog_ahb_irq.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_ahb_irq ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_ahb_irq.hex

p5_all: p5_axi_sfr p5_ahb_sfr p5_axi_irq p5_ahb_irq

# Phase 0: Branch prediction correctness test
.PHONY: p0_branch_pred
p0_branch_pred: programs/bin/prog_branch_pred.hex build/integration/tb_pipeline_cpu.vvp
	@echo "=== prog_branch_pred (branch prediction) ==="
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_branch_pred.hex

# Waveform shortcut: make p3_wave_<prog> PROG=<name>
p3_wave_%: programs/bin/prog_%.hex build/integration/tb_pipeline_cpu.vvp
	$(VVP) build/integration/tb_pipeline_cpu.vvp +HEX=programs/bin/prog_$*.hex \
	    +DUMP=build/integration/wave_$*.vcd

integ_axi:
	@echo "=== tb_axi_interface ==="
	$(IV) -o build/integration/tb_axi_interface.vvp \
	    integration/tb_axi_interface.sv models/axi_slave_model.sv \
	    $(RTL)/axi_interface.sv
	$(VVP) build/integration/tb_axi_interface.vvp

integ_ahb:
	@echo "=== tb_ahb_interface ==="
	$(IV) -o build/integration/tb_ahb_interface.vvp \
	    integration/tb_ahb_interface.sv models/ahb_slave_model.sv \
	    $(RTL)/ahb_interface.sv $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv
	$(VVP) build/integration/tb_ahb_interface.vvp

integ_axi_full:
	@echo "=== tb_axi_full (interface + interconnect + 3 SFRs) ==="
	$(IV) -o build/integration/tb_axi_full.vvp \
	    integration/tb_axi_full.sv \
	    $(RTL)/axi_interface.sv $(RTL)/axi_interconnect.sv $(RTL)/axi_sfr.sv
	$(VVP) build/integration/tb_axi_full.vvp

integ_ahb_full:
	@echo "=== tb_ahb_full (interface via CDC + interconnect + 3 SFRs) ==="
	$(IV) -o build/integration/tb_ahb_full.vvp \
	    integration/tb_ahb_full.sv \
	    $(RTL)/ahb_interface.sv $(RTL)/ahb_interconnect.sv $(RTL)/ahb_sfr.sv \
	    $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv
	$(VVP) build/integration/tb_ahb_full.vvp

integ_bus_err:
	@echo "=== tb_soc_bus_err (AXI bus error: BRESP/RRESP → store/load access fault) ==="
	$(IV) -o build/integration/tb_soc_bus_err.vvp integration/tb_soc_bus_err.sv $(RTL_ALL)
	$(VVP) build/integration/tb_soc_bus_err.vvp +HEX=programs/bin/prog_bus_err.hex
	$(VVP) build/integration/tb_soc_bus_err.vvp +HEX=programs/bin/prog_read_err.hex

integ_ahb_err:
	@echo "=== tb_soc_ahb_err (AHB bus error: HRESP → store/load access fault) ==="
	$(IV) -o build/integration/tb_soc_ahb_err.vvp integration/tb_soc_ahb_err.sv $(RTL_ALL)
	$(VVP) build/integration/tb_soc_ahb_err.vvp +HEX=programs/bin/prog_ahb_store_err.hex
	$(VVP) build/integration/tb_soc_ahb_err.vvp +HEX=programs/bin/prog_ahb_load_err.hex

integ_all: integ_cpu integ_axi integ_ahb integ_axi_full integ_ahb_full integ_bus_err integ_ahb_err

# ───────── System Tests (Phase 6) ─────────
.PHONY: system compliance_compile compliance p6_compliance p6_all rv32i_compliance

P6_PROGS = programs/bin/prog_rv32i_shifts.hex programs/bin/prog_rv32i_compare.hex \
           programs/bin/prog_dmem_endurance.hex

P7_PROGS = programs/bin/prog_plic_basic.hex programs/bin/prog_plic_priority.hex \
           programs/bin/prog_plic_threshold.hex

P8_PROGS = programs/bin/prog_csr_hazard.hex

SYSTEM_PROGS = programs/bin/prog_arithmetic.hex programs/bin/prog_forwarding.hex \
               programs/bin/prog_load_store.hex programs/bin/prog_branch_jump.hex \
               programs/bin/prog_csr.hex programs/bin/prog_ecall.hex \
               programs/bin/prog_interrupt_msi.hex programs/bin/prog_interrupt_mei.hex \
               programs/bin/prog_load_fault.hex \
               programs/bin/prog_axi_sfr.hex programs/bin/prog_ahb_sfr.hex \
               programs/bin/prog_axi_irq.hex programs/bin/prog_ahb_irq.hex \
               $(P6_PROGS) $(P7_PROGS) $(P8_PROGS)

# Phase 6a / 7: system batch test (all 20 programs)
build/system/tb_soc_top.vvp: system/tb_soc_top.sv $(RTL_ALL)
	@echo "=== Compiling tb_soc_top ==="
	$(IV) -o $@ system/tb_soc_top.sv $(RTL_ALL)

system: build/system/tb_soc_top.vvp $(SYSTEM_PROGS)
	@echo "=== System Batch Test (20 programs) ==="
	$(VVP) build/system/tb_soc_top.vvp

# Phase 6b: compliance testbench
build/system/tb_compliance.vvp: system/tb_compliance.sv $(RTL_ALL)
	@echo "=== Compiling tb_compliance ==="
	$(IV) -o $@ system/tb_compliance.sv $(RTL_ALL)

compliance_compile: build/system/tb_compliance.vvp

# Run a single ELF through compliance framework
compliance: compliance_compile
	bash scripts/run_one_test.sh $(ELF)

# Phase 6b: run compliance programs through tb_compliance
p6_compliance: build/system/tb_compliance.vvp $(P6_PROGS)
	@echo "=== prog_rv32i_shifts ==="
	$(VVP) build/system/tb_compliance.vvp +HEX=programs/bin/prog_rv32i_shifts.hex
	@echo "=== prog_rv32i_compare ==="
	$(VVP) build/system/tb_compliance.vvp +HEX=programs/bin/prog_rv32i_compare.hex
	@echo "=== prog_dmem_endurance ==="
	$(VVP) build/system/tb_compliance.vvp +HEX=programs/bin/prog_dmem_endurance.hex

p6_all: system p6_compliance

# ───────── Metrics (IPC + stall breakdown + branch hit rate + AHB latency) ─────────
.PHONY: metrics

METRICS_PROGS = programs/bin/prog_forwarding.hex programs/bin/prog_branch_pred.hex \
                programs/bin/prog_ahb_sfr.hex programs/bin/prog_fib.hex

build/system/tb_metrics.vvp: system/tb_metrics.sv $(RTL_ALL)
	@echo "=== Compiling tb_metrics ==="
	$(IV) -o $@ system/tb_metrics.sv $(RTL_ALL)

metrics: build/system/tb_metrics.vvp $(METRICS_PROGS)
	@echo "=== Pipeline Metrics (IPC / Stall / Branch Predictor / AHB Latency) ==="
	$(VVP) build/system/tb_metrics.vvp

# ───────── Task 1: Real Peripherals (Timer AXI + GPIO AHB) ─────────
.PHONY: periph_timer periph_gpio periph_uart periph_all

build/system/tb_periph.vvp: system/tb_periph.sv $(RTL_ALL) $(RTL_PERIPH)
	@echo "=== Compiling tb_periph ==="
	$(IV) -o $@ system/tb_periph.sv $(RTL_ALL) $(RTL_PERIPH)

periph_timer: programs/bin/prog_timer.hex build/system/tb_periph.vvp
	@echo "=== prog_timer (Timer AXI compare-match IRQ) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_timer.hex

periph_gpio: programs/bin/prog_gpio_ahb.hex build/system/tb_periph.vvp
	@echo "=== prog_gpio_ahb (GPIO AHB loopback + IRQ) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_gpio_ahb.hex

periph_uart: programs/bin/prog_uart.hex build/system/tb_periph.vvp
	@echo "=== prog_uart (UART AXI TX/RX loopback + IRQ) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_uart.hex

periph_all: periph_timer periph_gpio periph_uart

# ───────── D2/D3: Misaligned Exception + MTIP path ─────────
.PHONY: integ_misaligned integ_mtip integ_d2_d3
.PHONY: integ_oob integ_fence_wfi integ_d5_d6

integ_misaligned: programs/bin/prog_misaligned.hex build/system/tb_periph.vvp
	@echo "=== prog_misaligned (D2: misaligned load/store → mcause 4/6) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_misaligned.hex

integ_mtip: programs/bin/prog_mtip.hex build/system/tb_periph.vvp
	@echo "=== prog_mtip (D3: MTIP path — mip[7] via timer, mcause=0x80000007) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_mtip.hex

integ_d2_d3: integ_misaligned integ_mtip
	@echo ""
	@echo "=== D2 + D3: 2/2 PASS ==="

integ_oob: programs/bin/prog_oob_addr.hex build/system/tb_periph.vvp
	@echo "=== prog_oob_addr (D5: unmapped address → Load/Store Access Fault mcause 5/7) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_oob_addr.hex

integ_fence_wfi: programs/bin/prog_fence_wfi.hex build/system/tb_periph.vvp
	@echo "=== prog_fence_wfi (D6: FENCE+WFI as NOP — no exception, pipeline intact) ==="
	$(VVP) build/system/tb_periph.vvp +HEX=programs/bin/prog_fence_wfi.hex

integ_d5_d6: integ_oob integ_fence_wfi
	@echo ""
	@echo "=== D5 + D6: 2/2 PASS ==="

# RV32I Formal Compliance (riscv-arch-test old-framework-2.x)
# Runs 38 tests, reports PASS/SKIP/FAIL
rv32i_compliance:
	@echo "=== RV32I Compliance Tests (riscv-arch-test old-framework-2.x) ==="
	cd $(dir $(abspath $(lastword $(MAKEFILE_LIST)))) && bash compliance/run_compliance.sh

# ───────── Hex Program Build ─────────
programs/bin/%.hex: programs/src/%.s
	@mkdir -p programs/bin
	$(GCC) $(CFLAGS) -o programs/bin/$*.elf $<
	$(OBJCOPY) -O verilog --verilog-data-width 4 programs/bin/$*.elf programs/bin/$*.hex
	@echo "Built: programs/bin/$*.hex"

programs/bin/%.dump: programs/bin/%.elf
	$(OBJDUMP) -d -M numeric $< > $@

# ───────── Formal Verification (SymbiYosys) ─────────
SBY := ~/.local/bin/sby
FORMAL_DIR := formal

.PHONY: formal_x0 formal_fifo formal_uart formal_axi formal_plic formal_reg_wbr formal_stall formal_all
.PHONY: formal_alu formal_decoder formal_mem1_addr formal_axi_route formal_ahb_route
.PHONY: formal_precise_exc

formal_x0:
	@echo "=== Formal: register_file x0 always-zero ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_reg_x0 fv_reg_x0.sby

formal_fifo:
	@echo "=== Formal: async_fifo Gray-code + data integrity ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_fifo_gray fv_fifo_gray.sby

formal_uart:
	@echo "=== Formal: uart_axi 8N1 frame boundaries + pulse-width + RX counter ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_uart_proto fv_uart_proto.sby

formal_axi:
	@echo "=== Formal: axi_interface AXI4-Lite VALID-stability ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_axi_handshake fv_axi_handshake.sby

formal_plic:
	@echo "=== Formal: plic priority encoder correctness ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_plic_priority fv_plic_priority.sby

formal_reg_wbr:
	@echo "=== Formal: register_file write-before-read bypass ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_reg_wbr fv_reg_wbr.sby

formal_stall:
	@echo "=== Formal: pipeline stall coherence (hazard_unit + IF1/IF2 + IF2/ID + ID/EX regs) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_stall_coherence fv_stall_coherence.sby

formal_alu:
	@echo "=== Formal: ALU arithmetic/logic correctness (12 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_alu fv_alu.sby

formal_decoder:
	@echo "=== Formal: id_decoder encoding correctness (8 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_decoder fv_decoder.sby

formal_mem1_addr:
	@echo "=== Formal: mem1_stage address decode + misaligned detection (7 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_mem1_addr fv_mem1_addr.sby

formal_axi_route:
	@echo "=== Formal: AXI interconnect routing mutex + correctness (6 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_axi_route fv_axi_route.sby

formal_ahb_route:
	@echo "=== Formal: AHB interconnect routing mutex + correctness (5 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_ahb_route fv_ahb_route.sby

formal_precise_exc:
	@echo "=== Formal: zicsr precise exception — no trap during bus transaction (6 properties) ==="
	cd $(FORMAL_DIR) && $(SBY) -f -d ../build/formal/fv_precise_exc fv_precise_exc.sby

formal_datapath: formal_alu formal_decoder formal_mem1_addr formal_axi_route formal_ahb_route
	@echo ""
	@echo "=== Formal datapath: 5/5 PROVED ==="

formal_all: formal_x0 formal_fifo formal_uart formal_axi formal_plic formal_reg_wbr formal_stall formal_datapath formal_precise_exc
	@echo ""
	@echo "=== Formal verification: 13/13 PROVED (7 infra + 5 datapath + 1 precise-exc) ==="

# ───────── Run All ─────────
.PHONY: all clean

all: unit_all
	@echo ""
	@echo "==============================="
	@echo " Unit tests complete"
	@echo "==============================="

clean:
	rm -rf build/
	rm -f programs/bin/*.elf programs/bin/*.hex programs/bin/*.dump
