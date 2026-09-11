import Foundation

nonisolated struct PlaylistFilterMetadataResponse: Decodable {
    let tracks: [TrackMetadata]?

    struct TrackMetadata: Decodable {
        let videoId: String?
        let setVideoId: String?
        let trackName: String?
        let artistNames: [String]?
        let albumName: String?

        var track: Track? {
            guard let videoId, let trackName else { return nil }
            return Track(
                index: 0,
                title: trackName,
                subtitle: (artistNames ?? []).joined(separator: ", "),
                duration: nil,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"),
                videoId: videoId,
                albumLink: nil,
                playlistSetVideoId: setVideoId,
                searchTerms: [albumName].compactMap { $0 }
            )
        }
    }
}
