//
//  Handoff.swift
//  YT Music
//
//  Advertises the playing track over Handoff as its music.youtube.com URL, so
//  another device can pick it up in its browser.
//

import Foundation

@MainActor
final class Handoff {
    static let activityType = "moe.tenshii.YT-Music.playing"

    private(set) var activity: NSUserActivity?

    func update(_ snapshot: PlaybackSnapshot?) {
        guard let snapshot,
              let url = MusicLinks.url(videoId: snapshot.videoId, playlistId: nil, browseId: nil)
        else {
            activity?.invalidate()
            activity = nil
            return
        }
        guard activity?.webpageURL != url else { return }
        let activity = activity ?? NSUserActivity(activityType: Self.activityType)
        activity.isEligibleForHandoff = true
        activity.title = snapshot.artist.isEmpty ? snapshot.title : "\(snapshot.title) - \(snapshot.artist)"
        activity.webpageURL = url
        activity.becomeCurrent()
        self.activity = activity
    }
}
