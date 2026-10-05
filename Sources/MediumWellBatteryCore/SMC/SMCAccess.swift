import CSMC
import Foundation

/// Значение ключа SMC.
public struct SMCValue: Equatable, Sendable {
    public let key: String
    public let bytes: [UInt8]
    /// Четырёхбуквенный код типа данных (`8iu`, `flt`, `_xeh`, …).
    public let type: String

    public init(key: String, bytes: [UInt8], type: String) {
        self.key = key
        self.bytes = bytes
        self.type = type
    }

    /// Значение как целое (little-endian, как отдаёт SMC).
    public var integer: UInt32 {
        bytes.enumerated().reduce(0) { result, item in
            result | (UInt32(item.element) << (8 * item.offset))
        }
    }
}

public enum SMCAccessError: Error, Equatable, LocalizedError {
    case cannotOpen
    case keyNotFound(String)
    case readFailed(key: String, code: Int)
    case writeRejected(key: String, smcResult: Int)
    case sizeMismatch(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "Не удалось подключиться к AppleSMC"
        case .keyNotFound(let key):
            return "Ключ SMC \(key) не найден"
        case .readFailed(let key, let code):
            return "Не удалось прочитать ключ \(key) (код \(code))"
        case .writeRejected(let key, let result):
            return "SMC отклонил запись ключа \(key) (код \(result)); "
                + "вероятно, ключ только для чтения или нужны права root"
        case .sizeMismatch(let expected, let got):
            return "Ключ ждёт \(expected) байт, передано \(got)"
        }
    }
}

/// Доступ к SMC (System Management Controller) через IOKit.
///
/// Чтение доступно обычному пользователю, запись требует прав root —
/// поэтому приложение пишет ключи через привилегированный helper.
public final class SMCAccess: @unchecked Sendable {
    /// Замок общий для всех экземпляров: соединение с AppleSMC одно
    /// на процесс, параллельные вызовы должны быть сериализованы.
    private static let sharedLock = NSLock()

    private var isOpen = false

    public init() {}

    deinit {
        guard isOpen else { return }
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }
        csmc_close()
    }

    /// Читает ключ. `nil` — ключа нет или значение недоступно.
    public func read(_ key: String) -> SMCValue? {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }

        guard openIfNeeded() else { return nil }

        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        var type: UInt32 = 0

        let status = key.withCString { pointer in
            bytes.withUnsafeMutableBufferPointer { buffer in
                csmc_read_key(pointer, buffer.baseAddress, &size, &type)
            }
        }
        guard status == 0 else { return nil }

        return SMCValue(key: key,
                        bytes: Array(bytes.prefix(Int(size))),
                        type: Self.typeString(from: type))
    }

    /// Записывает значение ключа. Требует прав root.
    public func write(_ key: String, bytes: [UInt8]) throws {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }

        guard openIfNeeded() else { throw SMCAccessError.cannotOpen }

        let status = key.withCString { pointer in
            bytes.withUnsafeBufferPointer { buffer in
                csmc_write_key(pointer, buffer.baseAddress, UInt32(bytes.count))
            }
        }

        switch status {
        case 0:
            return
        case 2:
            throw SMCAccessError.keyNotFound(key)
        case 3:
            throw SMCAccessError.sizeMismatch(expected: -1, got: bytes.count)
        case 5:
            throw SMCAccessError.writeRejected(
                key: key, smcResult: Int(csmc_last_result()))
        default:
            throw SMCAccessError.readFailed(key: key, code: Int(status))
        }
    }

    /// Есть ли ключ в SMC.
    public func exists(_ key: String) -> Bool {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }

        guard openIfNeeded() else { return false }
        return key.withCString { csmc_key_exists($0) == 1 }
    }

    // MARK: - Внутреннее

    private func openIfNeeded() -> Bool {
        if isOpen { return true }
        guard csmc_open() == 0 else { return false }
        isOpen = true
        return true
    }

    /// Код типа приходит четырьмя байтами с выравниванием пробелами
    /// («ui8 », «flt ») — лишние пробелы убираем.
    private static func typeString(from type: UInt32) -> String {
        let bytes = (0..<4).map { UInt8((type >> (8 * (3 - $0))) & 0xFF) }
        let raw = String(bytes: bytes, encoding: .ascii) ?? ""
        return raw.trimmingCharacters(in: .whitespaces)
    }
}
