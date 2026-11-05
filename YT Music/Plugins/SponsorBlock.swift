//
//  SponsorBlock.swift
//  YT Music
//
//

import Foundation

nonisolated enum SponsorBlockCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case musicOfftopic = "music_offtopic"
    case sponsor
    case selfpromo
    case interaction
    case intro
    case outro
    case preview
    case filler

    var id: String { rawValue }

    var label: String {
        switch self {
        case .musicOfftopic: String(localized: "plugins.sponsorblock.music_offtopic")
        case .sponsor: String(localized: "plugins.sponsorblock.sponsor")
        case .selfpromo: String(localized: "plugins.sponsorblock.self_promo")
        case .interaction: String(localized: "plugins.sponsorblock.interaction")
        case .intro: String(localized: "plugins.sponsorblock.intro")
        case .outro: String(localized: "plugins.sponsorblock.outro")
        case .preview: String(localized: "plugins.sponsorblock.preview")
        case .filler: String(localized: "plugins.sponsorblock.filler")
        }
    }

    static let defaults: Set<SponsorBlockCategory> = [
        .musicOfftopic, .sponsor, .selfpromo, .interaction, .intro, .outro,
    ]
}

nonisolated struct SponsorSegment: Equatable, Sendable {
    var id: String
    var start: Double
    var end: Double
    var category: SponsorBlockCategory
}

nonisolated enum SponsorBlockAPI {
    static func segmentsURL(videoId: String, categories: Set<SponsorBlockCategory>) -> URL? {
        let list = categories.map { "\"\($0.rawValue)\"" }.sorted().joined(separator: ",")
        var components = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")
        components?.queryItems = [
            URLQueryItem(name: "videoID", value: videoId),
            URLQueryItem(name: "categories", value: "[\(list)]"),
            URLQueryItem(name: "actionTypes", value: #"["skip"]"#),
        ]
        return components?.url
    }

    private struct RawSegment: Decodable {
        var UUID: String
        var segment: [Double]
        var category: String
        var actionType: String?
    }

    /// Drops non-skip actions, unknown categories, and malformed ranges.
    static func decode(_ data: Data) throws -> [SponsorSegment] {
        try JSONDecoder().decode([RawSegment].self, from: data).compactMap { raw in
            guard raw.actionType ?? "skip" == "skip",
                  let category = SponsorBlockCategory(rawValue: raw.category),
                  raw.segment.count == 2, raw.segment[0] < raw.segment[1]
            else { return nil }
            return SponsorSegment(id: raw.UUID, start: raw.segment[0], end: raw.segment[1], category: category)
        }
    }

    static func segmentToSkip(at time: Double, in segments: [SponsorSegment], skipped: Set<String>) -> SponsorSegment? {
        segments.first { time >= $0.start && time < $0.end && !skipped.contains($0.id) }
    }
}

actor SponsorBlockClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? NetworkSession.make()
    }

    func segments(videoId: String, categories: Set<SponsorBlockCategory>) async throws -> [SponsorSegment] {
        guard !categories.isEmpty,
              let url = SponsorBlockAPI.segmentsURL(videoId: videoId, categories: categories)
        else { return [] }
        let (data, response) = try await session.data(from: url)
        // 404 means the video has no segments.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        return try SponsorBlockAPI.decode(data)
    }
}
