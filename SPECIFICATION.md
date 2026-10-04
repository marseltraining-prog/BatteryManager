# BatteryManager - Техническая спецификация v1.0

## 1. Обзор проекта

**Название:** BatteryManager  
**Цель:** Создать современный менеджер батареи для macOS с управлением зарядкой, мониторингом состояния и защитой от перегрева в стиле Liquid Glass.

**Целевая аудитория:** Пользователи MacBook, желающие продлить срок службы батареи через ограничение максимального заряда.

**Платформа:** macOS 13 Ventura и новее (Apple Silicon и Intel)

---

## 2. Функциональные требования

### 2.1 Управление зарядкой

**FR-001: Установка лимита заряда**
- Пользователь может установить максимальный процент заряда от 20% до 100%
- Лимит применяется через privileged helper с системными привилегиями
- Изменения вступают в силу немедленно
- Лимит сохраняется между перезапусками приложения

**FR-002: Принудительный разряд**
- Кнопка "Разряд" принудительно отключает зарядку
- Батарея разряжается даже при подключенном адаптере
- Режим остается активным до отмены пользователем

**FR-003: Принудительный заряд**
- Кнопка "Заряд" игнорирует установленный лимит
- Батарея заряжается до 100%
- Режим автоматически отключается при достижении 100%

### 2.2 Мониторинг батареи

**FR-004: Отображение текущего состояния**
- Текущий процент заряда (обновление каждые 2 секунды)
- Статус зарядки (charging/discharging)
- Мощность зарядки/разрядки в ваттах
- Температура батареи в градусах Цельсия

**FR-005: Визуализация потребления энергии**
- Две горизонтальные полосы:
  - Верхняя: мощность, идущая на зарядку батареи (W)
  - Нижняя: мощность, потребляемая системой (W)
- Слева: общая мощность от адаптера питания
- Анимация изменения ширины полос при изменении значений

**FR-006: Здоровье батареи**
- Проектная емкость (mAh и %)
- Максимальная текущая емкость (mAh и %)
- Емкость, определенная macOS (mAh и %)
- Состояние батареи (Normal/Replace Soon/Service Battery)
- Количество циклов зарядки

### 2.3 Графики и история

**FR-007: График заряда батареи**
- История заряда (%) за последние 24 часа
- Обновление каждые 60 секунд
- Зеленый градиент с заливкой под линией

**FR-008: График температуры**
- История температуры (°C) за последние 24 часа
- Динамический цвет: синий → желтый → красный в зависимости от значения
- Визуальное выделение зон перегрева

**FR-009: График потребления энергии**
- История мощности (W) за последние 24 часа
- Положительные значения: зарядка
- Отрицательные значения: разрядка
- Голубой градиент

### 2.4 Защита от перегрева

**FR-010: Двухуровневая система**
- **Уровень 1 (Предупреждение): 35-40°C**
  - Желтое уведомление "Батарея нагревается"
  - Иконка в доке становится желтой с ⚠️
  - Звуковой сигнал (опционально)
  
- **Уровень 2 (Критическое): >40°C**
  - Красное уведомление "Критический перегрев батареи!"
  - Автоматическое отключение зарядки
  - Иконка в доке становится красной с 🔥
  - Звуковой сигнал (громче)
  - Логирование события

**FR-011: Автоматическое возобновление зарядки**
- Когда температура опускается ниже 35°C
- Восстановление установленного лимита
- Уведомление "Зарядка возобновлена"

### 2.5 Иконка в доке

**FR-012: Динамическая иконка**
- Показывает текущий процент заряда overlay-текстом
- Цветовые состояния:
  - Зеленый: зарядка
  - Белый/серый: разрядка
  - Желтый: предупреждение о температуре
  - Красный: критический перегрев
- Дополнительные индикаторы:
  - ⚡ при зарядке
  - ⚠️ при предупреждении
  - 🔥 при перегреве
- Обновление каждые 2 секунды

### 2.6 Пользовательский интерфейс

**FR-013: Главное окно (Popover)**
- Открывается при клике на иконку в доке
- Размер: 420x680 пикселей
- Liquid Glass стиль (полупрозрачность + blur)
- Три вкладки: "Статус" / "Графики" / "Здоровье"

