//
//  EpisodeDetails.swift
//  YT Music
//
//  A podcast episode's description, from its player Details tab.
//

import Foundation

/// A podcast episode's description, from its player "Details" tab.
nonisolated struct EpisodeDetails: Sendable {
    var title: String
    /// The show's page, when linked.
    var show: EntityLink?
    var showName: String
    /// Description text with its links.
    var description: AttributedString
}
