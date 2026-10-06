#!/bin/bash
# Устанавливает привилегированный helper в систему.
# Требуется sudo (спросит пароль).
#
# Установка:
#   sudo ./scripts/install-helper.sh
#
# После установки приложение сможет управлять зарядом через:
#   /Library/PrivilegedHelperTools/com.mediumwell.BatteryManager.helper hold
#   /Library/PrivilegedHelperTools/com.mediumwell.BatteryManager.helper allow

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Этот скрипт требует прав root. Запусти: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HELPER_SRC="$ROOT_DIR/.build/helper"
HELPER_DST="/Library/PrivilegedHelperTools/com.mediumwell.BatteryManager.helper"

if [ ! -f "$HELPER_SRC" ]; then
    echo "Ошибка: helper не собран. Сначала запусти: ./scripts/build-helper.sh"
    exit 1
fi

echo "Устанавливаю helper в $HELPER_DST..."
cp "$HELPER_SRC" "$HELPER_DST"
chown root:wheel "$HELPER_DST"
chmod 4755 "$HELPER_DST"

echo "✓ Helper установлен."
echo
echo "Проверка:"
"$HELPER_DST" status