**FR-014: Вкладка "Статус"**
- Верхняя панель с кнопками управления
- Индикатор батареи с процентом
- Слайдер установки лимита
- Визуализация распределения энергии
- Информация о приложениях, потребляющих энергию (опционально)

**FR-015: Вкладка "Графики"**
- Три графика рядом друг с другом
- Возможность наведения на точку для точного значения
- Автоматическое масштабирование осей

**FR-016: Вкладка "Здоровье"**
- Карточка с информацией о батарее
- Цветовые индикаторы состояния
- Рекомендации по обслуживанию (при необходимости)

---

## 3. Нефункциональные требования

### 3.1 Производительность

**NFR-001: Низкое потребление ресурсов**
- CPU: < 1% в фоновом режиме
- RAM: < 50 MB
- Энергопотребление: minimal impact на батарею

**NFR-002: Частота обновления**
- UI: каждые 2 секунды
- История (SQLite): каждые 60 секунд
- Иконка в доке: каждые 2 секунды

**NFR-003: Отзывчивость**
- Открытие окна: < 0.2 секунды
- Применение лимита: < 0.5 секунды
- Переключение вкладок: < 0.3 секунды

### 3.2 Надежность

**NFR-004: Обработка ошибок**
- Валидация всех данных от IOKit
- Fallback на последние корректные значения
- Логирование ошибок в системный консоль
- Graceful degradation при отсутствии привилегий

**NFR-005: Устойчивость к сбоям**
- Автовосстановление при краше
- Сохранение настроек при аварийном завершении
- Пересоздание базы данных при повреждении

**NFR-006: Управление энергопотреблением**
- Приостановка мониторинга при переходе в сон
- Возобновление через 5 секунд после пробуждения
- Отсутствие записи данных во время сна

### 3.3 Безопасность

**NFR-007: Привилегированный доступ**
- Использование SMJobBless для установки helper
- Helper работает с минимальными привилегиями
- XPC для коммуникации между процессами
- Подпись кода для всех компонентов

**NFR-008: Валидация входных данных**
- Лимит заряда: 20-100%
- Температура: -10°C до 100°C (валидный диапазон)
- Мощность: 0W до 200W

### 3.4 Совместимость

**NFR-009: Поддержка систем**
- macOS 13 Ventura (минимум)
- macOS 14 Sonoma
- macOS 15 Sequoia и новее
- Apple Silicon (M1/M2/M3/M4)
- Intel процессоры

**NFR-010: Локализация**
- Русский язык (primary)
- Английский язык (secondary)
- Возможность добавления других языков

### 3.5 Удобство использования

**NFR-011: Accessibility**
- Поддержка VoiceOver
- Контрастность по WCAG AA
- Увеличенные hit targets (минимум 44x44px)
- Поддержка Reduce Motion

**NFR-012: Интуитивность**
- Понятные иконки и подписи
- Подсказки при наведении
- Визуальная обратная связь на действия

---

## 4. Архитектура системы

### 4.1 Высокоуровневая архитектура

```
┌─────────────────────────────────────────────────────┐
│                  BatteryManager App                  │
│  ┌────────────────────────────────────────────────┐ │
│  │            SwiftUI Views Layer                  │ │
│  │  MenuBarPopover │ Charts │ Settings            │ │
│  └─────────────────┬──────────────────────────────┘ │
│                    │                                 │
│  ┌─────────────────┴──────────────────────────────┐ │
│  │         ObservableObject Services              │ │
│  │  BatteryService │HistoryManager │ Monitors    │ │
│  └─────────────────┬──────────────────────────────┘ │
│                    │                                 │
│  ┌─────────────────┴──────────────────────────────┐ │
│  │              Platform Layer                     │ │
│  │  IOKitBridge │ XPCClient │ SQLiteManager       │ │
│  └─────────────────┬──────────────────────────────┘ │
└────────────────────┼──────────────────────────────┘
                     │ XPC
        ┌────────────┴────────────┐
        │  Privileged Helper Tool  │
        │  (runs with root)        │
        │  ChargeControlDaemon     │
        └──────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │      IOKit / Kernel     │
        │  Battery Management     │
        └─────────────────────────┘
```

