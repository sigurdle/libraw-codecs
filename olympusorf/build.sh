#!/usr/bin/env bash
#
# Build the Olympus / OM System ORF raw decoder WASM from orf_decode.cpp — a port of LibRaw's
# olympus_load_raw (LGPL-2.1 / CDDL-1.0; see PROVENANCE.md and LICENSE.CDDL alongside). Kept in its
# OWN wasm binary (the canoncrx precedent), which keeps the license boundary clean: the module is
# separately built and replaceable.
#
# -fno-exceptions: the decoder never throws (upstream has no throw on this path either).
#
# ALLOW_MEMORY_GROWTH is required: a 20 MP frame is 40 MB of mosaic plus its compressed strip.
#
# Outputs:
#   ./orf_decode.{mjs,wasm}                shipped decoder (web,worker)
#   ../../tests/wasm/orf_codec.{mjs,wasm}  node build for the vitest conformance test
#
# Usage: ./build.sh   (OPT=-Oz ./build.sh for a size build)
set -euo pipefail

HERE_W="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W)"
EMSDK_DIR="${EMSDK_DIR:-/d/dev/tools/emsdk}"
OPT="${OPT:--O3}"
LINK_OPT="${LINK_OPT:--O3}"

EMSDK_W="$(cd "$EMSDK_DIR" && pwd -W)"
PYBIN="$(ls "$EMSDK_DIR"/python/*/python.exe | head -1)"
export EM_CONFIG="$EMSDK_W/.emscripten"
export EMSDK_PYTHON="$(cd "$(dirname "$PYBIN")" && pwd -W)/python.exe"
EMCC="$EMSDK_W/upstream/emscripten/emcc.py"
emcc() { "$PYBIN" "$EMCC" "$@"; }

SRC="$HERE_W/orf_decode.cpp"
OBJ="$HERE_W/orf_decode.o"

echo "compiling olympus orf ($OPT)..."
emcc $OPT -ffunction-sections -fdata-sections -fno-exceptions -c "$SRC" -o "$OBJ"

EXPORTS=_orf_decode,_malloc,_free

LINK_COMMON=( $LINK_OPT -Wl,--gc-sections -sMALLOC=emmalloc -sFILESYSTEM=0
              -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB
              -sMODULARIZE=1 -sEXPORT_ES6=1
              -sEXPORTED_RUNTIME_METHODS=HEAPU8 --no-entry )

echo "=== link: shipped decoder (web,worker) ==="
emcc "${LINK_COMMON[@]}" -sENVIRONMENT=web,worker -sEXPORT_NAME=OrfDecodeModule \
	-sEXPORTED_FUNCTIONS=$EXPORTS "$OBJ" -o "$HERE_W/orf_decode.mjs"

TESTDIR_W="$(cd "$HERE_W/../../tests" && pwd -W)/wasm"
mkdir -p "$TESTDIR_W"
echo "=== link: node test build ==="
emcc "${LINK_COMMON[@]}" -sENVIRONMENT=web,worker,node -sEXPORT_NAME=OrfCodecModule \
	-sEXPORTED_FUNCTIONS=$EXPORTS "$OBJ" -o "$TESTDIR_W/orf_codec.mjs"

echo "BUILD_OK"
ls -la "$HERE_W"/orf_decode.wasm "$TESTDIR_W"/orf_codec.wasm
