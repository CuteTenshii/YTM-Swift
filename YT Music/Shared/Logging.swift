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

/// Writes a response body or script to Caches so it can be inspected when a
/// network payload can't be reproduced from tests.
nonisolated enum DebugDump {
    /// Returns the written path, or nil if the write failed.
    @discardableResult
    static func write(_ data: Data, to name: String) -> String? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }
}
