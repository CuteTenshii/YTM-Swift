//
//  History.swift
//  YT Music
//
//  View-facing model for the listening-history page (`FEmusic_history`), which
//  YouTube groups into date buckets ("Today", "Yesterday", "This week", …), each
//  a flat list of recently played tracks.
//

import Foundation

/// One date bucket of listening history: a title and the tracks played in it.
/// Each section is its own playable queue.
struct HistorySection: Identifiable, Sendable {
    let id = UUID()
    var title: String    // "Today", "Yesterday", "This week", …
    var tracks: [Track]
}
