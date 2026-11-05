//
//  Logging.swift
//  YT Music
//
//  Read logs with `/usr/bin/log stream --predicate 'subsystem == "moe.tenshii.YT-Music"'`.
//

import Foundation
import OSLog

nonisolated extension Logger {
    init(category: String) {
        self.init(subsystem: "moe.tenshii.YT-Music", category: category)
    }

    func note(_ message: String) {
        notice("\(message, privacy: .public)")
    }

    func problem(_ message: String) {
        error("\(message, privacy: .public)")
    }
}
