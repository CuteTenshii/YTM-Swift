//
//  AccountInfo.swift
//  YT Music
//
//  The signed-in user's display identity, shown in the sidebar.
//

import Foundation

struct AccountInfo: Sendable, Equatable, Codable {
    var name: String
    var handle: String
    var avatarURL: URL?
}
