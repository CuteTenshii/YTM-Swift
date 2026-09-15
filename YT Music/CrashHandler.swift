import Foundation
import Darwin

/// Saves the small amount of diagnostic information that is still available
/// when the process terminates unexpectedly. This is intentionally local-only:
/// crash reports can contain URLs and playback details.
nonisolated enum CrashHandler {
    private static let reportURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("YT Music", isDirectory: true)
            .appendingPathComponent("crashes", isDirectory: true)
            .appendingPathComponent(timestampedFilename)
    }()

    private static let timestampedFilename: String = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(formatter.string(from: Date())).log"
    }()

    // The descriptor is opened before installing signal handlers. The signal
    // path writes a fixed message without formatting crash-time details.
    nonisolated(unsafe) private static var reportDescriptor: Int32 = -1
    private static let fatalSignals: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP]

    static func install() {
        guard reportDescriptor == -1 else { return }

        let directory = reportURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reportDescriptor = open(reportURL.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)

        NSSetUncaughtExceptionHandler(ytmUncaughtExceptionHandler)

        for signalNumber in fatalSignals {
            signal(signalNumber, ytmCrashSignalHandler)
        }
    }

    fileprivate static func appendException(_ message: String) {
        guard let data = message.data(using: .utf8), reportDescriptor != -1 else { return }
        data.withUnsafeBytes { bytes in
            _ = write(reportDescriptor, bytes.baseAddress, data.count)
        }
    }

    fileprivate static func appendSignal(_ signalNumber: Int32) {
        guard reportDescriptor != -1 else { return }
        let message: StaticString
        switch signalNumber {
        case SIGABRT: message = "\n=== Fatal signal SIGABRT ===\n"
        case SIGBUS: message = "\n=== Fatal signal SIGBUS ===\n"
        case SIGFPE: message = "\n=== Fatal signal SIGFPE ===\n"
        case SIGILL: message = "\n=== Fatal signal SIGILL ===\n"
        case SIGSEGV: message = "\n=== Fatal signal SIGSEGV ===\n"
        case SIGTRAP: message = "\n=== Fatal signal SIGTRAP ===\n"
        default: message = "\n=== Fatal signal unknown ===\n"
        }
        message.withUTF8Buffer { bytes in
            _ = write(reportDescriptor, bytes.baseAddress, bytes.count)
        }
    }
}

nonisolated private func ytmUncaughtExceptionHandler(_ exception: NSException) {
    let details = """

    === Uncaught Objective-C exception ===
    date: \(ISO8601DateFormatter().string(from: Date()))
    name: \(exception.name.rawValue)
    reason: \(exception.reason ?? "unknown")
    call stack:
    \(exception.callStackSymbols.joined(separator: "\n"))
    """
    CrashHandler.appendException(details)
}

nonisolated private func ytmCrashSignalHandler(_ signalNumber: Int32) {
    CrashHandler.appendSignal(signalNumber)
    signal(signalNumber, SIG_DFL)
    kill(getpid(), signalNumber)
}
