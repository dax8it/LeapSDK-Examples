import Foundation

enum AudioDebug {
#if DEBUG
    static var enabled = false

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print(message())
    }
#else
    static let enabled = false

    static func log(_ message: @autoclosure () -> String) {
    }
#endif
}
