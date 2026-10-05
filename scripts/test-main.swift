// Точка входа тестового исполняемого файла для запуска без SwiftPM/Xcode.
// SwiftPM генерирует такой вход автоматически; здесь он задан явно,
// чтобы scripts/run-tests.sh мог собрать и запустить тесты напрямую.
import Foundation
import Testing

@main
enum MediumWellTestRunner {
    static func main() async {
        let code: CInt = await __swiftPMEntryPoint()
        exit(code)
    }
}
