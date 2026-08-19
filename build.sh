#!/usr/bin/env bash
# Build the ChemicalDM application using the TCC compiler backend.
#
# Usage:
#   ./build.sh              build cdm binary into ./bin/
#   ./build.sh --llvm       build with the LLVM/Clang backend (Compiler binary)
#   ./build.sh --run        build then launch
#   ./build.sh --selftest   build then run the internal test suite
#   ./build.sh --clean      remove build artifacts
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$HERE"

BACKEND="--tcc"
COMPILER="$ROOT/cmake-build-debug/TCCCompiler"
RUN=false
SELFTEST=false
CLEAN=false
MODE="debug_quick"

for arg in "$@"; do
    case "$arg" in
        --llvm) BACKEND="--llvm"; COMPILER="$ROOT/cmake-build-debug/Compiler";;
        --run) RUN=true;;
        --selftest) SELFTEST=true;;
        --clean) CLEAN=true;;
        --debug_complete) MODE="debug_complete";;
        *) echo "unknown option: $arg" >&2; exit 1;;
    esac
done

if [ ! -x "$COMPILER" ]; then
    echo "compiler not found: $COMPILER (run ./scripts/build.sh --tcc first)" >&2
    exit 1
fi

if [ "$CLEAN" = true ]; then
    rm -rf build bin
    exit 0
fi

mkdir -p bin

echo "==> compiling chemicaldm (${BACKEND})"
"$COMPILER" "chemical.mod" -o "bin/cdm" --mode "$MODE" --no-cache

if [ "$RUN" = true ]; then
    echo "==> launching chemicaldm"
    exec ./bin/cdm
fi

if [ "$SELFTEST" = true ]; then
    echo "==> running self-tests"
    ./bin/cdm --selftest
fi

echo "==> built: bin/cdm"