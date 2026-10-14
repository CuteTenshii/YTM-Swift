//
//  MusicLinks.swift
//  YT Music
//
//  Builds canonical music.youtube.com URLs for sharing / opening in a browser.
//

import Foundation

enum MusicLinks {
    private static let base = "https://music.youtube.com"

    /// Best public URL for an item, given whatever identifiers we have.
    static func url(videoId: String?, playlistId: String?, browseId: String?) -> URL? {
        if let videoId {
            var string = "\(base)/watch?v=\(videoId)"
            if let playlistId { string += "&list=\(playlistId)" }
            return URL(string: string)
        }
        if let playlistId {
            return URL(string: "\(base)/playlist?list=\(playlistId)")
        }
        if let browseId {
            // Playlist browse ids are "VL<playlistId>"; map them to a playlist link.
            if browseId.hasPrefix("VL") {
                return URL(string: "\(base)/playlist?list=\(browseId.dropFirst(2))")
            }
            if browseId.hasPrefix("UC") {
                return URL(string: "\(base)/channel/\(browseId)")
            }
            return URL(string: "\(base)/browse/\(browseId)")
        }
        return nil
    }

    /// What a YouTube / YT Music link points at, when the app can open it itself.
    enum Target: Equatable {
        case handle(String)
        case entity(EntityLink)
        case watch(videoId: String, playlistId: String?)
    }

    static func target(for url: URL) -> Target? {
        guard let host = url.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return nil }
        let id = parts.dropFirst().first
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        func query(_ name: String) -> String? { items?.first { $0.name == name }?.value }
        if first.hasPrefix("@") { return .handle(first) }
        switch (first, id) {
        case ("channel", let id?):
            return .entity(EntityLink(name: "", browseId: id, kind: .artist))
        case ("browse", let id?):
            let kind: HomeItem.Kind = id.hasPrefix("MPRE") ? .album : id.hasPrefix("UC") ? .artist : .unknown
            return .entity(EntityLink(name: "", browseId: id, kind: kind))
        case ("watch", _):
            guard let videoId = query("v") else { return nil }
            return .watch(videoId: videoId, playlistId: query("list"))
        case ("playlist", _):
            guard let list = query("list") else { return nil }
            return .entity(EntityLink(name: "", browseId: "VL" + list, kind: .playlist))
        default:
            return nil
        }
    }
}
