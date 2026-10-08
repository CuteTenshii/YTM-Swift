//
//  CreditsParserTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Credits parser")
struct CreditsParserTests {

    private let fixture = """
    {"onResponseReceivedActions":[{"openPopupAction":{"popup":{"dismissableDialogRenderer":{
    "title":"Song credits","sections":[
    {"dismissableDialogContentSectionRenderer":{"title":{"runs":[{"text":"Performed by"}]},
     "subtitle":{"runs":[{"text":"Rick Astley"}]}}},
    {"dismissableDialogContentSectionRenderer":{"title":{"runs":[{"text":"Written by"}]},
     "subtitle":{"runs":[{"text":"Mike Stock"},{"text":"\\n"},{"text":"Matt Aitken"},{"text":"\\n"},{"text":"Pete Waterman"}]}}},
    {"dismissableDialogContentSectionRenderer":{"title":{"runs":[{"text":"Empty"}]}}}
    ]}},"popupType":"DIALOG"}}]}
    """

    @Test("Splits each role's names on the newline runs and drops empty roles")
    func parsesSections() throws {
        let response = try JSONDecoder().decode(CreditsResponse.self, from: Data(fixture.utf8))
        #expect(CreditsParser.parse(response) == [
            CreditSection(role: "Performed by", names: ["Rick Astley"]),
            CreditSection(role: "Written by", names: ["Mike Stock", "Matt Aitken", "Pete Waterman"]),
        ])
    }

    @Test("A dialog without sections (music videos) yields no credits")
    func emptyForVideos() throws {
        let json = """
        {"onResponseReceivedActions":[{"openPopupAction":{"popup":{"dismissableDialogRenderer":{"title":"Song credits"}}}}]}
        """
        let response = try JSONDecoder().decode(CreditsResponse.self, from: Data(json.utf8))
        #expect(CreditsParser.parse(response).isEmpty)
    }
}
