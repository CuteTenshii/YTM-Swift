import Foundation
import Testing
@testable import YT_Music

@Suite("EpisodeDetailsParser")
struct EpisodeDetailsTests {
    private func decode(_ json: String) throws -> EpisodeDetailsResponse {
        try JSONDecoder().decode(EpisodeDetailsResponse.self, from: Data(json.utf8))
    }

    @Test("Parses title, show link and description with links")
    func parses() throws {
        let response = try decode("""
        {"contents":{"sectionListRenderer":{"contents":[{"musicDescriptionShelfRenderer":{
          "header":{"runs":[{"text":"Episode 1"}]},
          "subheader":{"runs":[{"text":"The Show","navigationEndpoint":{"browseEndpoint":{"browseId":"MPSPPLabc"}}}]},
          "description":{"runs":[{"text":"Visit "},{"text":"example.com","navigationEndpoint":{"urlEndpoint":{"url":"http://example.com"}}}]}
        }}]}}}
        """)
        let details = try #require(EpisodeDetailsParser.parse(response))
        #expect(details.title == "Episode 1")
        #expect(details.show?.browseId == "MPSPPLabc")
        #expect(String(details.description.characters) == "Visit example.com")
        let links = details.description.runs.compactMap(\.link)
        #expect(links == [URL(string: "http://example.com")!])
    }

    @Test("A response without a description shelf yields nil")
    func empty() throws {
        let response = try decode(#"{"contents":{"sectionListRenderer":{"contents":[]}}}"#)
        #expect(EpisodeDetailsParser.parse(response) == nil)
    }
}
