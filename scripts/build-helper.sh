#!/bin/bash
# Собирает привилегированный helper для управления зарядом.
# Выход: .build/helper (исполняемый файл, готов к установке с setuid root).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/.build"

CSMC_SRC="$ROOT_DIR/Sources/CSMC"
HELPER_SRC="$ROOT_DIR/Sources/Helper/helper.c"
OUTPUT="$BUILD_DIR/helper"

mkdir -p "$BUILD_DIR"

echo "Сборка helper..."
clang -o "$OUTPUT" \
    "$HELPER_SRC" \
    -I "$ROOT_DIR/Sources" \
    -framework IOKit \
    -framework CoreFoundation \
    -O2

echo "✓ Готово: $OUTPUT"
ls -lh "$OUTPUT"
