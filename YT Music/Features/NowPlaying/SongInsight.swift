//
//  SongInsight.swift
//  YT Music
//
//  On-device "About this song" insight from lyrics via Foundation Models.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SongInsight: Sendable, Equatable {
    var summary: String
    var mood: String
    var themes: [String]
}

enum SongInsightError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: "Apple Intelligence isn't available on this Mac."
        }
    }
}

protocol SongInsightProviding: Sendable {
    var isSupported: Bool { get }
    func insight(title: String, artist: String, lyrics: String) async throws -> SongInsight
}

struct SongInsightService: SongInsightProviding {
    private let maxLyricsCharacters = 2_000

    var isSupported: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func insight(title: String, artist: String, lyrics: String) async throws -> SongInsight {
        #if canImport(FoundationModels)
        guard isSupported else { throw SongInsightError.unsupported }

        let session = LanguageModelSession {
            """
            You explain songs to a curious listener, working ONLY from the lyrics \
            you are given. Never invent facts about the artist, the song's release, \
            its chart performance, or its history. If you don't know, say nothing \
            about it. Focus on what the words express: their imagery, story, and \
            feeling. Keep it concise, warm, and neutral.
            """
        }

        let trimmed = String(lyrics.prefix(maxLyricsCharacters))
        let prompt = """
        Song: "\(title)" by \(artist)

        Lyrics:
        \(trimmed)
        """

        let response = try await session.respond(to: prompt, generating: GeneratedInsight.self)
        let generated = response.content
        return SongInsight(
            summary: generated.summary,
            mood: generated.mood,
            themes: generated.themes
        )
        #else
        throw SongInsightError.unsupported
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
private struct GeneratedInsight {
    @Guide(description: "One or two sentences explaining what the song is about, based only on the lyrics.")
    var summary: String

    @Guide(description: "The emotional mood of the song in two or three words, e.g. 'Melancholic and hopeful'.")
    var mood: String

    @Guide(description: "Two to four short key themes, each a single word or brief phrase.")
    var themes: [String]
}
#endif
