//
//  DiscordRPCTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Discord RPC title parsing")
struct DiscordRPCSplitTitleTests {

    @Test("Splits \"Artist - Track\" on a hyphen")
    func splitsOnHyphen() {
        let result = DiscordRPC.splitTitle("Some Artist - Some Track")
        #expect(result?.artist == "Some Artist")
        #expect(result?.track == "Some Track")
    }

    @Test("Splits on an en dash")
    func splitsOnEnDash() {
        let result = DiscordRPC.splitTitle("Some Artist – Some Track")
        #expect(result?.artist == "Some Artist")
        #expect(result?.track == "Some Track")
    }

    @Test("No separator yields nil")
    func noSeparatorYieldsNil() {
        #expect(DiscordRPC.splitTitle("Just A Title") == nil)
    }

    @Test("Empty artist or track after trimming yields nil")
    func emptyPartYieldsNil() {
        #expect(DiscordRPC.splitTitle(" - Track") == nil)
        #expect(DiscordRPC.splitTitle("Artist - ") == nil)
    }

    @Test("Only the first separator occurrence splits the title")
    func firstOccurrenceWins() {
        let result = DiscordRPC.splitTitle("Artist - Track - Live Version")
        #expect(result?.artist == "Artist")
        #expect(result?.track == "Track - Live Version")
    }

    @Test("A hyphen inside a hyphenated word alone does not split")
    func hyphenWithoutSurroundingSpacesYieldsNil() {
        #expect(DiscordRPC.splitTitle("Long-Titled Song") == nil)
    }
}
