//
//  SongCredits.swift
//  YT Music
//

import Foundation

nonisolated struct CreditSection: Sendable, Equatable, Hashable {
    var role: String
    var names: [String]
}
