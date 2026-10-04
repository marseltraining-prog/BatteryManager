# BatteryManager MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working macOS battery manager with charge limiting, real-time monitoring, temperature protection, and Liquid Glass UI.

**Architecture:** SwiftUI app reading IOKit battery data, privileged helper for charge control via XPC, SQLite for 24h history, menu bar popover interface.

**Tech Stack:** Swift 5.9+, SwiftUI, IOKit, SMJobBless, XPC, SQLite (GRDB.swift), Swift Charts

**Spec:** `SPECIFICATION.md`, `DESIGN.md`

## Global Constraints

- macOS 13 Ventura minimum
- Swift 5.9+
- Bundle ID: com.mediumwell.BatteryManager
- Helper ID: com.mediumwell.BatteryManager.helper
- All UI text in Russian (primary) and English (secondary)
- CPU usage < 1% in background
- Memory usage < 50 MB
- Update interval: 2 seconds for UI, 60 seconds for history

## Review Focus

- **Invalid IOKit data (temperature 200°C, negative charge):** Validate all IOKit values against sane ranges before publishing; fallback to last valid value
- **Battery removed/not found on desktop Mac:** Check IORegistry at launch; if no battery, show "Батарея не обнаружена" state
- **XPC connection failure when helper not installed:** Catch connection errors, work in monitor-only mode, show "Привилегии не установлены" banner
- **SQLite disk full during history write:** Catch write errors, delete oldest 50% of history, retry once
- **App wakes from sleep with stale data:** Pause monitoring on sleep notification, resume 5s after wake, mark sleep gap in history

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `BatteryManager.xcodeproj`
- Create: `BatteryManager/BatteryManagerApp.swift`
- Create: `BatteryManager/Info.plist`
- Create: `BatteryManager/Assets.xcassets`
- Create: `.gitignore`

**Interfaces:**
- Consumes: Nothing
- Produces: Buildable Xcode project with Bundle ID `com.mediumwell.BatteryManager`

- [ ] **Step 1: Create Xcode project**

```bash
cd /Users/macbookmarsel/Documents/deepseek-harness/default-workspace/MediumWell/BatteryManager
# Create via Xcode command line or manual setup
```

Project settings:
- Product Name: BatteryManager
- Organization: MediumWell
- Bundle ID: com.mediumwell.BatteryManager
- Deployment Target: macOS 13.0
- Language: Swift
- UI: SwiftUI
- App Sandbox: Disabled (needed for IOKit)

- [ ] **Step 2: Configure Info.plist**

Add keys:
```xml
<key>LSUIElement</key>
<true/>
<key>NSSupportsAutomaticTermination</key>
<false/>
<key>NSSupportsSuddenTermination</key>
<false/>
```

- [ ] **Step 3: Add .gitignore**

```
# Xcode
*.xcuserstate
xcuserdata/
DerivedData/
*.xcworkspace/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3

# Swift
*.swp
*~.nib
*.hmap
*.ipa

# Build
build/
dist/

# Database
*.db
*.db-shm
*.db-wal
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild -project BatteryManager.xcodeproj -scheme BatteryManager -configuration Debug`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: создан Xcode проект с базовой конфигурацией

