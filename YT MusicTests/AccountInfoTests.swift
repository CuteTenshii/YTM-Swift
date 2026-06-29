//
//  AccountInfoTests.swift
//  YT MusicTests
//
//  Tests for parsing the account/account_menu response.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Account info")
struct AccountInfoTests {

    private func response(from json: String) throws -> AccountMenuResponse {
        try JSONDecoder().decode(AccountMenuResponse.self, from: Data(json.utf8))
    }

    @Test("Parses name, handle, and the largest avatar")
    func parsesFullAccount() throws {
        let response = try response(from: """
        { "actions": [ { "openPopupAction": { "popup": { "multiPageMenuRenderer": {
          "header": { "activeAccountHeaderRenderer": {
            "accountName": { "runs": [ { "text": "Ada Lovelace" } ] },
            "channelHandle": { "runs": [ { "text": "@ada" } ] },
            "accountPhoto": { "thumbnails": [
              { "url": "https://img/small", "width": 48, "height": 48 },
              { "url": "https://img/big", "width": 192, "height": 192 }
            ] }
          } }
        } } } } ] }
        """)

        let info = try #require(AccountInfoParser.parse(response))
        #expect(info.name == "Ada Lovelace")
        #expect(info.handle == "@ada")
        #expect(info.avatarURL?.absoluteString == "https://img/big")
    }

    @Test("Falls back to email when there's no channel handle")
    func fallsBackToEmail() throws {
        let response = try response(from: """
        { "actions": [ { "openPopupAction": { "popup": { "multiPageMenuRenderer": {
          "header": { "activeAccountHeaderRenderer": {
            "accountName": { "runs": [ { "text": "Grace" } ] },
            "email": { "runs": [ { "text": "grace@example.com" } ] }
          } }
        } } } } ] }
        """)

        let info = try #require(AccountInfoParser.parse(response))
        #expect(info.handle == "grace@example.com")
        #expect(info.avatarURL == nil)
    }

    @Test("Returns nil when there's no account header (signed out)")
    func nilWhenNoHeader() throws {
        let response = try response(from: #"{ "actions": [] }"#)
        #expect(AccountInfoParser.parse(response) == nil)
    }

    @Test("Returns nil when the name is empty")
    func nilWhenNameEmpty() throws {
        let response = try response(from: """
        { "actions": [ { "openPopupAction": { "popup": { "multiPageMenuRenderer": {
          "header": { "activeAccountHeaderRenderer": { "channelHandle": { "runs": [ { "text": "@x" } ] } } }
        } } } } ] }
        """)
        #expect(AccountInfoParser.parse(response) == nil)
    }
}
