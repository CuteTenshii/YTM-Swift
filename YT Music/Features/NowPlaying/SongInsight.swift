//
//  SongInsight.swift
//  YT Music
//
//  An on-device "About this song" explanation, generated from a track's lyrics
//  by Apple Intelligence (the Foundation Models framework). Runs entirely on
//  device — no network, no account — and is only offered when the model is
//  available (Apple-silicon Mac with Apple Intelligence enabled and the model
//  downloaded). The model interprets the lyrics we hand it; it is deliberately
//  NOT asked to recall facts about the song or artist (the on-device model is
//  small and would hallucinate them).
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The view-facing insight the card renders. Kept free of any Foundation Models
/// type so the UI and tests don't depend on model availability.
struct SongInsight: Sendable, Equatable {
    /// One or two sentences on what the song is about.
    var summary: String
    /// The emotional mood in a few words ("Melancholic and hopeful").
    var mood: String
    /// A handful of short key themes.
    var themes: [String]
}

enum SongInsightError: LocalizedError {
    /// Apple Intelligence isn't available on this device / OS.
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: "Apple Intelligence isn't available on this Mac."
        }
    }
}

/// Generates a `SongInsight` from a track's lyrics. Abstracted so the UI can be
/// driven by a fake in tests (the real one needs the on-device model).
protocol SongInsightProviding: Sendable {
    /// Whether the on-device model is ready to generate insights right now.
    var isSupported: Bool { get }
    func insight(title: String, artist: String, lyrics: String) async throws -> SongInsight
}

/// The real explainer, backed by the Foundation Models on-device LLM.
struct SongInsightService: SongInsightProviding {
    /// Lyrics longer than this are truncated before prompting — the on-device
    /// model has a small context window, and the gist is in the first verses.
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
            its chart performance, or its history — if you don't know, say nothing \
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
/// The structured shape the model fills in (guided generation), mapped to the
/// plain `SongInsight` for the UI.
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
