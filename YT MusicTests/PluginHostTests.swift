//
//  PluginHostTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@MainActor
private final class RecordingPlugin: Plugin {
    let id: String
    let name = "Recording"
    let summary = ""
    private(set) var progress: [Double] = []

    init(id: String) { self.id = id }

    func playbackDidProgress(currentTime: Double, duration: Double) {
        progress.append(currentTime)
    }
}

@Suite("PluginHost")
@MainActor
struct PluginHostTests {

    @Test("Fans playback progress out to enabled plugins only")
    func progressReachesEnabledOnly() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let enabled = RecordingPlugin(id: "on")
        let disabled = RecordingPlugin(id: "off")
        let host = PluginHost(plugins: [enabled, disabled], defaults: defaults)
        host.setEnabled(true, for: enabled)

        host.playbackDidProgress(currentTime: 12, duration: 200)

        #expect(enabled.progress == [12])
        #expect(disabled.progress.isEmpty)
    }
}
