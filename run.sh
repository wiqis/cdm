#!/usr/bin/env bash
# ChemicalDM build & run helper.
#
# Usage:
#   ./run.sh              build the app, then launch it (GUI)
#   ./run.sh --build      build only (do not run)
#   ./run.sh --test       build with the test suite enabled, then run the tests
#   ./run.sh --llvm       use the LLVM/Clang backend (Compiler binary)
#   ./run.sh --debug      build with debug_complete mode
#   ./run.sh --clean      remove build artifacts
#
# Compiler discovery: looks for the compiler in the repository's
# cmake-build-debug/ directory (i.e. ../../cmake-build-debug relative to this
# script), falling back to out/build for CI layouts.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# Locate the compiler binary in the parent (chemical) repo. Prefer the standard
# developer build dir; fall back to the CI build dir.
find_compiler() {
    for dir in "$HERE/../../../cmake-build-debug" "$HERE/../../../out/build"; do
        if [ -x "$dir/TCCCompiler" ] || [ -x "$dir/TCCCompiler.exe" ]; then
            printf '%s' "$dir"
            return 0
        fi
    done
    return 1
}

BACKEND="tcc"
ONLY_BUILD=false
TEST_MODE=false
DEBUG_MODE=false
CLEAN=false
MODE="debug_quick"

for arg in "$@"; do
    case "$arg" in
        --llvm) BACKEND="llvm";;
        --build) ONLY_BUILD=true;;
        --test) TEST_MODE=true;;
        --debug) DEBUG_MODE=true; MODE="debug_complete";;
        --clean) CLEAN=true;;
        --debug_quick) MODE="debug_quick";;
        --debug_complete) MODE="debug_complete";;
        *) echo "run.sh: unknown option: $arg" >&2; exit 1;;
    esac
done

if [ "$CLEAN" = true ]; then
    rm -rf build bin
    echo "==> cleaned"
    exit 0
fi

BUILD_DIR="$(find_compiler || true)"
if [ -z "$BUILD_DIR" ]; then
    echo "run.sh: compiler not found under ../../../cmake-build-debug or ../../../out/build" >&2
    echo "        build the chemical compiler first: ../../../scripts/build.sh --tcc" >&2
    exit 1
fi

if [ "$BACKEND" = "llvm" ]; then
    COMPILER="$BUILD_DIR/Compiler"
else
    COMPILER="$BUILD_DIR/TCCCompiler"
fi
if [ ! -x "$COMPILER" ]; then
    echo "run.sh: $COMPILER not found (build it with ../../../scripts/build.sh --$BACKEND)" >&2
    exit 1
fi

mkdir -p bin

echo "==> compiling chemicaldm ($BACKEND backend, mode=$MODE)"
if [ "$TEST_MODE" = true ]; then
    "$COMPILER" "chemical.mod" -o "bin/cdm" --mode "$MODE" --no-cache --test
else
    "$COMPILER" "chemical.mod" -o "bin/cdm" --mode "$MODE" --no-cache
fi

if [ "$TEST_MODE" = true ]; then
    echo "==> running test suite"
    exec ./bin/cdm --test
fi

if [ "$ONLY_BUILD" = true ]; then
    echo "==> built: bin/cdm"
    exit 0
fi

echo "==> launching chemicaldm"
exec ./bin/cdm