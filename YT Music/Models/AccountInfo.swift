//
//  AccountInfo.swift
//  YT Music
//
//  The signed-in user's display identity, shown in the sidebar.
//

import Foundation

struct AccountInfo: Sendable, Equatable {
    var name: String
    var handle: String      // "@handle" or email; may be empty
    var avatarURL: URL?
}
