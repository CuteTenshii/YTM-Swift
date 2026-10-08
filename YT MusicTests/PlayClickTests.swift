//
//  PlayClickTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Play click setting")
struct PlayClickTests {
    @Test("Defaults to double click")
    func defaultsToDoubleClick() {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        #expect(AppSettings(defaults: suite).playClick == .double)
    }

    @Test("Maps each choice to its click count")
    func clickCounts() {
        #expect(PlayClick.single.count == 1)
        #expect(PlayClick.double.count == 2)
    }

    @Test("The choice persists across instances")
    func persists() {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        AppSettings(defaults: suite).playClick = .single
        #expect(AppSettings(defaults: suite).playClick == .single)
    }
}
