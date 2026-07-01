//
//  CommentsParserTests.swift
//  YT MusicTests
//
//  Verifies comments continuation-token extraction and the entity-payload parse
//  against fixtures shaped like the real `next` responses (no network).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Comments parser")
struct CommentsParserTests {

    // The comments engagement panel carries a continuation token.
    private let tokenFixture = """
    {"engagementPanels":[
    {"engagementPanelSectionListRenderer":{"panelIdentifier":"engagement-panel-structured-description"}},
    {"engagementPanelSectionListRenderer":{"targetId":"engagement-panel-comments-section",
    "header":{"engagementPanelTitleHeaderRenderer":{"title":{"runs":[{"text":"Comments"}]}}},
    "content":{"sectionListRenderer":{"contents":[{"itemSectionRenderer":{"contents":[
    {"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"TOKEN_123"}}}}
    ]}}]}}}}
    ]}
    """

    @Test("Finds the comments panel's continuation token")
    func findsToken() throws {
        let response = try JSONDecoder().decode(CommentsTokenResponse.self, from: Data(tokenFixture.utf8))
        #expect(CommentsParser.continuationToken(response) == "TOKEN_123")
    }

    @Test("No comments panel → nil token")
    func noToken() throws {
        let response = try JSONDecoder().decode(CommentsTokenResponse.self, from: Data("{}".utf8))
        #expect(CommentsParser.continuationToken(response) == nil)
    }

    // Comment data lives in framework-update entity mutations.
    private let commentsFixture = """
    {"frameworkUpdates":{"entityBatchUpdate":{"mutations":[
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"c1","content":{"content":"Great song!"},"publishedTime":"2 years ago","replyLevel":0},
    "author":{"displayName":"@alice","isVerified":true},
    "toolbar":{"likeCountNotliked":"1.2K","replyCount":"3"},
    "avatar":{"image":{"sources":[{"url":"https://x/a1.jpg","width":48},{"url":"https://x/a2.jpg","width":88}]}}}}},
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"r1","content":{"content":"A reply"},"replyLevel":1}}}},
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"c2","content":{"content":"Second"},"replyLevel":0},
    "author":{"displayName":"@bob"},"toolbar":{"likeCountNotliked":"0"}}}}
    ]}}}
    """

    @Test("Parses top-level comments, picks the largest avatar, skips replies")
    func parsesComments() throws {
        let response = try JSONDecoder().decode(CommentsResponse.self, from: Data(commentsFixture.utf8))
        let comments = CommentsParser.parse(response).comments

        #expect(comments.count == 2)   // the replyLevel-1 row is skipped
        #expect(comments[0].id == "c1")
        #expect(comments[0].author == "@alice")
        #expect(comments[0].text == "Great song!")
        #expect(comments[0].isVerified)
        #expect(comments[0].likeCount == "1.2K")
        #expect(comments[0].replyCount == "3")
        #expect(comments[0].publishedTime == "2 years ago")
        #expect(comments[0].authorThumbnailURL?.absoluteString == "https://x/a2.jpg")  // highest width

        // A "0" like count is treated as no count.
        #expect(comments[1].id == "c2")
        #expect(comments[1].likeCount == nil)
        #expect(comments[1].isVerified == false)
    }

    @Test("An empty response yields no comments and no paging token")
    func emptyOnGarbage() throws {
        let response = try JSONDecoder().decode(CommentsResponse.self, from: Data("{}".utf8))
        let page = CommentsParser.parse(response)
        #expect(page.comments.isEmpty)
        #expect(page.continuationToken == nil)
    }

    // A trailing (thread-less) continuation item is the "load more" paging token.
    private let pagingFixture = """
    {"frameworkUpdates":{"entityBatchUpdate":{"mutations":[
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"c1","content":{"content":"Hi"},"replyLevel":0},"author":{"displayName":"@a"}}}}
    ]}},
    "onResponseReceivedEndpoints":[{"appendContinuationItemsAction":{"continuationItems":[
    {"commentThreadRenderer":{"commentViewModel":{"commentViewModel":{"commentId":"c1"}}}},
    {"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"PAGE_2"}}}}
    ]}}]}
    """

    @Test("Extracts the next-page paging token from the trailing continuation")
    func parsesPagingToken() throws {
        let response = try JSONDecoder().decode(CommentsResponse.self, from: Data(pagingFixture.utf8))
        let page = CommentsParser.parse(response)
        #expect(page.comments.map(\.id) == ["c1"])
        #expect(page.continuationToken == "PAGE_2")   // not mistaken for a reply token
    }

    // Reply tokens live in the comment thread renderers, keyed to a comment id.
    private let withRepliesFixture = """
    {"frameworkUpdates":{"entityBatchUpdate":{"mutations":[
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"c1","content":{"content":"Top comment"},"replyLevel":0},
    "author":{"displayName":"@alice"},"toolbar":{"replyCount":"2"}}}}
    ]}},
    "onResponseReceivedEndpoints":[{"reloadContinuationItemsCommand":{"continuationItems":[
    {"commentThreadRenderer":{"commentViewModel":{"commentViewModel":{"commentId":"c1"}},
    "replies":{"commentRepliesRenderer":{"contents":[
    {"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"REPLIES_c1"}}}}
    ]}}}}
    ]}}]}
    """

    @Test("Attaches a comment's reply continuation token")
    func attachesReplyToken() throws {
        let response = try JSONDecoder().decode(CommentsResponse.self, from: Data(withRepliesFixture.utf8))
        let comments = CommentsParser.parse(response).comments
        #expect(comments.count == 1)
        #expect(comments[0].replyToken == "REPLIES_c1")
        #expect(comments[0].replyCount == "2")
    }

    // A reply continuation returns the reply entities (and may echo the parent).
    private let repliesFixture = """
    {"frameworkUpdates":{"entityBatchUpdate":{"mutations":[
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"c1","content":{"content":"Top comment"},"replyLevel":0},
    "author":{"displayName":"@alice"}}}},
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"r1","content":{"content":"First reply"},"replyLevel":1},
    "author":{"displayName":"@bob"}}}},
    {"payload":{"commentEntityPayload":{
    "properties":{"commentId":"r2","content":{"content":"Second reply"},"replyLevel":1},
    "author":{"displayName":"@carol"}}}}
    ]}}}
    """

    @Test("parseReplies returns the replies and drops the echoed parent")
    func parsesReplies() throws {
        let response = try JSONDecoder().decode(CommentsResponse.self, from: Data(repliesFixture.utf8))
        let replies = CommentsParser.parseReplies(response, excluding: "c1").comments
        #expect(replies.map(\.id) == ["r1", "r2"])   // parent "c1" excluded
        #expect(replies[0].text == "First reply")
    }
}
