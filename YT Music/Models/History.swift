//
//  History.swift
//  YT Music
//
//  View-facing model for the listening-history page (`FEmusic_history`), which
//  YouTube groups into date buckets ("Today", "Yesterday", "This week", …), each
//  a flat list of recently played tracks.
//

import Foundation

struct HistorySection: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var tracks: [Track]
}
