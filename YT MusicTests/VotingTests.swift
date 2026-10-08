//
//  VotingTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Playlist voting")
struct VotingTests {

    private func vote(_ status: PlaylistItemVote.Status) -> PlaylistItemVote {
        PlaylistItemVote(
            status: status, neutralCount: "0", upvotedCount: "1", downvotedCount: "-1",
            upvoteToken: "UP", undoUpvoteToken: "UNDO_UP", downvoteToken: "DOWN", undoDownvoteToken: "UNDO_DOWN"
        )
    }

    @Test("Each vote change picks the matching feedback token")
    func tokens() {
        #expect(vote(.none).token(toward: .up) == "UP")
        #expect(vote(.none).token(toward: .down) == "DOWN")
        #expect(vote(.up).token(toward: .none) == "UNDO_UP")
        #expect(vote(.down).token(toward: .none) == "UNDO_DOWN")
        #expect(vote(.up).token(toward: .down) == "DOWN")
        #expect(vote(.down).token(toward: .up) == "UP")
        #expect(vote(.none).token(toward: .none) == nil)
        #expect(vote(.up).token(toward: .up) == nil)
    }

    @Test("The shown count follows the vote status")
    func count() {
        #expect(vote(.none).count == "0")
        #expect(vote(.up).count == "1")
        #expect(vote(.down).count == "-1")
    }

    private func button(_ token: String, undo: String, toggled: Bool) -> String {
        """
        {"toggleButtonViewModel":{
          "defaultButtonViewModel":{"buttonViewModel":{"onTap":{"innertubeCommand":{"feedbackEndpoint":{"feedbackToken":"\(token)"}}}}},
          "toggledButtonViewModel":{"buttonViewModel":{"onTap":{"innertubeCommand":{"feedbackEndpoint":{"feedbackToken":"\(undo)"}}}}},
          "isToggled":\(toggled)}}
        """
    }

    private func page(rowExtras: String, sortItems: String = "[]", editHeader: String = "{}") throws -> EntityPage {
        let json = """
        {"contents":{"twoColumnBrowseResultsRenderer":{
          "tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
            {"musicEditablePlaylistDetailHeaderRenderer":{
              "header":{"musicResponsiveHeaderRenderer":{"title":{"runs":[{"text":"Mine"}]}}},
              "editHeader":{"musicPlaylistEditHeaderRenderer":\(editHeader)}}}
          ]}}}}],
          "secondaryContents":{"sectionListRenderer":{"contents":[
            {"musicPlaylistShelfRenderer":{
              "header":{"musicSideAlignedItemRenderer":{"startItems":[{"sortFilterSubMenuRenderer":{"subMenuItems":\(sortItems)}}]}},
              "contents":[{"musicResponsiveListItemRenderer":{
                "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Titanium"}]}}}],
                "playlistItemData":{"videoId":"vid1","playlistSetVideoId":"SET1"}\(rowExtras)}}]
            }}
          ]}}
        }}}
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(json.utf8))
        let destination = EntityDestination(browseId: "VLPLx", kind: .playlist, title: "", subtitle: "", thumbnailURL: nil)
        return EntityPageParser.parse(response, fallback: destination)
    }

    @Test("A voting row's buttons yield its status, counts, and tokens")
    func rowVote() throws {
        let extras = """
        ,"engagementBar":{"engagementBarViewModel":{"actions":[{"votingViewModel":{
          "upvoteButton":\(button("UP", undo: "UNDO_UP", toggled: true)),
          "downvoteButton":\(button("DOWN", undo: "UNDO_DOWN", toggled: false)),
          "initialState":{"votes":1,"status":"VOTE_STATUS_UPVOTED","compactVotes":"0","compactVotesUpvoted":"1","compactVotesDownvoted":"-1"}
        }}]}}
        """
        let track = try #require(try page(rowExtras: extras).tracks.first)
        #expect(track.vote == vote(.up))
    }

    @Test("Rows of playlists without voting have no votes")
    func rowWithoutVoting() throws {
        #expect(try page(rowExtras: "").tracks.first?.vote == nil)
    }

    @Test("An owned playlist's sort choices edit its saved order")
    func editSorts() throws {
        let items = """
        [{"title":"Top voted","selected":true,"serviceEndpoint":{"playlistEditEndpoint":{"playlistId":"PLx",
           "actions":[{"action":"ACTION_SET_PLAYLIST_VIDEO_ORDER","playlistVideoOrder":6}],"params":"CAE%3D"}}},
         {"title":"Title","selected":false,"serviceEndpoint":{"playlistEditEndpoint":{"playlistId":"PLx",
           "actions":[{"action":"ACTION_SET_PLAYLIST_DYNAMIC_SORT_PREFERENCE","playlistDynamicSortPreference":1}]}}}]
        """
        #expect(try page(rowExtras: "", sortItems: items).sortOptions == [
            PlaylistSortOption(
                title: "Top voted",
                action: .edit(PlaylistSortEdit(action: "ACTION_SET_PLAYLIST_VIDEO_ORDER", field: "playlistVideoOrder",
                                               value: 6, params: "CAE%3D")),
                isSelected: true
            ),
            PlaylistSortOption(
                title: "Title",
                action: .edit(PlaylistSortEdit(action: "ACTION_SET_PLAYLIST_DYNAMIC_SORT_PREFERENCE",
                                               field: "playlistDynamicSortPreference", value: 1, params: nil))
            ),
        ])
    }

    @Test("The edit header's Voting dropdown yields its choices")
    func voteOptions() throws {
        let header = """
        {"voteDropdown":{"dropdownRenderer":{"entries":[
          {"dropdownItemRenderer":{"label":{"runs":[{"text":"Everyone"}]},"isSelected":false,"int32Value":1,
            "descriptionText":{"runs":[{"text":"Anyone can vote"}]}}},
          {"dropdownItemRenderer":{"label":{"runs":[{"text":"Collaborators only"}]},"isSelected":false,"int32Value":2,
            "disabled":true,"descriptionText":{"runs":[{"text":"Only collaborators can vote"}]}}},
          {"dropdownItemRenderer":{"label":{"runs":[{"text":"Voting off"}]},"isSelected":true,"int32Value":3,
            "descriptionText":{"runs":[{"text":"No one can vote"}]}}}
        ]}}}
        """
        #expect(try page(rowExtras: "", editHeader: header).header.voteOptions == [
            PlaylistVoteOption(value: 1, title: "Everyone", detail: "Anyone can vote", isDisabled: false, isSelected: false),
            PlaylistVoteOption(value: 2, title: "Collaborators only", detail: "Only collaborators can vote",
                               isDisabled: true, isSelected: false),
            PlaylistVoteOption(value: 3, title: "Voting off", detail: "No one can vote", isDisabled: false, isSelected: true),
        ])
    }
}
