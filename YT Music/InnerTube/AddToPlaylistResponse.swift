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
//    contents[].addToPlaylistRenderer.playlists[]
//      .playlistAddToOptionRenderer { playlistId, title, thumbnail }
//
//  `contents` arrives as an *array* of renderer wrappers (the same shape as most
//  InnerTube surfaces), so we decode it as a list. A stray single-object variant
//  is tolerated too — see `Contents.init(from:)`. Every nested field is optional
//  (or resilient to a missing url/text) so one malformed row can't fail the whole
//  decode; unparseable rows are simply dropped by the parser.
//

import Foundation

nonisolated struct AddToPlaylistResponse: Decodable {
    let contents: Contents?

    /// `contents` is normally `[{ addToPlaylistRenderer: … }]`. We flatten every
    /// wrapper's renderers into one list, and also accept a lone object form.
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
        let thumbnail: ThumbnailList?
    }

    /// The option title can arrive as either `runs` or a flat `simpleText`.
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
                subtitle: "",
                thumbnailURL: renderer.thumbnail?.bestURL
            )
        }
    }
}