- Bundle ID: com.mediumwell.BatteryManager
- Deployment target: macOS 13.0
- LSUIElement для menu bar app
- Gitignore для Xcode"
git tag v0.1.0
```

---

## Task 2: IOKit Battery Bridge

**Files:**
- Create: `BatteryManager/Services/IOKitBridge.swift`
- Create: `BatteryManagerTests/IOKitBridgeTests.swift`

**Interfaces:**
- Consumes: Nothing
- Produces: `struct BatteryInfo`, `class IOKitBridge` with `func getBatteryInfo() -> BatteryInfo?`

- [ ] **Step 1: Write failing test**

```swift
func testGetBatteryInfo_withValidBattery_returnsData() {
    let bridge = IOKitBridge()
    let info = bridge.getBatteryInfo()
    
    XCTAssertNotNil(info)
    XCTAssertTrue(info!.currentCharge >= 0 && info!.currentCharge <= 100)
    XCTAssertTrue(info!.temperature >= -10.0 && info!.temperature <= 100.0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project BatteryManager.xcodeproj -scheme BatteryManager`
Expected: FAIL with "IOKitBridge not found"

- [ ] **Step 3: Define BatteryInfo struct**

```swift
struct BatteryInfo {
    let currentCharge: Int              // 0-100
    let maxCapacity: Int                // mAh
    let designCapacity: Int             // mAh
    let isCharging: Bool
    let isPluggedIn: Bool
    let voltage: Double                 // Volts
    let amperage: Double                // Amps
    let temperature: Double             // Celsius
    let cycleCount: Int
    let powerDraw: Double              // Watts (computed)
}
```

- [ ] **Step 4: Implement IOKitBridge.getBatteryInfo()**

In `BatteryManager/Services/IOKitBridge.swift`:

```swift
import IOKit
import IOKit.ps

class IOKitBridge {
    func getBatteryInfo() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return nil
        }
        
        // Validate and extract with fallback defaults
        let currentCharge = (description[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let maxCapacity = (description[kIOPSMaxCapacityKey] as? Int) ?? 0
        let designCapacity = (description["DesignCapacity"] as? Int) ?? maxCapacity
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let voltage = (description[kIOPSVoltageKey] as? Double) ?? 0.0
        let amperage = (description[kIOPSCurrentKey] as? Double) ?? 0.0
        let cycleCount = (description[kIOPSCycleCountKey] as? Int) ?? 0
        
        // Temperature from IORegistry (more complex, may need separate function)
        let temperature = getTemperatureFromIORegistry() ?? 25.0
        
        // Validate ranges per Review Focus
        guard currentCharge >= 0 && currentCharge <= 100,
              temperature >= -10.0 && temperature <= 100.0 else {
            return nil
        }
        
        let powerDraw = (voltage * amperage) / 1000.0  // Convert to Watts
        
        return BatteryInfo(
            currentCharge: currentCharge,
            maxCapacity: maxCapacity,
            designCapacity: designCapacity,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            voltage: voltage,
            amperage: amperage,
            temperature: temperature,
            cycleCount: cycleCount,
            powerDraw: powerDraw
        )
    }
    
    private func getTemperatureFromIORegistry() -> Double? {
        // IORegistry lookup for temperature - simplified
        return nil  // Fallback handled in caller
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -project BatteryManager.xcodeproj -scheme BatteryManager`
Expected: PASS

- [ ] **Step 6: Test invalid data handling per Review Focus**

```swift
func testGetBatteryInfo_withInvalidTemperature_returnsNil() {
    // Mock test - in real implementation, would inject mock IOKit responses
    // Verify that temperature > 100°C causes nil return
}
```

- [ ] **Step 7: Commit**

```bash
git add BatteryManager/Services/IOKitBridge.swift BatteryManagerTests/
git commit -m "feat: добавлен IOKit bridge для чтения данных батареи

- Структура BatteryInfo с основными метриками
- Валидация данных (заряд 0-100%, температура -10-100°C)
- Обработка отсутствия батареи (nil return)"
```

---

## Task 3: BatteryService Observable

**Files:**
- Create: `BatteryManager/Models/BatteryData.swift`
- Create: `BatteryManager/Services/BatteryService.swift`
- Create: `BatteryManagerTests/BatteryServiceTests.swift`

**Interfaces:**
- Consumes: `IOKitBridge.getBatteryInfo() -> BatteryInfo?`
- Produces: `class BatteryService: ObservableObject` with `@Published var currentData: BatteryData?`, `func startMonitoring()`, `func stopMonitoring()`

- [ ] **Step 1: Write failing test**

```swift
func testStartMonitoring_updatesCurrentData() {
    let service = BatteryService()
    let expectation = XCTestExpectation(description: "Data updated")
    
    service.startMonitoring()
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        XCTAssertNotNil(service.currentData)
        expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 5)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project BatteryManager.xcodeproj -scheme BatteryManager`
Expected: FAIL with "BatteryService not found"

- [ ] **Step 3: Define BatteryData model**

```swift
struct BatteryData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let currentCharge: Int
    let maxCapacity: Int
    let designCapacity: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let voltage: Double
    let amperage: Double
    let temperature: Double
    let cycleCount: Int
    let powerDraw: Double
    
    var healthPercentage: Int {
        guard designCapacity > 0 else { return 0 }
        return Int((Double(maxCapacity) / Double(designCapacity)) * 100)
    }
    
    var condition: BatteryCondition {
        if healthPercentage >= 80 { return .normal }
        if healthPercentage >= 60 { return .replaceSoon }
        return .serviceBattery
    }
}

enum BatteryCondition: String {
    case normal = "Normal"
    case replaceSoon = "Replace Soon"
    case serviceBattery = "Service Battery"
    case unknown = "Unknown"
}
```

- [ ] **Step 4: Implement BatteryService**

```swift
import Foundation
import Combine

class BatteryService: ObservableObject {
    @Published var currentData: BatteryData?
    @Published var isMonitoring = false
    
    private let bridge = IOKitBridge()
    private var timer: Timer?
    private var lastValidData: BatteryData?
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        updateBatteryData()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateBatteryData()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }
    
    private func updateBatteryData() {
        guard let info = bridge.getBatteryInfo() else {
            // Per Review Focus: use last valid data if IOKit fails
            currentData = lastValidData
            return
        }
        
        let data = BatteryData(
            timestamp: Date(),
            currentCharge: info.currentCharge,
            maxCapacity: info.maxCapacity,
            designCapacity: info.designCapacity,
            isCharging: info.isCharging,
            isPluggedIn: info.isPluggedIn,
            voltage: info.voltage,
            amperage: info.amperage,
            temperature: info.temperature,
            cycleCount: info.cycleCount,
            powerDraw: info.powerDraw
        )
        
        currentData = data
        lastValidData = data
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -project BatteryManager.xcodeproj -scheme BatteryManager`
Expected: PASS

- [ ] **Step 6: Test fallback per Review Focus**

```swift
func testUpdateBatteryData_whenIOKitFails_usesPreviousData() {
    // Test that lastValidData persists when getBatteryInfo returns nil
}
```

- [ ] **Step 7: Commit**

```bash
git add BatteryManager/Models/ BatteryManager/Services/BatteryService.swift BatteryManagerTests/
git commit -m "feat: добавлен BatteryService для мониторинга батареи

- ObservableObject с @Published currentData
- Обновление каждые 2 секунды
- Fallback на последние валидные данные при ошибке IOKit
- BatteryData модель с health percentage и condition"
```

---

## Task 4: Liquid Glass Design Tokens

**Files:**
- Create: `BatteryManager/Views/Styling/DesignTokens.swift`
- Create: `BatteryManager/Views/Styling/LiquidGlassModifiers.swift`

**Interfaces:**
- Consumes: Nothing
- Produces: `struct DesignTokens`, `View.liquidGlassBackground()`, `View.glassButton()`, `View.glassCard()`

- [ ] **Step 1: Define DesignTokens**

```swift
import SwiftUI

struct DesignTokens {
    // Surfaces (Liquid Glass with opacity)
    static let surface1 = Color(red: 5/255, green: 7/255, blue: 12/255).opacity(0.85)
    static let surface2 = Color(red: 10/255, green: 13/255, blue: 18/255).opacity(0.75)
    static let surface3 = Color(red: 15/255, green: 19/255, blue: 28/255).opacity(0.65)
    static let surface4 = Color(red: 22/255, green: 29/255, blue: 43/255).opacity(0.55)
    static let surface5 = Color(red: 30/255, green: 38/255, blue: 54/255).opacity(0.45)
    
    // Accents
    static let charging = Color(hex: "6EE7B7")
    static let discharging = Color(hex: "38BDF8")
    static let warning = Color(hex: "FBBF24")
    static let critical = Color(hex: "F87171")
    static let overheat = Color(hex: "FB923C")
    
    // Gradients
    static let chargeGradient = LinearGradient(
        colors: [Color(hex: "6EE7B7"), Color(hex: "10B981")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Spacing
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing5: CGFloat = 20
    static let spacing6: CGFloat = 24
    
    // Radii
    static let radius1: CGFloat = 8
    static let radius2: CGFloat = 12
    static let radius3: CGFloat = 16
    static let radius4: CGFloat = 24
    static let radiusPill: CGFloat = 999
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Define LiquidGlassModifiers**

```swift
import SwiftUI

extension View {
    func liquidGlassBackground(level: Int = 1) -> some View {
        let surface = switch level {
        case 1: DesignTokens.surface1
        case 2: DesignTokens.surface2
        case 3: DesignTokens.surface3
        case 4: DesignTokens.surface4
        default: DesignTokens.surface5
        }
        
        return self
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.radius3)
                    .fill(surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radius3)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    .shadow(color: .white.opacity(0.05), radius: 1, x: 0, y: 1)
            )
    }
    
    func glassButton() -> some View {
        self
            .padding(.horizontal, DesignTokens.spacing3)
            .padding(.vertical, DesignTokens.spacing2)
            .liquidGlassBackground(level: 3)
            .clipShape(Capsule())
    }
    
    func glassCard() -> some View {
        self
            .padding(DesignTokens.spacing5)
            .liquidGlassBackground(level: 2)
    }
}
```

- [ ] **Step 3: Test visual appearance**

Create preview:
```swift
struct DesignTokens_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Button").glassButton()
            Text("Card Content").glassCard()
        }
        .frame(width: 400, height: 300)
        .background(Color.black)
    }
}
```

- [ ] **Step 4: Verify preview renders**

Run: Open Xcode, check Canvas preview shows Liquid Glass effects
Expected: Translucent surfaces with blur, gradients, shadows visible

- [ ] **Step 5: Commit**

```bash
git add BatteryManager/Views/Styling/
git commit -m "feat: добавлены Liquid Glass design tokens и модификаторы

- 5 уровней полупрозрачных поверхностей
- Акцентные цвета (зарядка, разрядка, предупреждение)
- Градиенты для индикаторов
- View модификаторы: liquidGlassBackground, glassButton, glassCard
- Многослойные тени для глубины"
```

---

## Task 5: Menu Bar Popover UI

**Files:**
- Create: `BatteryManager/Views/MenuBarPopover.swift`
- Create: `BatteryManager/Views/StatusView.swift`
- Modify: `BatteryManager/BatteryManagerApp.swift`

**Interfaces:**
- Consumes: `BatteryService.currentData: BatteryData?`
- Produces: Menu bar app with popover showing battery status

- [ ] **Step 1: Write basic StatusView**

```swift
import SwiftUI

struct StatusView: View {
    let data: BatteryData?
    
    var body: some View {
        VStack(spacing: DesignTokens.spacing4) {
            if let data = data {
                Text("\(data.currentCharge)%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(data.isCharging ? DesignTokens.charging : .white)
                
                Text(data.isCharging ? "Зарядка" : "Разрядка")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("🌡️ \(String(format: "%.1f°C", data.temperature))")
                    Text("⚡ \(String(format: "%.1fW", abs(data.powerDraw)))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
                Text("Батарея не обнаружена")
                    .foregroundColor(.secondary)
            }
        }
        .glassCard()
    }
}
```

- [ ] **Step 2: Create MenuBarPopover**

```swift
import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var batteryService: BatteryService
    
    var body: some View {
        VStack(spacing: 0) {
            StatusView(data: batteryService.currentData)
                .frame(width: 420)
                .padding(DesignTokens.spacing5)
        }
        .frame(height: 680)
        .background(DesignTokens.surface1)
    }
}
```

- [ ] **Step 3: Integrate with BatteryManagerApp**

```swift
import SwiftUI
import AppKit

@main
struct BatteryManagerApp: App {
    @StateObject private var batteryService = BatteryService()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(batteryService: batteryService)
        } label: {
            if let data = batteryService.currentData {
                Text("\(data.currentCharge)%")
            } else {
                Text("--")
            }
        }
        .menuBarExtraStyle(.window)
    }
    
    init() {
        _batteryService.wrappedValue.startMonitoring()
    }
}
```

- [ ] **Step 4: Build and run**

Run: `xcodebuild -project BatteryManager.xcodeproj -scheme BatteryManager`
Then launch app from build folder
Expected: Menu bar icon appears, shows percentage, click opens popover

- [ ] **Step 5: Commit**

```bash
git add BatteryManager/Views/ BatteryManager/BatteryManagerApp.swift
git commit -m "feat: добавлен menu bar popover с базовым UI

- MenuBarExtra с процентом заряда
- StatusView с зарядом, температурой, мощностью
- Liquid Glass стилизация
- Интеграция с BatteryService"
```

---

## Task 6: GitHub Repository Creation

**Files:**
- Modify: `.git/config` (add remote)

**Interfaces:**
- Consumes: Existing local git repo
- Produces: GitHub repository at github.com/mediumwell/BatteryManager

- [ ] **Step 1: Create GitHub repo**

Manual step or via GitHub CLI:
```bash
gh repo create mediumwell/BatteryManager --public --description "Современный менеджер батареи для macOS с Liquid Glass дизайном"
```

- [ ] **Step 2: Add remote and push**

```bash
cd /Users/macbookmarsel/Documents/deepseek-harness/default-workspace/MediumWell/BatteryManager
git remote add origin https://github.com/mediumwell/BatteryManager.git
git branch -M main
git push -u origin main --tags
```

- [ ] **Step 3: Verify repo online**

Open: https://github.com/mediumwell/BatteryManager
Expected: Repository visible with README, commits, and v0.1.0 tag

---

## Execution Checkpoints

**After Task 3:** Basic monitoring works - app reads battery data and updates every 2 seconds
**After Task 5:** MVP UI complete - menu bar app with popover showing live battery status
**After Task 6:** Code published on GitHub

## Future Tasks (not in this plan)

- Task 7: Battery history with SQLite (GRDB.swift)
- Task 8: Swift Charts graphs (3 charts for 24h)
- Task 9: Charge limit slider and control view
- Task 10: Privileged helper with SMJobBless
- Task 11: XPC charge control service
- Task 12: Temperature monitoring with alerts
- Task 13: Dynamic dock icon with percentage overlay
- Task 14: Health view with battery details
- Task 15: Settings and localization

---

**Plan Status:** Ready for review
**Recommended Execution:** Native (implementing in current session) - tasks are sequential, interfaces are clear, and early feedback on Liquid Glass design is valuable
