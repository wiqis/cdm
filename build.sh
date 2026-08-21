#!/usr/bin/env bash
# Build the ChemicalDM application using the TCC compiler backend.
#
# Usage:
#   ./build.sh              build cdm binary into ./bin/
#   ./build.sh --llvm       build with the LLVM/Clang backend (Compiler binary)
#   ./build.sh --test       build with test resources + run the @test suite
#   ./build.sh --run        build then launch
#   ./build.sh --clean      remove build artifacts
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$HERE"

BACKEND="--tcc"
COMPILER="$ROOT/cmake-build-debug/TCCCompiler"
RUN=false
TEST_MODE=false
CLEAN=false
MODE="debug_quick"

for arg in "$@"; do
    case "$arg" in
        --llvm) BACKEND="--llvm"; COMPILER="$ROOT/cmake-build-debug/Compiler";;
        --run) RUN=true;;
        --test) TEST_MODE=true;;
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
if [ "$TEST_MODE" = true ]; then
    "$COMPILER" "chemical.mod" -o "bin/cdm" --mode "$MODE" --no-cache --test
else
    "$COMPILER" "chemical.mod" -o "bin/cdm" --mode "$MODE" --no-cache
fi

if [ "$TEST_MODE" = true ]; then
    echo "==> running test suite"
    exec ./bin/cdm --test
fi

if [ "$RUN" = true ]; then
    echo "==> launching chemicaldm"
    exec ./bin/cdm
fi

echo "==> built: bin/cdm"