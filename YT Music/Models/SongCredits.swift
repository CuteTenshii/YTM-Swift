//
//  SongCredits.swift
//  YT Music
//

import Foundation

/// One role in a track's credits ("Written by") and the people credited.
nonisolated struct CreditSection: Sendable, Equatable, Hashable {
    var role: String
    var names: [String]
}
