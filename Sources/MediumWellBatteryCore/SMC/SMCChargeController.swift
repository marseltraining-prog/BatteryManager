import Foundation

/// Запись значений в SMC. Абстракция нужна, чтобы логику выбора ключа
/// можно было проверить тестами без реального железа и прав root.
public protocol SMCWriting: Sendable {
    func read(_ key: String) -> SMCValue?
    func write(_ key: String, bytes: [UInt8]) throws
}

extension SMCAccess: SMCWriting {}

/// Ключ SMC, управляющий зарядкой, и значения «удерживать» / «разрешить».
public struct ChargeControlKey: Equatable, Sendable {
    /// Основной ключ управления.
    public let key: String
    /// Значение, останавливающее заряд.
    public let holdValue: [UInt8]
    /// Значение, разрешающее заряд.
    public let allowValue: [UInt8]
    /// Ключ-спутник, который пишется тем же значением (на части моделей
    /// одного ключа недостаточно — заряд возобновляется во сне).
    public let companionKey: String?
    /// Понятное описание для интерфейса.
    public let note: String

    public init(key: String, holdValue: [UInt8], allowValue: [UInt8],
                companionKey: String? = nil, note: String) {
        self.key = key
        self.holdValue = holdValue
        self.allowValue = allowValue
        self.companionKey = companionKey
        self.note = note
    }

    public var companionValue: [UInt8]? {
        companionKey == nil ? nil : holdValue
    }

    /// Известные ключи управления зарядом, от новых macOS к старым.
    /// Значения взяты из открытой реализации `battery`
    /// (github.com/actuallymentor/battery), где они проверены на железе.
    public static let knownKeys: [ChargeControlKey] = [
        ChargeControlKey(
            key: "CHTE", holdValue: [0x01, 0x00, 0x00, 0x00],
            allowValue: [0x00, 0x00, 0x00, 0x00],
            note: "macOS 26 и новее (CHTE)"),
        ChargeControlKey(
            key: "CH0B", holdValue: [0x02], allowValue: [0x00],
            companionKey: "CH0C",
            note: "Apple Silicon (CH0B/CH0C)"),
        ChargeControlKey(
            key: "CHSC", holdValue: [0x00], allowValue: [0x01],
            note: "новые модели (CHSC) — на части машин только для чтения"),
        ChargeControlKey(
            key: "CHIE", holdValue: [0x08], allowValue: [0x00],
            note: "управление адаптером (CHIE)")
    ]
}

public enum ChargeControlError: Error, Equatable, LocalizedError {
    case noSupportedKey
    case writeFailed(key: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noSupportedKey:
            return "На этой модели не найден поддерживаемый ключ управления зарядом"
        case .writeFailed(let key, let reason):
            return "Не удалось записать \(key): \(reason)"
        }
    }
}

/// Управление зарядкой через SMC.
///
/// Ключ выбирается по факту наличия в SMC: на новых macOS это CHTE,
/// на Apple Silicon — CH0B/CH0C, на некоторых моделях — CHSC.
/// Запись требует прав root, поэтому в приложении используется
/// привилегированный helper (см. scripts/install-helper.sh).
public final class SMCChargeController: ChargeController {
    private let smc: any SMCWriting
    private let candidates: [ChargeControlKey]

    /// Последняя ошибка записи — для отображения в интерфейсе.
    public private(set) var lastError: ChargeControlError?

    public init(
        smc: any SMCWriting = SMCAccess(),
        candidates: [ChargeControlKey] = ChargeControlKey.knownKeys
    ) {
        self.smc = smc
        self.candidates = candidates
    }

    /// Ключ, доступный на этой машине (первый существующий).
    public var detectedKey: ChargeControlKey? {
        candidates.first { smc.read($0.key) != nil }
    }

    /// Есть ли на этой машине поддерживаемый ключ.
    public var isSupported: Bool {
        detectedKey != nil
    }

    /// Разрешить или запретить зарядку (FR-001, FR-003).
    public func setChargingAllowed(_ allowed: Bool) {
        guard let key = detectedKey else {
            lastError = .noSupportedKey
            return
        }

        let value = allowed ? key.allowValue : key.holdValue

        do {
            try smc.write(key.key, bytes: value)
            if let companion = key.companionKey {
                try smc.write(companion, bytes: value)
            }
            lastError = nil
        } catch {
            lastError = .writeFailed(
                key: key.key,
                reason: (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error))
        }
    }
}
