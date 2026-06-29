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
            return URL(string: "\(base)/browse/\(browseId)")
        }
        return nil
    }
}
