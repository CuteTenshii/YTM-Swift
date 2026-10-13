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
        let settings = AppSettings(defaults: suite)
        #expect(settings.playOnSingleClick == false)
        #expect(settings.playClickCount == 2)
    }

    @Test("Single click needs one click")
    func singleClickCount() {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        settings.playOnSingleClick = true
        #expect(settings.playClickCount == 1)
    }

    @Test("The choice persists across instances")
    func persists() {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        AppSettings(defaults: suite).playOnSingleClick = true
        #expect(AppSettings(defaults: suite).playOnSingleClick)
    }
}