### 4.2 Компоненты

**Main App (BatteryManager.app)**
- SwiftUI views
- ObservableObject services
- IOKit data reading
- SQLite history storage
- XPC client для связи с helper

**Privileged Helper (com.mediumwell.BatteryManager.helper)**
- XPC service с root привилегиями
- Управление зарядкой через IOKit
- Установка лимитов
- Принудительный разряд/заряд

**SQLite Database**
- Файл: `~/Library/Application Support/BatteryManager/history.db`
- Таблицы:
  - `battery_history`: временные ряды данных
  - `settings`: пользовательские настройки

### 4.3 Потоки данных

**Чтение данных батареи:**
```
Timer (2s) → BatteryService.update()
           → IOKitBridge.getBatteryInfo()
           → IOKit APIs
           → BatteryData struct
           → @Published properties
           → SwiftUI View updates
```

**Установка лимита:**
```
User slides → ChargeControlView
           → ChargeControlService.setLimit(80)
           → XPCClient.sendMessage()
           → PrivilegedHelper receives
           → IOKit set charge limit
           → Response → UI confirmation
```

**Запись истории:**
```
Timer (60s) → HistoryManager.record()
            → Current BatteryData
            → SQLite INSERT
            → Cleanup old data (>24h)
```

**Мониторинг температуры:**
```
BatteryService update → TemperatureMonitor.check()
                      → Compare with thresholds
                      → If > 40°C:
                          ├→ Show notification
                          ├→ Update dock icon
                          ├→ ChargeControlService.stopCharging()
                          └→ Log event
```

---

## 5. Модели данных

### 5.1 BatteryData

```swift
struct BatteryData: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    
    // Charge
    let currentCharge: Int           // 0-100%
    let maxCapacity: Int             // mAh
    let designCapacity: Int          // mAh
    let currentCapacityMah: Int      // mAh
    
    // State
    let isCharging: Bool
    let isPluggedIn: Bool
    let timeRemaining: Int?          // minutes, nil if charging
    
    // Power
    let powerDraw: Double            // Watts, negative when discharging
    let voltage: Double              // Volts
    let amperage: Double             // Amps
    
    // Temperature
    let temperature: Double          // Celsius
    
    // Health
    let cycleCount: Int
    let healthPercentage: Int        // 0-100%
    let condition: BatteryCondition  // enum
    
    // Computed
    var batteryToSystemPower: (battery: Double, system: Double) {
        // Calculate distribution
    }
}

enum BatteryCondition: String, Codable {
    case normal = "Normal"
    case replaceSoon = "Replace Soon"
    case serviceBattery = "Service Battery"
    case unknown = "Unknown"
}
```

### 5.2 BatterySettings

```swift
struct BatterySettings: Codable {
    var chargeLimit: Int = 80           // 20-100%
    var isForcingDischarge: Bool = false
    var isForcingCharge: Bool = false
    
    // Notifications
    var soundEnabled: Bool = true
    var notificationsEnabled: Bool = true
    
    // Temperature thresholds
    var warningTemp: Double = 35.0      // °C
    var criticalTemp: Double = 40.0     // °C
    
    // UI
    var selectedTab: Tab = .status
    var launchAtLogin: Bool = false
    var updateInterval: TimeInterval = 2.0
    
    enum Tab: String, Codable {
        case status, charts, health
    }
}
```

### 5.3 BatteryHistoryRecord

```swift
struct BatteryHistoryRecord: Codable {
    let timestamp: Int               // Unix timestamp
    let chargePercent: Int
    let temperature: Double
    let powerDraw: Double
    let isCharging: Bool
}
```

---

## 6. Технологический стек

### 6.1 Основные технологии

- **Язык:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Graphics:** Swift Charts (для графиков)
- **Database:** SQLite (через GRDB.swift)
- **IPC:** XPC (межпроцессная коммуникация)
- **System APIs:** IOKit, SMJobBless

### 6.2 Зависимости

**Прямые зависимости:**
- GRDB.swift: SQLite ORM
- (опционально) LaunchAtLogin: для автозапуска

