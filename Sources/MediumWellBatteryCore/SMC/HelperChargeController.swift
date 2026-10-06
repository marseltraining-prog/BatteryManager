import Foundation

/// Управление зарядом через привилегированный helper.
///
/// Запись в SMC требует прав root, поэтому приложение не пишет ключи само,
/// а запускает helper (setuid root, ставится `Установка-Helper.command`).
/// Helper принимает только команды `hold` / `allow` / `status`.
public final class HelperChargeController: ReportingChargeController {
    public static let defaultHelperPath =
        "/Library/PrivilegedHelperTools/com.mediumwell.BatteryManager.helper"

    private let helperPath: String

    private let errorLock = NSLock()
    private nonisolated(unsafe) var storedError: ChargeControlError?

    public init(helperPath: String = HelperChargeController.defaultHelperPath) {
        self.helperPath = helperPath
    }

    /// Установлен ли helper. Проверяется каждый раз: его можно поставить
    /// уже после запуска приложения.
    public var isSupported: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
    }

    public var unavailableReason: String? {
        isSupported ? nil
            : "Не установлен helper — запустите «Установка-Helper.command»"
    }

    public var lastError: ChargeControlError? {
        errorLock.lock()
        defer { errorLock.unlock() }
        return storedError
    }

    private func setLastError(_ error: ChargeControlError?) {
        errorLock.lock()
        defer { errorLock.unlock() }
        storedError = error
    }

    public func setChargingAllowed(_ allowed: Bool) {
        guard isSupported else {
            setLastError(.helperNotInstalled)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [allowed ? "allow" : "hold"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            // Вывод helper — одна-две строки, в буфер канала помещается.
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                setLastError(nil)
            } else {
                let text = String(data: output, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                setLastError(.writeFailed(
                    key: "helper",
                    reason: text.isEmpty
                        ? "код завершения \(process.terminationStatus)" : text))
            }
        } catch {
            setLastError(.writeFailed(
                key: "helper", reason: error.localizedDescription))
        }
    }
}
