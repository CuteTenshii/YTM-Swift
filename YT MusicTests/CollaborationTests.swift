//
//  CollaborationTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Playlist collaboration")
struct CollaborationTests {

    private func page(editHeader: String) throws -> EntityPage {
        let json = """
        {"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
          {"musicEditablePlaylistDetailHeaderRenderer":{
            "header":{"musicResponsiveHeaderRenderer":{"title":{"runs":[{"text":"Mine"}]}}},
            "editHeader":{"musicPlaylistEditHeaderRenderer":\(editHeader)}}}
        ]}}}}]}}}
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(json.utf8))
        let destination = EntityDestination(browseId: "VLPLx", kind: .playlist, title: "", subtitle: "", thumbnailURL: nil)
        return EntityPageParser.parse(response, fallback: destination)
    }

    @Test("A shareable playlist's header points at its collaboration panel")
    func panelFromHeader() throws {
        let header = try page(editHeader: """
        {"privacy":"UNLISTED","collaborationSettingsCommand":{"showEngagementPanelEndpoint":{
          "identifier":{"tag":"PAplaylist_collaborate"},
          "globalConfiguration":{"params":"0ggPCg1QTE5t"}}}}
        """).header
        #expect(header.collaborationPanel == CollaborationPanelRef(panelId: "PAplaylist_collaborate", params: "0ggPCg1QTE5t"))
    }

    @Test("A private playlist, whose settings are disabled, has no collaboration panel")
    func privateHasNoPanel() throws {
        let header = try page(editHeader: """
        {"privacy":"PRIVATE","collaborationSettingsDisabled":true,"collaborationSettingsCommand":{
          "confirmDialogEndpoint":{"content":{"confirmDialogRenderer":{}}}}}
        """).header
        #expect(header.collaborationPanel == nil)
    }

    private func panel(enabled: Bool, allowNew: Bool, shortUrl: String, collaborators: String) -> String {
        """
        {"content":{"engagementPanelSectionListRenderer":{"content":{"playlistCollaborationViewModel":{
          "playlistCollaborationFormSchema":{"id":"playlist_collaboration_form","initialValues":{
            "isCollaborationEnabled":\(enabled),"isAllowNewCollaboratorsEnabled":\(allowNew),"isInviteCollaboratorsButtonEnabled":true}},
          "copyLinkButton":{"buttonViewModel":{"title":"Copy invite link","onTap":{"innertubeCommand":{
            "copyLinkCommand":{"shortUrl":"\(shortUrl)","id":"PLx"}}}}},
          "playlistCollaborators":[\(collaborators)]
        }}}}}
        """
    }

    private let owner = """
    {"contentListItemViewModel":{"title":{"content":"Tenshii"},
      "metadata":{"contentMetadataViewModel":{"metadataRows":[{"metadataParts":[{"text":{"content":"Owner"}}]}]}},
      "avatar":{"avatarViewModel":{"image":{"sources":[{"url":"https://yt3.ggpht.com/a=s176"}]}}},
      "rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"browseEndpoint":{"browseId":"UCowner"}}}}}}}
    """

    private func parse(_ json: String) throws -> PlaylistCollaboration {
        let response = try JSONDecoder().decode(CollaborationPanelResponse.self, from: Data(json.utf8))
        return try #require(CollaborationPanelParser.parse(response))
    }

    @Test("An enabled panel yields its invite link and collaborators")
    func enabled() throws {
        let collaboration = try parse(panel(
            enabled: true, allowNew: true,
            shortUrl: "https://music.youtube.com/playlist?list=PLx&jct=abc", collaborators: owner
        ))
        #expect(collaboration.isEnabled)
        #expect(collaboration.allowsNewCollaborators)
        #expect(collaboration.inviteURL?.absoluteString == "https://music.youtube.com/playlist?list=PLx&jct=abc")
        #expect(collaboration.collaborators == [
            PlaylistCollaborator(
                name: "Tenshii", role: "Owner", avatarURL: URL(string: "https://yt3.ggpht.com/a=s176"),
                link: EntityLink(name: "Tenshii", browseId: "UCowner", kind: .profile)
            ),
        ])
    }

    @Test("A disabled panel's empty link is treated as no invite link")
    func disabled() throws {
        let collaboration = try parse(panel(enabled: false, allowNew: false, shortUrl: "", collaborators: ""))
        #expect(!collaboration.isEnabled)
        #expect(!collaboration.allowsNewCollaborators)
        #expect(collaboration.inviteURL == nil)
        #expect(collaboration.collaborators.isEmpty)
    }

    @Test("A response without the collaboration view model doesn't parse")
    func missingViewModel() throws {
        let response = try JSONDecoder().decode(CollaborationPanelResponse.self, from: Data("{}".utf8))
        #expect(CollaborationPanelParser.parse(response) == nil)
    }
}
