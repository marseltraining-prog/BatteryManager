#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/scripts/build-helper.sh" || { echo "Сборка helper не удалась."; read -p "Нажми Enter для закрытия..."; exit 1; }
echo
echo "Сейчас macOS попросит пароль администратора для установки helper."
echo
if osascript -e "do shell script \"'$SCRIPT_DIR/scripts/install-helper.sh'\" with administrator privileges" 2>&1; then
    echo
    echo "✓ Готово! Окно можно закрыть."
    echo "  Теперь приложение сможет управлять ограничением заряда."
else
    echo
    echo "Не получилось. Напиши мне в чат."
fi
read -p "Нажми Enter для закрытия..."
