//
//  NavigatorTests.swift
//  YT MusicTests
//
//  Regression tests for cross-tab navigation: `open(_:)` must push onto the
//  stack of the section currently on screen, not a hardcoded Home stack. The
//  original bug: "Go to album/artist" from a Search-originated page pushed onto
//  the off-screen Home path, so nothing visible happened.
//

import Testing
@testable import YT_Music

@MainActor
@Suite("Navigator")
struct NavigatorTests {

    private func destination(_ id: String) -> EntityDestination {
        EntityDestination(browseId: id, kind: .album, title: id, subtitle: "", thumbnailURL: nil)
    }

    @Test("open pushes onto the active section's stack, not Home")
    func opensOnActiveSection() {
        let nav = Navigator()
        nav.section = .search

        nav.open(destination("MPRE_heathens"))

        #expect(nav.section == .search)
        #expect(nav.searchPath.map(\.browseId) == ["MPRE_heathens"])
        #expect(nav.homePath.isEmpty)
        #expect(nav.currentPath.last?.browseId == "MPRE_heathens")
    }

    @Test("open from each browsable section targets that section's path")
    func routesPerSection() {
        for section in [ContentView.Section.home, .explore, .search, .library, .uploads, .history] {
            let nav = Navigator()
            nav.section = section
            nav.open(destination("id"))
            #expect(nav.section == section)
            #expect(nav.currentPath.map(\.browseId) == ["id"])
        }
    }

    @Test("open from Settings (no stack) falls back to Home")
    func settingsFallsBackToHome() {
        let nav = Navigator()
        nav.section = .settings

        nav.open(destination("MPRE_album"))

        #expect(nav.section == .home)
        #expect(nav.homePath.map(\.browseId) == ["MPRE_album"])
    }

    @Test("open appends (grows the back stack) rather than replacing")
    func appendsToBackStack() {
        let nav = Navigator()
        nav.section = .library

        nav.open(destination("first"))
        nav.open(destination("second"))

        #expect(nav.libraryPath.map(\.browseId) == ["first", "second"])
    }

    @Test("open ignores re-pushing the page already on top")
    func dedupesTopOfStack() {
        let nav = Navigator()
        nav.section = .home

        nav.open(destination("same"))
        nav.open(destination("same"))

        #expect(nav.homePath.map(\.browseId) == ["same"])
    }
}
