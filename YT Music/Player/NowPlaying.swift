//
//  NowPlaying.swift
//  YT Music
//

import Foundation

extension PlayerState {
    struct NowPlaying: Equatable, Codable {
        var title: String
        var subtitle: String
        var album: String
        var thumbnailURL: URL?
        var videoId: String
        var artists: [EntityLink] = []
        var albumLink: EntityLink?

        init(title: String, subtitle: String, album: String, thumbnailURL: URL?,
             videoId: String, artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.album = album
            self.thumbnailURL = thumbnailURL
            self.videoId = videoId
            self.artists = artists
            self.albumLink = albumLink
        }

        init(_ track: Track, videoId: String, album: String) {
            self.init(title: track.title, subtitle: track.subtitle, album: album,
                      thumbnailURL: track.thumbnailURL, videoId: videoId,
                      artists: track.artists, albumLink: track.albumLink)
        }

        // Custom decode so older snapshots without links still load.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            subtitle = try c.decode(String.self, forKey: .subtitle)
            album = try c.decode(String.self, forKey: .album)
            thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
            videoId = try c.decode(String.self, forKey: .videoId)
            artists = try c.decodeIfPresent([EntityLink].self, forKey: .artists) ?? []
            albumLink = try c.decodeIfPresent(EntityLink.self, forKey: .albumLink)
        }

        var asTrack: Track {
            Track(index: 1, title: title, subtitle: subtitle, duration: nil, thumbnailURL: thumbnailURL,
                  videoId: videoId, artists: artists, albumLink: albumLink)
        }

        var artistLine: String {
            let names = artists.map(\.name).filter { !$0.isEmpty }
            if !names.isEmpty { return names.joined(separator: ", ") }
            return PlayerState.withoutTypeLabel(subtitle).components(separatedBy: " • ").first ?? ""
        }
    }

    /// Strips the type label, view counts and bare durations from a subtitle.
    static func withoutTypeLabel(_ subtitle: String) -> String {
        var components = subtitle.components(separatedBy: " • ")
        let labels: Set<String> = ["Song", "Video", "Episode", "Podcast"]
        if components.count > 1, let first = components.first, labels.contains(first) {
            components.removeFirst()
        }
        components.removeAll { isViewCount($0) || isDuration($0) }
        return components.joined(separator: " • ")
    }

    /// A view-count component like "3.5M views".
    private static func isViewCount(_ component: String) -> Bool {
        let text = component.trimmingCharacters(in: .whitespaces).lowercased()
        guard text.hasSuffix(" views") || text.hasSuffix(" view") else { return false }
        return text.first?.isNumber ?? false
    }

    /// A bare duration like "2:46" or "1:02:30".
    private static func isDuration(_ component: String) -> Bool {
        let parts = component.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