**Системные фреймворки:**
- IOKit
- ServiceManagement (для SMJobBless)
- UserNotifications
- AppKit (для menu bar)

### 6.3 Инструменты разработки

- Xcode 15+
- Swift Package Manager
- Git
- xcrun для подписи кода

---

## 7. Интерфейсные спецификации

### 7.1 IOKit API (чтение батареи)

**Основные функции:**
```c
IOServiceGetMatchingService()
IORegistryEntryCreateCFProperties()
IOObjectRelease()
```

**Читаемые ключи:**
- `CurrentCapacity` → currentCharge
- `MaxCapacity` → maxCapacity
- `DesignCapacity` → designCapacity
- `IsCharging` → isCharging
- `ExternalConnected` → isPluggedIn
- `InstantAmperage` → amperage
- `Voltage` → voltage
- `Temperature` → temperature
- `CycleCount` → cycleCount
- `AppleRawBatteryState` → condition

### 7.2 XPC Protocol (связь с helper)

```swift
@objc protocol ChargeControlProtocol {
    func setChargeLimit(_ percent: Int, reply: @escaping (Bool, Error?) -> Void)
    func getChargeLimit(reply: @escaping (Int?, Error?) -> Void)
    func forceDischarge(_ enable: Bool, reply: @escaping (Bool, Error?) -> Void)
    func allowCharge(_ enable: Bool, reply: @escaping (Bool, Error?) -> Void)
    func getHelperVersion(reply: @escaping (String) -> Void)
}
```

### 7.3 SQLite Schema

```sql
CREATE TABLE IF NOT EXISTS battery_history (
    timestamp INTEGER PRIMARY KEY,
    charge_percent INTEGER NOT NULL,
    temperature REAL NOT NULL,
    power_draw REAL NOT NULL,
    is_charging INTEGER NOT NULL,
    CHECK (charge_percent >= 0 AND charge_percent <= 100),
    CHECK (temperature >= -10.0 AND temperature <= 100.0)
);

CREATE INDEX idx_timestamp ON battery_history(timestamp DESC);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

---

## 8. Безопасность и привилегии

### 8.1 SMJobBless процесс

1. Main app запускает установку helper через `SMJobBless()`
2. Система запрашивает пароль администратора
3. Helper устанавливается в `/Library/PrivilegedHelperTools/`
4. Helper регистрируется как LaunchDaemon
5. Main app коммуницирует через XPC

### 8.2 Code Signing

**Main App:**
- Bundle ID: `com.mediumwell.BatteryManager`
- Entitlements:
  - `com.apple.security.app-sandbox` (NO для IOKit доступа)
  - `com.apple.security.device.usb` (для IOKit)

**Privileged Helper:**
- Bundle ID: `com.mediumwell.BatteryManager.helper`
- Embedded в main app bundle
- Подписан тем же сертификатом

### 8.3 Права доступа

**Main App:**
- Чтение IOKit registry (батарея)
- Запись в ~/Library/Application Support
- Доступ к XPC

**Privileged Helper:**
- Запись в IOKit registry (управление зарядкой)
- Минимальные привилегии (principle of least privilege)

---

## 9. Обработка ошибок

### 9.1 Категории ошибок

**IOKit Errors:**
- Батарея не найдена → показать уведомление
- Некорректные данные → использовать последние валидные
- Отказ в доступе → работать в режиме чтения (без управления)

**XPC Errors:**
- Helper не установлен → предложить установку
- Timeout → повторить запрос
- Connection interrupted → переподключиться

**SQLite Errors:**
- База повреждена → пересоздать
- Диск заполнен → очистить старые данные
- Ошибка записи → пропустить, продолжить

**UI Errors:**
- Невалидный input → показать подсказку
- Окно не открывается → перезапустить app

### 9.2 Логирование

**Уровни:**
- Debug: детальные данные IOKit
- Info: события пользователя
- Warning: некритичные ошибки
- Error: критичные ошибки
- Fatal: краш

**Destination:**
- Console.app (os_log)
- Опционально: файл в ~/Library/Logs/BatteryManager/

---

## 10. Тестирование

### 10.1 Unit тесты

- BatteryService: мок данных IOKit
- HistoryManager: in-memory SQLite
- TemperatureMonitor: граничные условия
- ChargeControlService: мок XPC

### 10.2 Integration тесты

- IOKit чтение → BatteryService → UI update
- User action → XPC → Helper → IOKit
- Timer → History recording → SQLite

### 10.3 UI тесты

- Открытие окна
- Переключение вкладок
- Установка лимита через слайдер
- Отображение графиков

### 10.4 Manual тесты

- Реальное управление зарядкой
- Тестирование на разных моделях Mac
- Перегрев (сложно автоматизировать)
- Переход в сон/пробуждение

---

## 11. Развертывание и распространение

### 11.1 Сборка

```bash
# Build release
xcodebuild -scheme BatteryManager \
           -configuration Release \
           -archivePath ./build/BatteryManager.xcarchive \
           archive

