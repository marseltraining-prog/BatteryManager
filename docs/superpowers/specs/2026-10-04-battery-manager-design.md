# BatteryManager for macOS: Design Specification

**Status:** Draft for user review  
**Version target:** 0.1.0 (feasibility prototype)  
**Date:** 2026-10-04

## 1. Purpose and agreed scope

Build a lightweight native macOS battery utility inspired by the user's AlDente references, with a modern Liquid Glass visual treatment. The first supported target is the user's MacBook; model, processor, and macOS version must be recorded before choosing or enabling any charge-control mechanism.

The initial product aims to:

- Show battery charge, charging/discharging state, and battery health.
- Let the user configure a charge ceiling and, only where verified control is available, enforce it.
- Show adapter input, battery charging power, and estimated system consumption when the hardware exposes sufficient measurements.
- Plot charge, temperature, and power history over 24 hours.
- Warn about high battery temperature and stop charging at a configurable critical threshold only when the app can reliably control charging.
- Present a Dock icon with charge percentage and state/thermal indicator.

This is a reduced AlDente-like utility. Scheduling, calibration, advanced analytics, and unrelated system optimization are out of scope.

## 2. Product experience

### 2.1 Main window

A compact, native SwiftUI window is opened from the Dock app. It contains three destinations: **Status**, **Charts**, and **Battery Health**. It should remain usable at compact window sizes and support scrolling when content does not fit.

**Status** contains:

- Current charge percentage and charging/discharging/idle state.
- Charge ceiling control (20-100%, step 1%, default 80%).
- Explicit **Allow charging** and **Discharge** controls, with confirmation for actions that override the normal limit.
- Power-flow visualization: adapter input, power into/out of the battery, and estimated system use. Unknown or unavailable readings are labeled as such, never represented as zero.
- A concise temperature/protection state and last update time.

**Charts** contains three separate, side-by-side charts when the window width permits, otherwise stacked:

- Battery charge (%).
- Battery temperature (°C).
- Power (W), with separate series only where source measurements make them meaningful.

Each chart spans the rolling previous 24 hours, has readable axes and units, and displays gaps for unavailable samples rather than interpolating misleading values.

**Battery Health** shows design capacity, full-charge capacity, macOS-reported capacity/state, and cycle count where available. Values not exposed by the system are shown as unavailable. Health percentages are calculated only from valid capacities and clearly identify their source.

### 2.2 Dock behavior

The application has a regular Dock icon and a normal resizable window; selecting the Dock icon opens or brings the window forward. The icon displays the current percentage and changes its accent by state: green while charging, neutral while discharging, amber at warning temperature, and red with a heat-warning glyph at critical temperature. Icon updates are event/data driven and throttled to avoid unnecessary redraws.

A separate always-on-top Dock popover is not part of the first version: standard macOS Dock applications open windows, not anchored popovers. The visual reference is used for the status layout inside the app window. A menu-bar extra can be considered later if the user wants a true popover.

### 2.3 Liquid Glass visual direction

Use native SwiftUI materials and platform controls as the foundation, with restrained translucent surfaces, subtle highlights, thin separators, and state colors. Maintain legible contrast and respect light/dark appearance, Reduce Motion, and accessibility sizing. Avoid imitating Apple's private visual effects or relying on web-only `backdrop-filter`; the HTML mockup is a visual reference, not production UI code.

## 3. Temperature policy and safety

Initial suggested defaults, subject to confirmation against the battery temperature sensor and model:

- **Warning:** 38°C sustained for 2 minutes. Notify the user and show amber state.
- **Critical:** 42°C sustained for 30 seconds. Show red state and request charge stop if verified control is available.
- **Recovery hysteresis:** clear warning below 36°C; clear critical below 39°C, to prevent rapid toggling.

These are conservative application policy thresholds, not Apple-published battery safety limits. Apple guidance for ambient operating conditions must not be misrepresented as a battery-cell temperature limit. The app cannot guarantee thermal protection if the sensor is missing, stale, or charge control is unavailable. In those cases it must report monitoring/control unavailable and never imply that charging was stopped. macOS and the device's built-in thermal management remain authoritative.

## 4. Technical architecture

- **Language/UI:** Swift and SwiftUI; native Charts framework where supported by the selected minimum macOS version.
- **Minimum OS:** choose only after confirming deployment needs. Initial proposal is macOS 13+, but APIs and visual treatments must be capability-gated.
- **BatteryTelemetryProvider:** read-only adapter around supported system battery data sources. Expose normalized values with source, timestamp, and availability; do not assume every sensor or power-flow value exists.
- **ChargeControlProvider:** isolated interface for applying/removing a charge limit and requesting charge/discharge. No privileged helper is implemented until a feasibility spike demonstrates a supported, reviewable mechanism for the target hardware/OS. A helper, if required, uses a narrow allow-listed IPC protocol and least privilege; it never accepts arbitrary shell commands.
- **ThermalProtectionService:** evaluates fresh telemetry, applies thresholds/hysteresis, notifies, and requests stop only through a verified ChargeControlProvider.
- **HistoryStore:** local-only rolling history, samples once per minute, prunes data older than 24 hours, and tolerates app restarts. The storage backend may start as a small file/SwiftData store; SQLite is not a requirement absent a demonstrated need.
- **AppModel / Views:** publish state to SwiftUI; separate display formatting from system access.

