import Foundation

/// Встроенный лимит заряда macOS (тот же, что в «Настройках → Аккумулятор»).
///
/// Лимит держит сама система: он действует во сне и при закрытом
/// приложении и не требует прав администратора.
public protocol SystemChargeLimiting: Sendable {
    /// Поддерживает ли система лимит заряда на этом Mac.
    var isSupported: Bool { get }
    /// Допустимые значения лимита, % (на macOS 27 — 80, 85, 90, 95, 100).
    var availableLimits: [Int] { get }
    /// Текущий лимит, %; nil — прочитать не удалось.
    func currentLimit() -> Int?
    /// Записывает лимит. Значение должно быть из `availableLimits`.
    func setLimit(_ percent: Int) throws
}

public enum SystemChargeLimitError: Error, Equatable, LocalizedError {
    case unsupported
    case rejected(limit: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Система не поддерживает лимит заряда на этом Mac"
        case .rejected(let limit, let reason):
            return "Система не приняла лимит \(limit)%: \(reason)"
        }
    }
}

/// Доступ к лимиту заряда через системный PowerUI.
///
/// Публичного API у лимита нет, поэтому класс вызывается через рантайм
/// Objective-C. Если фреймворка или метода нет (другая версия macOS),
/// `isSupported` возвращает false и приложение работает без лимита.
public final class SystemChargeLimit: SystemChargeLimiting, @unchecked Sendable {
    private typealias ErrorPointer = AutoreleasingUnsafeMutablePointer<NSError?>?
    private typealias GetLimit =
        @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt8
    private typealias SetLimit =
        @convention(c) (AnyObject, Selector, UInt8, ErrorPointer) -> Bool
    private typealias GetLimits =
        @convention(c) (AnyObject, Selector, ErrorPointer) -> Unmanaged<AnyObject>?
    private typealias GetFlag = @convention(c) (AnyObject, Selector) -> Bool

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"

    private let client: NSObject?
    private let lock = NSLock()

    public init(clientName: String = "BatteryManager") {
        dlopen(Self.frameworkPath, RTLD_NOW)

        let selector = NSSelectorFromString("initWithClientName:")
        guard let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              type.instancesRespond(to: selector),
              let allocated = (type as AnyObject)
                .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let created = allocated
                .perform(selector, with: clientName)?.takeUnretainedValue()
                as? NSObject
        else {
            client = nil
            return
        }
        client = created
    }

    public var isSupported: Bool {
        guard let function: GetFlag = method("isMCLSupported"),
              let client else { return false }
        guard method("getMCLLimitWithError:") as GetLimit? != nil,
              method("setMCLLimit:error:") as SetLimit? != nil else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        return function(client, NSSelectorFromString("isMCLSupported"))
    }

    public var availableLimits: [Int] {
        guard let function: GetLimits = method("availableChargeLimitsWithError:"),
              let client else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var error: NSError?
        let result = function(
            client, NSSelectorFromString("availableChargeLimitsWithError:"), &error)
        let numbers = result?.takeUnretainedValue() as? [NSNumber] ?? []
        return numbers.map(\.intValue).filter { (1...100).contains($0) }.sorted()
    }

    public func currentLimit() -> Int? {
        guard let function: GetLimit = method("getMCLLimitWithError:"),
              let client else { return nil }
        lock.lock()
        defer { lock.unlock() }
        var error: NSError?
        let value = Int(function(
            client, NSSelectorFromString("getMCLLimitWithError:"), &error))
        guard error == nil, (1...100).contains(value) else { return nil }
        return value
    }

    public func setLimit(_ percent: Int) throws {
        guard let function: SetLimit = method("setMCLLimit:error:"),
              let client, (1...100).contains(percent) else {
            throw SystemChargeLimitError.unsupported
        }
        lock.lock()
        defer { lock.unlock() }
        var error: NSError?
        let accepted = function(
            client, NSSelectorFromString("setMCLLimit:error:"),
            UInt8(percent), &error)
        guard accepted, error == nil else {
            throw SystemChargeLimitError.rejected(
                limit: percent,
                reason: error.map { "\($0.domain), код \($0.code)" }
                    ?? "без описания")
        }
    }

    /// Реализация метода как функция C; nil — метода нет в этой версии macOS.
    private func method<Function>(_ name: String) -> Function? {
        let selector = NSSelectorFromString(name)
        guard let client, client.responds(to: selector) else { return nil }
        return unsafeBitCast(client.method(for: selector), to: Function.self)
    }
}