# Export app
xcodebuild -exportArchive \
           -archivePath ./build/BatteryManager.xcarchive \
           -exportPath ./dist \
           -exportOptionsPlist ExportOptions.plist
```

### 11.2 Подпись и нотаризация

```bash
# Подпись
codesign --force --deep --sign "Developer ID Application: ..." \
         BatteryManager.app

# Нотаризация через Apple
xcrun notarytool submit BatteryManager.zip \
      --apple-id "..." \
      --password "..." \
      --team-id "..."

# Staple ticket
xcrun stapler staple BatteryManager.app
```

### 11.3 Распространение

**Опции:**
1. **GitHub Releases:** DMG файл с app
2. **Homebrew Cask:** формула установки
3. **Прямая загрузка:** с website

**Формат распространения:**
- DMG образ с drag-and-drop установкой
- Размер: ~5-10 MB
- Включает README и LICENSE

---

## 12. Обслуживание и обновления

### 12.1 Проверка обновлений

- Опционально: Sparkle framework для автообновлений
- Проверка при запуске (раз в день)
- Уведомление о доступной версии

### 12.2 Миграция данных

**При обновлении:**
- Проверка версии SQLite схемы
- Миграция при необходимости
- Сохранение старых настроек

### 12.3 Телеметрия

**Опционально (с согласия пользователя):**
- Анонимная статистика использования
- Отчеты о крашах
- Популярные функции

---

## 13. Ограничения и известные проблемы

### 13.1 Технические ограничения

1. **Управление зарядкой:**
   - Зависит от поддержки конкретной модели Mac
   - Может не работать на старых Intel Mac
   - Apple может изменить API в будущих версиях macOS

2. **Точность данных:**
   - IOKit предоставляет приблизительные значения
   - Температура может иметь погрешность ±2°C
   - Оставшееся время - оценка системы

3. **Производительность:**
   - Частое чтение IOKit влияет на энергопотребление
   - Графики за большие периоды (>24ч) замедляют UI

### 13.2 Известные баги

- Нет на момент v0.1.0

### 13.3 Будущие улучшения

**v1.1:**
- Расписание зарядки (заряд до 100% к определенному времени)
- Экспорт истории в CSV

**v1.2:**
- Калибровка батареи
- Уведомления о достижении лимита

**v2.0:**
- Поддержка нескольких профилей
- Интеграция с Shortcuts
- Виджеты для macOS

---

## 14. Глоссарий

- **IOKit:** низкоуровневый фреймворк macOS для доступа к устройствам
- **SMJobBless:** механизм установки privileged helper tools
- **XPC:** Inter-Process Communication в macOS
- **Liquid Glass:** дизайн-стиль с полупрозрачностью и blur эффектами
- **Cycle Count:** количество полных циклов заряда/разряда батареи
- **Design Capacity:** первоначальная емкость батареи при производстве
- **Max Capacity:** текущая максимальная емкость (уменьшается со временем)

---

## 15. Контакты и поддержка

- **Repository:** https://github.com/mediumwell/BatteryManager
- **Issues:** https://github.com/mediumwell/BatteryManager/issues
- **Email:** support@mediumwell.dev (если создадим)
- **License:** MIT

---

**Версия спецификации:** 1.0  
**Дата:** 2024-10-04  
**Автор:** MediumWell Team
