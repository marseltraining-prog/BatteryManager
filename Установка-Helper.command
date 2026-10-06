#!/bin/bash
# Установка helper управления зарядом (macOS спросит пароль администратора).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DST="/Library/PrivilegedHelperTools/com.mediumwell.BatteryManager.helper"

finish() { echo; read -p "Нажми Enter для закрытия..."; exit "$1"; }

"$SCRIPT_DIR/scripts/build-helper.sh" || { echo "Сборка helper не удалась."; finish 1; }

# Процесс с правами администратора не имеет доступа к папке «Документы»
# (защита macOS), поэтому helper сначала копируется во временный файл,
# а команды установки передаются напрямую, без запуска скрипта из проекта.
TMP="$(mktemp /private/tmp/batterymanager-helper.XXXXXX)" || finish 1
cp "$SCRIPT_DIR/.build/helper" "$TMP" || { echo "Не удалось подготовить helper."; finish 1; }

echo
echo "Сейчас macOS попросит пароль администратора для установки helper."
echo
INSTALL="mkdir -p /Library/PrivilegedHelperTools && cp '$TMP' '$DST' && chown root:wheel '$DST' && chmod 4755 '$DST'"
if osascript -e "do shell script \"$INSTALL\" with administrator privileges" 2>&1; then
    rm -f "$TMP"
    echo "✓ Helper установлен. Проверка:"
    "$DST" status
    echo
    echo "Теперь приложение может управлять ограничением заряда."
    finish 0
else
    rm -f "$TMP"
    echo
    echo "Не получилось. Напиши мне в чат."
    finish 1
fi
