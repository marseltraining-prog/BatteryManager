# BatteryManager Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add battery history (SQLite), 24h charts, charge-limit UI, overheat protection, dock icon with percentage, and health view to the working MVP.

**Architecture:** HistoryStore on raw SQLite3 C API (no external deps — SwiftPM deps unusable in this environment), HistoryRecorder ties BatteryService to the store, Swift Charts views read history, TemperatureMonitor drives two-level overheat protection with a ChargeController seam for the future privileged helper, dock tile via NSHostingView.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Charts, SQLite3 (system), UserNotifications, AppKit dock tile

**Spec:** `SPECIFICATION.md` (FR-006..FR-016), `DESIGN.md`

## Global Constraints

- macOS 13 Ventura minimum; Swift 5.9+
- Bundle ID: com.mediumwell.BatteryManager
- UI text: Russian primary
- Update interval: 2s UI, 60s history; history retention 24h
- Temperature thresholds: warning 35°C, critical 40°C (per spec FR-010)
- Charge limit range: 20-100% (spec FR-001)
- Tests run via `scripts/run-tests.sh` (Swift Testing, no Xcode/SwiftPM)

## Review Focus

- **SQLite disk full during history write:** catch write error, prune oldest 50%, retry once
- **Corrupt DB file:** detect on open, recreate, continue with empty history
- **Temperature nil (no sensor):** monitor reports .normal, no notifications, no crash
- **History gaps (sleep):** charts must render gaps without connecting across them; recorder skips writes while no data
- **Dock icon on LSUIElement app:** activation policy must switch to .regular or dock tile is absent

---

## Task 1: HistoryStore (SQLite)

**Files:**
- Create: `Sources/MediumWellBatteryCore/History/HistoryRecord.swift`
- Create: `Sources/MediumWellBatteryCore/History/HistoryStore.swift`
- Create: `Tests/MediumWellBatteryCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces: `struct HistoryRecord: Equatable, Sendable` (timestamp: Date, chargePercent: Int, temperature: Double?, powerWatts: Double, adapterWatts: Double?, systemPowerWatts: Double?, batteryPowerWatts: Double?, isCharging: Bool); `final class HistoryStore` with `init(databaseURL: URL) throws`, `func record(_ info: BatteryInfo, at: Date) throws`, `func records(since: Date) throws -> [HistoryRecord]`, `func prune(olderThan: TimeInterval, from: Date) throws`, `static func defaultDatabaseURL() -> URL`

- [ ] **Step 1: Write failing tests** (roundtrip, ordering, nil temperature, prune, corrupt DB recreate)
- [ ] **Step 2: Run — expect compile failure (types missing)**
- [ ] **Step 3: Implement HistoryRecord + HistoryStore** (sqlite3_open_v2 with CREATE|READWRITE, WAL; CREATE TABLE IF NOT EXISTS battery_history; corrupt DB → delete file, recreate)
- [ ] **Step 4: Run — expect pass**
- [ ] **Step 5: Commit + tag v0.6.0**

## Task 2: HistoryRecorder

**Files:**
- Create: `Sources/MediumWellBatteryCore/History/HistoryRecorder.swift`
- Create: `Tests/MediumWellBatteryCoreTests/HistoryRecorderTests.swift`

**Interfaces:**
- Consumes: `BatteryReading`, `HistoryStore`
- Produces: `final class HistoryRecorder` with `init(reader:store:interval:retention:)`, `start()/stop()`, `func recordNow() throws`

- [ ] **Step 1: Failing tests** (recordNow writes a row; nil reader result writes nothing; start/stop polls on interval like BatteryService)
- [ ] **Step 2: Run — fail**
- [ ] **Step 3: Implement** (DispatchSourceTimer pattern from BatteryService)
- [ ] **Step 4: Run — pass**
- [ ] **Step 5: Commit + tag v0.7.0**

## Task 3: Charts (Swift Charts)

**Files:**
- Create: `Sources/MediumWellBatteryCore/History/ChartData.swift`
- Create: `App/Views/ChartsView.swift`
- Create: `Tests/MediumWellBatteryCoreTests/ChartDataTests.swift`

**Interfaces:**
- Consumes: `[HistoryRecord]`
- Produces: `struct ChartData` with `static func points(from: [HistoryRecord]) -> (charge: [ChargePoint], temperature: [TempPoint], power: [PowerPoint])`; `struct ChartsView: View` (3 charts, 24h, Liquid Glass cards)

- [ ] **Step 1: Failing tests** (mapping preserves order/values; nil temperature → excluded point; empty input → empty arrays)
- [ ] **Step 2: Run — fail**
- [ ] **Step 3: Implement ChartData + ChartsView** (LineMark + gradient fill, per DESIGN.md colors)
- [ ] **Step 4: Run — pass**
- [ ] **Step 5: Commit + tag v0.8.0**

## Task 4: TemperatureMonitor (overheat protection)

**Files:**
- Create: `Sources/MediumWellBatteryCore/Monitoring/TemperatureMonitor.swift`
- Create: `Tests/MediumWellBatteryCoreTests/TemperatureMonitorTests.swift`

**Interfaces:**
- Consumes: `BatteryReading`, `TemperatureState`
- Produces: `protocol ChargeController: Sendable { func setChargingAllowed(_ allowed: Bool) }`; `final class TemperatureMonitor` with `init(reader:controller:)`, `@Published state: TemperatureState`, `func evaluate()`, callback `onStateChange: ((TemperatureState, Double?) -> Void)?`

- [ ] **Step 1: Failing tests** (nil temp → .normal no callback; 34.9→.normal; 35→.warning callback; 40.1→.critical callback + controller.setChargingAllowed(false); back to 30 → .normal + controller.setChargingAllowed(true))
- [ ] **Step 2: Run — fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run — pass**
- [ ] **Step 5: Commit + tag v0.9.0**

## Task 5: Dock icon with percentage

**Files:**
- Create: `App/Dock/DockIconManager.swift`
- Modify: `App/BatteryManagerApp.swift` (attach DockIconManager, activation policy .regular)
- Modify: `scripts/build-app.sh` (LSUIElement false)

**Interfaces:**
- Consumes: `BatteryService.currentData`, DesignTokens
- Produces: `final class DockIconManager` (NSHostingView on NSApplication.shared.dockTile, colors per status: charging green / discharging white / warning amber+⚠️ / critical red+🔥)

- [ ] **Step 1: Implement** (AppKit layer — no unit tests possible; compile-check)
- [ ] **Step 2: Build app, launch, verify process alive**
- [ ] **Step 3: Commit + tag v0.10.0**

## Task 6: Health view + tabs

**Files:**
- Create: `App/Views/HealthView.swift`
- Modify: `App/Views/MenuBarPopover.swift` (tab switcher: Статус / Графики / Здоровье)
- Modify: `App/BatteryManagerApp.swift` (wire HistoryRecorder + TemperatureMonitor)

**Interfaces:**
- Consumes: BatteryInfo (health fields), HistoryStore, ChartsView, StatusView
- Produces: `struct HealthView: View` (проектная/максимальная ёмкость, здоровье %, циклы, состояние); popover tabs

- [ ] **Step 1: Implement HealthView + tabs + wiring**
- [ ] **Step 2: Build app, launch, verify alive; run full test suite**
- [ ] **Step 3: Commit + tag v1.0.0-beta**

---

**Deferred to Phase 3 (needs Xcode/signing or root):** privileged helper (SMJobBless), real charge control via IOKit, XPC, notifications polish, settings UI.
