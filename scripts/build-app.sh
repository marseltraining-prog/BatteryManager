#!/usr/bin/env bash
# Сборка BatteryManager.app без Xcode.
#
# Собирает ядро как динамическую библиотеку, компилирует приложение
# (App/), собирает .app-бандл вручную (Info.plist + PkgInfo) и
# подписывает его ad-hoc. Работает в той же ограниченной среде, что и
# scripts/run-tests.sh (module cache внутри репозитория).
#
# Использование: scripts/build-app.sh [--run]
#   --run  после сборки запустить приложение через `open`
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"

CLT="/Library/Developer/CommandLineTools"
SDK="${SDKROOT:-$CLT/SDKs/MacOSX26.5.sdk}"
TARGET="arm64-apple-macosx27"
# Версия для Info.plist: Apple требует до трёх чисел через точку,
# поэтому убираем префикс «v» и суффикс предрелиза (v1.0.0-beta → 1.0.0).
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed -e 's/^v//' -e 's/-.*$//' || true)"
VERSION="${VERSION:-0.0.0}"

TMP="$ROOT/.tmp"
BUILD="$TMP/build"
APP="$ROOT/build/BatteryManager.app"
MODULE_CACHE="$TMP/module-cache"

mkdir -p "$MODULE_CACHE" "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Frameworks"

CORE_SOURCES="$(find Sources/MediumWellBatteryCore -name '*.swift' | sort)"
APP_SOURCES="$(find App -name '*.swift' | sort)"

# 1. Ядро как динамическая библиотека (та же, что использует тест-раннер).
swiftc -emit-library -emit-module \
    -module-name MediumWellBatteryCore \
    -enable-testing \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -emit-module-path "$BUILD/MediumWellBatteryCore.swiftmodule" \
    -o "$BUILD/libMediumWellBatteryCore.dylib" \
    $CORE_SOURCES

# 2. Компиляция приложения.
swiftc \
    -parse-as-library \
    -module-name BatteryManager \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-cache-path "$MODULE_CACHE" \
    -I "$BUILD" -L "$BUILD" -lMediumWellBatteryCore \
    -Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
    $APP_SOURCES \
    -o "$APP/Contents/MacOS/BatteryManager"

# 3. Ядро внутрь бандла.
cp "$BUILD/libMediumWellBatteryCore.dylib" "$APP/Contents/Frameworks/"

# 4. Info.plist и PkgInfo.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.mediumwell.BatteryManager</string>
    <key>CFBundleName</key>
    <string>BatteryManager</string>
    <key>CFBundleDisplayName</key>
    <string>BatteryManager</string>
    <key>CFBundleExecutable</key>
    <string>BatteryManager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 5. Ad-hoc подпись.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Собрано: $APP ($VERSION)"

if [ "${1:-}" = "--run" ]; then
    open "$APP"
    echo "Запущено через open."
fi
