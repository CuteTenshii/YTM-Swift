//
//  ToastCenterTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("ToastCenter")
@MainActor
struct ToastCenterTests {

    @Test("A new toast replaces the one on screen")
    func newestWins() {
        let center = ToastCenter()
        center.show(Toast(message: "first"))
        center.show(Toast(message: "second"))
        #expect(center.current?.message == "second")
    }

    @Test("Dismissing a stale toast leaves the newer one up")
    func staleDismissIgnored() {
        let center = ToastCenter()
        let old = Toast(message: "old")
        center.show(old)
        center.show(Toast(message: "new"))

        center.dismiss(old.id)

        #expect(center.current?.message == "new")
    }

    @Test("A toast dismisses itself after its duration")
    func autoDismisses() async {
        let center = ToastCenter()
        center.show(Toast(message: "hi"), for: .milliseconds(20))

        try? await Task.sleep(for: .milliseconds(200))

        #expect(center.current == nil)
    }

    @Test("Hovering keeps a toast up until the pointer leaves")
    func hoverPausesDismissal() async {
        let center = ToastCenter()
        center.show(Toast(message: "hi"), for: .milliseconds(20))
        center.setHovering(true)

        try? await Task.sleep(for: .milliseconds(200))
        #expect(center.current != nil)

        center.setHovering(false)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(center.current == nil)
    }
}
