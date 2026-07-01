//
//  MenuTokenParsingTests.swift
//  YT MusicTests
//
//  Tests that the overflow-menu token miners on the shared renderers pull out the
//  history feedback token and the uploaded-item delete entity id — both directly
//  on a service item and behind a confirm-delete dialog.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Menu token parsing")
struct MenuTokenParsingTests {

    private func listRow(from json: String) throws -> MusicResponsiveListItemRenderer {
        try JSONDecoder().decode(MusicResponsiveListItemRenderer.self, from: Data(json.utf8))
    }

    private func card(from json: String) throws -> MusicTwoRowItemRenderer {
        try JSONDecoder().decode(MusicTwoRowItemRenderer.self, from: Data(json.utf8))
    }

    @Test("List row mines the feedback token from a service menu item")
    func listRowFeedbackToken() throws {
        let row = try listRow(from: """
        { "menu": { "menuRenderer": { "items": [
          { "menuServiceItemRenderer": { "serviceEndpoint": {
            "feedbackEndpoint": { "feedbackToken": "TOKEN_1" }
          } } }
        ] } } }
        """)
        #expect(row.feedbackToken == "TOKEN_1")
    }

    @Test("List row mines a delete entity id directly on a service endpoint")
    func listRowDirectDeleteId() throws {
        let row = try listRow(from: """
        { "menu": { "menuRenderer": { "items": [
          { "menuServiceItemRenderer": { "serviceEndpoint": {
            "deletePrivatelyOwnedEntityCommand": { "entityId": "ENTITY_A" }
          } } }
        ] } } }
        """)
        #expect(row.deleteEntityId == "ENTITY_A")
    }

    @Test("Card mines a delete entity id from behind the confirm-delete dialog")
    func cardConfirmDialogDeleteId() throws {
        let card = try card(from: """
        { "title": { "runs": [ { "text": "Uploaded Album" } ] },
          "menu": { "menuRenderer": { "items": [
            { "menuNavigationItemRenderer": { "navigationEndpoint": {
              "confirmDialogEndpoint": { "content": { "confirmDialogRenderer": {
                "confirmButton": { "buttonRenderer": { "serviceEndpoint": {
                  "deletePrivatelyOwnedEntityCommand": { "entityId": "ENTITY_B" }
                } } }
              } } }
            } } }
          ] } }
        }
        """)
        #expect(card.deleteEntityId == "ENTITY_B")
    }

    @Test("No menu → no tokens")
    func absentMenu() throws {
        let row = try listRow(from: "{ }")
        #expect(row.feedbackToken == nil)
        #expect(row.deleteEntityId == nil)
    }
}
