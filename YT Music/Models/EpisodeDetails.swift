//
//  EpisodeDetails.swift
//  YT Music
//
//  A podcast episode's description, from its player Details tab.
//

import Foundation

nonisolated struct EpisodeDetails: Sendable {
    var title: String
    var show: EntityLink?
    var showName: String
    var description: AttributedString
}