The process should not poll at two-second intervals by default. Use a modest cadence (proposed 10 seconds for live status and 60 seconds for history), adapting to supported event notifications and power impact.

## 5. Data model and availability

A telemetry sample includes timestamp, charge percentage, charging state, temperature (optional), battery current/voltage or power (optional), adapter power (optional), capacities (optional), cycles (optional), and a source/quality marker. Derived system consumption is shown only when input and battery power are concurrently available and sign conventions are validated; it is labeled as an estimate. Missing measurements are first-class states.

The displayed health rows follow the supplied AlDente screenshot. Design capacity, maximum capacity, and macOS-reported capacity may be the same underlying value on some Macs; the UI must not imply independent measurements when the source does not distinguish them.

## 6. Permissions, privacy, and failure handling

- Read-only monitoring requires no administrator password unless the selected supported source explicitly requires it.
- Charge control must use a macOS-approved, narrowly scoped authorization mechanism for the chosen deployment target. Do not instruct users to disable System Integrity Protection or lower system security.
- Explain why any privileged helper is needed and provide explicit opt-in, status, and uninstall behavior.
- Store history locally; no telemetry uploads or analytics in the first version.
- On permission denial, unsupported hardware, stale data, helper failure, or app launch before data is ready, keep the UI operational and show a clear unavailable/error state.
- On helper communication failure, do not claim a charge limit or stop action succeeded; display the last confirmed state and notify the user.

## 7. Packaging and versioning

- Git repository is local at `BatteryManager`; remote GitHub publication requires the user's GitHub identity/authentication and confirmation of the repository name and visibility.
- Use SemVer. Begin at `0.1.0` for the feasibility prototype; increment minor for user-visible features and patch for compatible fixes. Tag releases as `vX.Y.Z` and keep a concise `CHANGELOG.md`.
- Conventional Commits are used. Do not claim changes have been pushed to GitHub until a remote exists and push succeeds.

## 8. Delivery phases

1. **0.1.0 Feasibility prototype:** record target Mac/macOS; verify available charge, health, temperature, adapter, and battery-power readings; probe whether safe charge control is possible. Produce a capability report and read-only telemetry sample. No automatic charging intervention.
2. **0.2.0 Read-only app:** native window, Dock percentage icon, status and battery-health views, honest unavailable states.
3. **0.3.0 History and charts:** local rolling 24-hour samples and three charts.
4. **0.4.0 Thermal notifications:** configurable warning/critical states and notifications; no automatic stop until charge control is proven.
5. **0.5.0 Verified charge control:** opt-in limit and manual controls through the reviewed mechanism, only for validated hardware/OS combinations.
6. **0.6.0 Thermal stop and polish:** enable automatic stop only on validated combinations, add recovery hysteresis, failure reporting, packaging, and release documentation.

Version numbers are milestones, not promises that every capability will work on every Mac.

## 9. Acceptance criteria

- The app runs as a native macOS app and the Dock icon opens its main window.
- Current charge/state and available health metrics match system-reported values on the target Mac; unavailable values are explicit.
- 24-hour charts plot stored samples with gaps where data is missing and prune older samples.
- Temperature warnings trigger only from a fresh, validated battery-temperature measurement and obey debounce/hysteresis.
- Charge-limit and stop controls report success only after confirmation from the provider; unsupported control is disabled and explained.
- No UI claim suggests that input adapter wattage equals system consumption unless the calculation is supported by valid simultaneous measurements.
- Unit tests cover normalization, missing/stale data, power sign handling, threshold debounce/hysteresis, and history retention.
- A manual validation checklist covers unplugging/reconnecting power, sleep/wake, denied permissions, unsupported sensors, and helper failure.

## 10. Open decisions before implementation

1. Confirm target Mac model/chip and macOS version.
2. Confirm GitHub repository name and public/private visibility before creating a remote.
3. Confirm temperature defaults (38°C warning / 42°C critical) after verifying which battery sensor is available on the target Mac.
4. Confirm whether a normal Dock window is acceptable for v1, with a menu-bar popover deferred.

## References

- Apple, `SMAppService`: https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple, IOKit: https://developer.apple.com/documentation/iokit
- Apple, notebook operating temperature/support guidance: https://support.apple.com/en-us/HT201640

The cited Apple developer pages document platform frameworks and service registration; they do not establish a public API for changing battery charge thresholds. Charge control remains a feasibility gate, not an assumed capability.
