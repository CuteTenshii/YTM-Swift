//
//  AddToPlaylistResponse.swift
//  YT Music
//
//

import Foundation

nonisolated struct AddToPlaylistResponse: Decodable {
    let contents: Contents?

    /// `contents` is normally `[{ addToPlaylistRenderer }]`; a lone object is also accepted.
    struct Contents: Decodable {
        let renderers: [Renderer]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([Wrapper].self) {
                renderers = list.compactMap(\.addToPlaylistRenderer)
            } else if let single = try? container.decode(Wrapper.self) {
                renderers = [single.addToPlaylistRenderer].compactMap { $0 }
            } else {
                renderers = []
            }
        }

        struct Wrapper: Decodable {
            let addToPlaylistRenderer: Renderer?
        }
    }

    struct Renderer: Decodable {
        let playlists: [PlaylistOption]?
    }

    struct PlaylistOption: Decodable {
        let playlistAddToOptionRenderer: OptionRenderer?
    }

    struct OptionRenderer: Decodable {
        let playlistId: String?
        let title: OptionText?
        /// Arrives as split `runs` ("22" + " tracks") or a flat `simpleText`.
        let shortBylineText: OptionText?
        /// Nested under thumbnailRenderer.musicThumbnailRenderer, not a top-level `thumbnail`.
        let thumbnailRenderer: ThumbnailRenderer?
    }

    struct ThumbnailRenderer: Decodable {
        let musicThumbnailRenderer: MusicThumbnail?

        struct MusicThumbnail: Decodable {
            let thumbnail: ThumbnailList?
        }

        var bestURL: URL? { musicThumbnailRenderer?.thumbnail?.bestURL }
    }

    /// Arrives as `runs` or a flat `simpleText`.
    struct OptionText: Decodable {
        let runs: [Run]?
        let simpleText: String?

        struct Run: Decodable { let text: String? }

        var text: String { simpleText ?? (runs ?? []).compactMap(\.text).joined() }
    }

    struct ThumbnailList: Decodable {
        let thumbnails: [Thumb]?

        struct Thumb: Decodable {
            let url: String?
            let width: Int?
        }

        var bestURL: URL? {
            (thumbnails ?? [])
                .max { ($0.width ?? 0) < ($1.width ?? 0) }
                .flatMap { $0.url }
                .flatMap { URL(string: $0) }
        }
    }
}

nonisolated enum AddToPlaylistParser {
    static func parse(_ response: AddToPlaylistResponse) -> [EditablePlaylist] {
        (response.contents?.renderers ?? []).flatMap { $0.playlists ?? [] }.compactMap { option in
            guard let renderer = option.playlistAddToOptionRenderer,
                  let id = renderer.playlistId else { return nil }
            let title = renderer.title?.text ?? ""
            return EditablePlaylist(
                id: id,
                title: title.isEmpty ? "Playlist" : title,
                subtitle: renderer.shortBylineText?.text ?? "",
                thumbnailURL: renderer.thumbnailRenderer?.bestURL
            )
        }
    }
}
