//
//  ReturnYouTubeDislike.swift
//  YT Music
//
//  Return YouTube Dislike lookup: vote counts for a video, decoded from the
//  public returnyoutubedislikeapi.com `votes` endpoint.
//

import Foundation

nonisolated struct VoteCounts: Equatable, Sendable, Decodable {
    var likes: Int
    var dislikes: Int
}

nonisolated enum ReturnYouTubeDislikeAPI {
    static func votesURL(videoId: String) -> URL? {
        var components = URLComponents(string: "https://returnyoutubedislikeapi.com/votes")
        components?.queryItems = [URLQueryItem(name: "videoId", value: videoId)]
        return components?.url
    }

    static func decode(_ data: Data) throws -> VoteCounts {
        try JSONDecoder().decode(VoteCounts.self, from: data)
    }
}

actor ReturnYouTubeDislikeClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? NetworkSession.make()
    }

    /// Nil when the API has no data for the video.
    func votes(videoId: String) async throws -> VoteCounts? {
        guard let url = ReturnYouTubeDislikeAPI.votesURL(videoId: videoId) else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try ReturnYouTubeDislikeAPI.decode(data)
    }
}
