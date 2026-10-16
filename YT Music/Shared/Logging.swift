//
//  Logging.swift
//  YT Music
//
//  Shared logging helpers. Read with Console.app or
//  `/usr/bin/log stream --predicate 'subsystem == "moe.tenshii.YT-Music"'`.
//

import Foundation
import OSLog

nonisolated extension Logger {
    /// A logger in the app's subsystem.
    init(category: String) {
        self.init(subsystem: "moe.tenshii.YT-Music", category: category)
    }

    /// Logs a runtime-built message, visible without a debugger attached.
    func note(_ message: String) {
        notice("\(message, privacy: .public)")
    }

    func problem(_ message: String) {
        error("\(message, privacy: .public)")
    }
}
