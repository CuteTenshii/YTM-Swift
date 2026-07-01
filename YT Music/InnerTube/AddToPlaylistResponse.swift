//
//  AddToPlaylistResponse.swift
//  YT Music
//
//  Decodable models + parser for `playlist/get_add_to_playlist` — the endpoint
//  YT Music's own "Add to playlist" dialog uses. Unlike browsing the library
//  playlists page (which lists every saved playlist, including ones you can't
//  edit), this returns exactly the playlists the signed-in user can add the
//  given track(s) to.
//
//  Path:
//    contents.addToPlaylistRenderer.playlists[]
//      .playlistAddToOptionRenderer { playlistId, title, thumbnail }
//

import Foundation

nonisolated struct AddToPlaylistResponse: Decodable {
    let contents: Contents?

    struct Contents: Decodable {
        let addToPlaylistRenderer: Renderer?
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
        let thumbnail: ThumbnailList?
    }

    /// The option title can arrive as either `runs` or a flat `simpleText`.
    struct OptionText: Decodable {
        let runs: [Run]?
        let simpleText: String?

        struct Run: Decodable { let text: String }

        var text: String { simpleText ?? (runs ?? []).map(\.text).joined() }
    }

    struct ThumbnailList: Decodable {
        let thumbnails: [Thumb]?

        struct Thumb: Decodable {
            let url: String
            let width: Int?
        }

        var bestURL: URL? {
            (thumbnails ?? [])
                .max { ($0.width ?? 0) < ($1.width ?? 0) }
                .flatMap { URL(string: $0.url) }
        }
    }
}

nonisolated enum AddToPlaylistParser {
    static func parse(_ response: AddToPlaylistResponse) -> [EditablePlaylist] {
        (response.contents?.addToPlaylistRenderer?.playlists ?? []).compactMap { option in
            guard let renderer = option.playlistAddToOptionRenderer,
                  let id = renderer.playlistId else { return nil }
            return EditablePlaylist(
                id: id,
                title: renderer.title?.text ?? "Playlist",
                subtitle: "",
                thumbnailURL: renderer.thumbnail?.bestURL
            )
        }
    }
}
