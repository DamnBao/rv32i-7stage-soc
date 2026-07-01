#!/bin/bash
# run_one_test.sh — Convert ELF to hex and run through tb_compliance testbench.
# Usage: bash scripts/run_one_test.sh <elf_file>
# Exit codes: 0=PASS, 1=FAIL, 2=ERROR

set -e

ELF="$1"
if [ -z "$ELF" ]; then
    echo "Usage: $0 <elf_file>"
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(dirname "$SCRIPT_DIR")"
BASENAME=$(basename "$ELF" .elf)
HEX="/tmp/compliance_${BASENAME}_$$.hex"
VVP="${SIM_DIR}/build/system/tb_compliance.vvp"
LOG="/tmp/compliance_${BASENAME}_$$.log"

cleanup() { rm -f "$HEX" "$LOG"; }
trap cleanup EXIT

# Compile testbench if needed
if [ ! -f "$VVP" ]; then
    echo "[run_one_test] Compiling tb_compliance..."
    make -C "$SIM_DIR" compliance_compile
fi

# ELF → Verilog hex (word-aligned, little-endian)
riscv64-unknown-elf-objcopy -O verilog --verilog-data-width 4 "$ELF" "$HEX"

# Run simulation (30s timeout)
if ! timeout 30s vvp "$VVP" +HEX="$HEX" > "$LOG" 2>&1; then
    : # vvp may exit non-zero for FAIL; check output below
fi

# Parse result
if grep -q "^TEST_PASS" "$LOG"; then
    echo "PASS: $BASENAME"
    exit 0
elif grep -q "^TEST_FAIL" "$LOG"; then
    echo "FAIL: $BASENAME"
    grep "TEST_FAIL" "$LOG" >&2
    exit 1
else
    echo "ERROR: $BASENAME (no halt marker or timeout)"
    cat "$LOG" >&2
    exit 2
fi
