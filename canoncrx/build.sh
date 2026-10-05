#!/usr/bin/env bash
#
# Build the Canon CR3 `crx` RAW decoder WASM from crx_decode.cpp — a port of LibRaw's crx
# decoder (LGPL-2.1 / CDDL-1.0; see PROVENANCE.md and LICENSE.CDDL alongside). Kept in its OWN
# wasm binary (vc1/vp6 precedent) — which is also what keeps the license boundary clean: the
# module is separately built and replaceable.
#
# NOTE (2026-08-02): the paragraph below was wrong. Smart App Control IS enforced
# here (VerifiedAndReputablePolicyState=1), but wasm-opt.exe runs fine under it —
# verified by running it. So the link is NOT pinned to -O0 any more: LINK_OPT
# (default -O3) lets Binaryen run, which is ~12% SMALLER at identical decode speed.
# Measured on JPEG: TU -O3/link -O0 = 582KB, TU -O3/link -O3 = 511KB, 0.999x speed.
# Same Smart App Control / Binaryen workaround as the sibling ports: clang optimizes at -O3, the
# link runs at -O0 (no wasm-opt/metadce) and wasm-ld --gc-sections strips unreferenced code.
#
# -fno-exceptions is deliberate: the port has no `throw` left (upstream's only C++-runtime use,
# a std::vector guarded by catch(...), became calloc + a null check), so nothing needs unwinding.
#
# ALLOW_MEMORY_GROWTH is required: a 24 MP frame needs ~50 MB for the mosaic alone, plus the
# per-plane wavelet buffers on the C-RAW path.
#
# STACK_SIZE is required too, and is NOT optional tuning: CrxBitstream embeds a 64 KB refill
# buffer (CRX_BUF_SIZE) and crxReadImageHeaders puts one on the stack, which overflows
# Emscripten's 64 KB default immediately. Upstream never noticed — it runs on a native stack.
#
# Outputs:
#   ./crx_decode.{mjs,wasm}                shipped decoder (web,worker)
#   ../../tests/wasm/crx_codec.{mjs,wasm}  node build for the vitest conformance test
#
# Usage: ./build.sh   (OPT=-Oz ./build.sh for a size build)
set -euo pipefail

HERE_W="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W)"
EMSDK_DIR="${EMSDK_DIR:-/d/dev/tools/emsdk}"
OPT="${OPT:--O3}"
# Link-time optimization level — this is the step that runs Binaryen (wasm-opt).
# It used to be pinned to -O0 because Smart App Control was thought to block the
# unsigned Binaryen binaries; measured 2026-08-02, wasm-opt runs fine under SAC
# (enforced, state 1) and -O3 linking is ~12% smaller at identical decode speed.
LINK_OPT="${LINK_OPT:--O3}"

EMSDK_W="$(cd "$EMSDK_DIR" && pwd -W)"
PYBIN="$(ls "$EMSDK_DIR"/python/*/python.exe | head -1)"
export EM_CONFIG="$EMSDK_W/.emscripten"
export EMSDK_PYTHON="$(cd "$(dirname "$PYBIN")" && pwd -W)/python.exe"
EMCC="$EMSDK_W/upstream/emscripten/emcc.py"
emcc() { "$PYBIN" "$EMCC" "$@"; }

SRC="$HERE_W/crx_decode.cpp"
OBJ="$HERE_W/crx_decode.o"

echo "compiling crx ($OPT)..."
emcc $OPT -ffunction-sections -fdata-sections -fno-exceptions -c "$SRC" -o "$OBJ"

EXPORTS=_crx_decode,_malloc,_free

LINK_COMMON=( $LINK_OPT -Wl,--gc-sections -sMALLOC=emmalloc -sFILESYSTEM=0
              -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576
              -sMODULARIZE=1 -sEXPORT_ES6=1
              -sEXPORTED_RUNTIME_METHODS=HEAPU8 --no-entry )

echo "=== link: shipped decoder (web,worker) ==="
emcc "${LINK_COMMON[@]}" -sENVIRONMENT=web,worker -sEXPORT_NAME=CrxDecodeModule \
	-sEXPORTED_FUNCTIONS=$EXPORTS "$OBJ" -o "$HERE_W/crx_decode.mjs"

TESTDIR_W="$(cd "$HERE_W/../../tests" && pwd -W)/wasm"
mkdir -p "$TESTDIR_W"
echo "=== link: node test build ==="
emcc "${LINK_COMMON[@]}" -sENVIRONMENT=web,worker,node -sEXPORT_NAME=CrxCodecModule \
	-sEXPORTED_FUNCTIONS=$EXPORTS "$OBJ" -o "$TESTDIR_W/crx_codec.mjs"

echo "BUILD_OK"
ls -la "$HERE_W"/crx_decode.wasm "$TESTDIR_W"/crx_codec.wasm
