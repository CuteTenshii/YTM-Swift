import Foundation
import Testing
@testable import YT_Music

@Suite("Library artist page")
struct LibraryArtistPageTests {
    private let json = """
    {"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"musicShelfRenderer":{
        "contents":[
          {"musicResponsiveListItemRenderer":{
            "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Shuffle all"}]}}}],
            "navigationEndpoint":{"watchPlaylistEndpoint":{"playlistId":"ML1"}}}},
          {"musicResponsiveListItemRenderer":{
            "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song","navigationEndpoint":{"watchEndpoint":{"videoId":"abc"}}}]}}}],
            "playlistItemData":{"videoId":"abc"}}}
        ],
        "subheaders":[{"musicSideAlignedItemRenderer":{"startItems":[{"dropdownRenderer":{"entries":[
          {"dropdownItemRenderer":{"label":{"runs":[{"text":"Release date"}]},"isSelected":true,
            "onSelectCommand":{"browseEndpoint":{"browseId":"MPLAUC1","params":"p1"}}}},
          {"dropdownItemRenderer":{"label":{"runs":[{"text":"Recently saved"}]},"isSelected":false,
            "onSelectCommand":{"browseEndpoint":{"browseId":"MPLAUC1","params":"p2"}}}}
        ]}}]}}]
      }}]}}}}]}}}
    """

    @Test("Drops the Shuffle all row and reads the sort dropdown")
    func parses() throws {
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(json.utf8))
        let destination = EntityDestination(browseId: "MPLAUC1", kind: .unknown, title: "In your library",
                                            subtitle: "", thumbnailURL: nil)
        let page = EntityPageParser.parse(response, fallback: destination)
        #expect(page.tracks.map(\.videoId) == ["abc"])
        #expect(page.shufflePlaylistId == "ML1")
        #expect(page.sortOptions.map(\.title) == ["Release date", "Recently saved"])
        #expect(page.sortOptions.map(\.isSelected) == [true, false])
        #expect(page.sortOptions[1].action == .browse(browseId: "MPLAUC1", params: "p2"))
    }
}
