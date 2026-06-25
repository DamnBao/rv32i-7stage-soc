#!/bin/bash
# run_compliance.sh — RV32I compliance test runner (riscv-arch-test old-framework-2.x)
#
# Builds each test, runs on our SoC simulation, compares signature with reference.
# Must be run from SIM/ directory: bash compliance/run_compliance.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RTL_DIR="$SIM_DIR/../RTL"

TESTS_SRC="$SCRIPT_DIR/tests/src"
TESTS_REF="$SCRIPT_DIR/tests/references"
WORK_DIR="$SCRIPT_DIR/work"
VVP="$SCRIPT_DIR/tb_compliance_run.vvp"

GCC="riscv64-unknown-elf-gcc"
OBJCOPY="riscv64-unknown-elf-objcopy"
NM="riscv64-unknown-elf-nm"
IV="iverilog -g2012 -Wall"
IMEM_MAX=524288  # 512KB for compliance (branch tests need up to ~294KB)

CFLAGS="-march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
        -DXLEN=32 \
        -T $SCRIPT_DIR/link_compliance.ld \
        -Wl,--no-check-sections \
        -I $SCRIPT_DIR \
        -I $SCRIPT_DIR/env"
# --no-check-sections: suppresses linker LMA overlap check.
# In our Harvard architecture simulation, IMEM and DMEM are separate arrays
# ($readmemh loads them independently), so branch tests with code >64KB that
# "overlap" the DMEM LMA range (0x10000) are safe at runtime.

mkdir -p "$WORK_DIR"

# ── Compile testbench (once) ──────────────────────────────────────────────────
echo "=== Compiling tb_compliance_run ==="
RTL_ALL=$(ls "$RTL_DIR"/*.sv | tr '\n' ' ')
$IV -o "$VVP" "$SCRIPT_DIR/tb_compliance_run.sv" $RTL_ALL 2>/dev/null
echo "Compile OK"
echo ""

# ── Run all tests ─────────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0; TOTAL=0
FAIL_LIST=""; SKIP_LIST=""

for src in "$TESTS_SRC"/*.S; do
    name=$(basename "$src" .S)
    elf="$WORK_DIR/$name.elf"
    hex="$WORK_DIR/$name.hex"
    dmem_hex="$WORK_DIR/$name.dmem.hex"
    sig="$WORK_DIR/$name.sig"
    ref="$TESTS_REF/$name.reference_output"
    TOTAL=$((TOTAL + 1))

    # ── Build ──────────────────────────────────────────────────────────────────
    build_log="$WORK_DIR/$name.build.log"
    if ! $GCC $CFLAGS -o "$elf" "$src" 2>"$build_log"; then
        # Check if IMEM overflow (too large for 64KB hardware)
        if grep -q "overflowed\|IMEM\|will not fit" "$build_log" 2>/dev/null; then
            echo "SKIP(IMEM)    $name  (code > 64KB IMEM limit)"
            SKIP=$((SKIP + 1)); SKIP_LIST="$SKIP_LIST $name"; continue
        else
            echo "COMPILE_FAIL  $name"
            cat "$build_log" | head -3 | sed 's/^/              /'
            FAIL=$((FAIL + 1)); FAIL_LIST="$FAIL_LIST $name(compile)"; continue
        fi
    fi

    # ── Check code section fits in 64KB IMEM ─────────────────────────────────
    TEXT_SIZE=$(riscv64-unknown-elf-size "$elf" 2>/dev/null | awk 'NR==2{print $1}')
    if [ "${TEXT_SIZE:-0}" -gt "$IMEM_MAX" ]; then
        echo "SKIP(IMEM)    $name  (text=${TEXT_SIZE}B > 64KB)"
        SKIP=$((SKIP + 1)); SKIP_LIST="$SKIP_LIST $name"; continue
    fi

    # ── Extract code-only IMEM hex ────────────────────────────────────────────
    $OBJCOPY -O verilog --verilog-data-width 4 \
        -j .text.init -j .text -j .rodata \
        "$elf" "$hex" 2>/dev/null

    # ── Extract DMEM init hex from .data section (rebased to 0x0 for $readmemh) ─
    # Needed by load/store tests that read pre-initialized test data
    $OBJCOPY -O verilog --verilog-data-width 4 \
        -j .data \
        --change-addresses=-0x10000 \
        "$elf" "$dmem_hex" 2>/dev/null || rm -f "$dmem_hex"

    # ── Extract signature symbol addresses ────────────────────────────────────
    SIG_BEGIN_HEX=$($NM "$elf" 2>/dev/null | awk '/begin_signature/ {print $1}')
    SIG_END_HEX=$($NM "$elf"   2>/dev/null | awk '/end_signature/   {print $1}')

    if [ -z "$SIG_BEGIN_HEX" ] || [ -z "$SIG_END_HEX" ]; then
        echo "SYMBOL_FAIL   $name  (no begin/end_signature)"
        FAIL=$((FAIL + 1)); FAIL_LIST="$FAIL_LIST $name(symbol)"; continue
    fi

    SIG_BEGIN_DEC=$((16#$SIG_BEGIN_HEX))
    SIG_END_DEC=$((16#$SIG_END_HEX))
    if [ "$SIG_BEGIN_DEC" -lt $((16#10000)) ] || [ "$SIG_END_DEC" -gt $((16#20000)) ]; then
        echo "ADDR_FAIL     $name  (sig 0x$SIG_BEGIN_HEX–0x$SIG_END_HEX out of DMEM)"
        FAIL=$((FAIL + 1)); FAIL_LIST="$FAIL_LIST $name(addr)"; continue
    fi

    # ── Simulate ──────────────────────────────────────────────────────────────
    VVP_ARGS="+HEX=$hex +SIG_BEGIN=$SIG_BEGIN_HEX +SIG_END=$SIG_END_HEX +SIG_FILE=$sig"
    if [ -f "$dmem_hex" ]; then
        VVP_ARGS="$VVP_ARGS +DMEM_HEX=$dmem_hex"
    fi

    if ! vvp "$VVP" $VVP_ARGS 2>/dev/null; then
        echo "SIM_FAIL      $name"
        FAIL=$((FAIL + 1)); FAIL_LIST="$FAIL_LIST $name(sim)"; continue
    fi

    # ── Compare signature ─────────────────────────────────────────────────────
    if diff -q "$sig" "$ref" > /dev/null 2>&1; then
        echo "PASS          $name"
        PASS=$((PASS + 1))
    else
        echo "SIG_MISMATCH  $name"
        MISMATCH=$(diff "$sig" "$ref" | grep "^[<>]" | wc -l)
        echo "              ($MISMATCH differing lines)"
        diff "$sig" "$ref" | grep "^[<>]" | head -4 | sed 's/^/              /'
        FAIL=$((FAIL + 1)); FAIL_LIST="$FAIL_LIST $name(sig)"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  RV32I Compliance: $PASS / $TOTAL PASS"
if [ $SKIP -gt 0 ]; then
    echo "  SKIP ($SKIP, code exceeds 64KB IMEM):$SKIP_LIST"
fi
if [ $FAIL -gt 0 ]; then
    echo "  FAIL ($FAIL): $FAIL_LIST"
fi
echo "══════════════════════════════════════════════"
[ $FAIL -eq 0 ]  # exit 0 if no failures (skips are not failures)
