#!/usr/bin/env bash
# Запуск тестов без Xcode и SwiftPM.
#
# Среда ограничена: полный Xcode не установлен, а песочница запрещает
# запись module cache компилятора в /var/folders, из-за чего `swift test`
# не может скомпилировать манифест пакета. Этот скрипт собирает ядро и
# тесты напрямую через swiftc с module cache внутри репозитория.
#
# Использование: scripts/run-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"

CLT="/Library/Developer/CommandLineTools"
SDK="${SDKROOT:-$CLT/SDKs/MacOSX26.5.sdk}"
TARGET="arm64-apple-macosx27"
TMP="$ROOT/.tmp"
BUILD="$TMP/build"
MODULE_CACHE="$TMP/module-cache"

mkdir -p "$MODULE_CACHE" "$BUILD"

# Все Swift-файлы ядра и тестов (рекурсивно)
CORE_SOURCES="$(find Sources/MediumWellBatteryCore -name '*.swift' | sort)"
TEST_SOURCES="$(find Tests/MediumWellBatteryCoreTests -name '*.swift' | sort)"

# C-слой доступа к SMC: Swift не гарантирует раскладку структуры AppleSMC.
echo "Компиляция C-слоя SMC..."
clang -c -O2 -target "$TARGET" -isysroot "$SDK" \
    -I Sources/CSMC/include \
    Sources/CSMC/CSMC.c -o "$BUILD/CSMC.o"

# 1. Компиляция ядра как модуля с поддержкой @testable
swiftc -emit-library -emit-module \
    -module-name MediumWellBatteryCore \
    -enable-testing \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -I Sources/CSMC/include \
    -emit-module-path "$BUILD/MediumWellBatteryCore.swiftmodule" \
    -o "$BUILD/libMediumWellBatteryCore.dylib" \
    $CORE_SOURCES "$BUILD/CSMC.o"

# 2. Компиляция тестового исполняемого файла
swiftc \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -plugin-path "$CLT/usr/lib/swift/host/plugins/testing" \
    -I Sources/CSMC/include \
    -F "$CLT/Library/Developer/Frameworks" \
    -I "$BUILD" -L "$BUILD" -lMediumWellBatteryCore \
    -Xlinker -rpath -Xlinker "$BUILD" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" \
    $TEST_SOURCES scripts/test-main.swift "$BUILD/CSMC.o" \
    -o "$BUILD/test-runner"

# 3. Запуск тестов
exec "$BUILD/test-runner"
