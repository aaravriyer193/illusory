import Foundation

/// stdout is block-buffered once it isn't a tty, which silently swallows output
/// from a launched menu-bar app. stderr is unbuffered, so diagnostics survive.
enum Log {
    static func info(_ message: String) {
        FileHandle.standardError.write("illusory: \(message)\n".data(using: .utf8)!)
    }
}
