import Foundation
import Testing
@testable import YT_Music

@Suite("ReturnYouTubeDislikeAPI")
struct ReturnYouTubeDislikeTests {
    @Test("Builds the votes URL for a video")
    func url() {
        let url = ReturnYouTubeDislikeAPI.votesURL(videoId: "abc123")
        #expect(url?.absoluteString == "https://returnyoutubedislikeapi.com/votes?videoId=abc123")
    }

    @Test("Decodes likes and dislikes and ignores the other fields")
    func decodes() throws {
        let json = #"{"id":"abc123","likes":1200,"dislikes":34,"rating":4.8,"viewCount":99999,"deleted":false}"#
        let votes = try ReturnYouTubeDislikeAPI.decode(Data(json.utf8))
        #expect(votes == VoteCounts(likes: 1200, dislikes: 34))
    }

    @Test("A body without counts fails to decode")
    func rejectsError() {
        #expect(throws: (any Error).self) {
            try ReturnYouTubeDislikeAPI.decode(Data(#"{"error":"not found"}"#.utf8))
        }
    }
}
