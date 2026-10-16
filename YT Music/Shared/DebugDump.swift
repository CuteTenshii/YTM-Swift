//
//  DebugDump.swift
//  YT Music
//
//  Writes a response body or script to Caches so it can be inspected when a network payload can't be reproduced from tests.
//

import Foundation

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
