//
//  Plugin.swift
//  YT Music
//
//

import SwiftUI

@MainActor
protocol Plugin: AnyObject, Identifiable {
    /// Persisted key for the enabled state; don't change once shipped.
    var id: String { get }
    var name: String { get }
    var summary: String { get }

    func setActive(_ active: Bool)
    func playbackDidChange(_ snapshot: PlaybackSnapshot?)
    func playbackDidProgress(currentTime: Double, duration: Double)
    var configuration: AnyView? { get }
}

extension Plugin {
    func setActive(_ active: Bool) {}
    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {}
    func playbackDidProgress(currentTime: Double, duration: Double) {}
    var configuration: AnyView? { nil }
}
