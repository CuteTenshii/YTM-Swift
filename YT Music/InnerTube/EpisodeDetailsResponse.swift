//
//  EpisodeDetailsResponse.swift
//  YT Music
//
//  Decodable model for browsing `MPPE<videoId>` (a podcast episode's "Details" tab).
//
//  Response path:
//    contents.sectionListRenderer.contents[].musicDescriptionShelfRenderer
//      .header.runs[].text      <- episode title
//      .subheader.runs[]        <- show name + browse endpoint
//      .description.runs[]      <- text, with urlEndpoint runs for links
//

import Foundation

nonisolated struct EpisodeDetailsResponse: Decodable {
    let contents: Contents?

    struct Contents: Decodable {
        let sectionListRenderer: SectionList?
    }

    struct SectionList: Decodable {
        let contents: [Section]?
    }

    struct Section: Decodable {
        let musicDescriptionShelfRenderer: Shelf?
    }

    struct Shelf: Decodable {
        let header: Runs?
        let subheader: Runs?
        let description: Runs?
    }

    struct Runs: Decodable {
        let runs: [Run]?
    }

    struct Run: Decodable {
        let text: String?
        let navigationEndpoint: Endpoint?
    }

    struct Endpoint: Decodable {
        let urlEndpoint: URLEndpoint?
        let browseEndpoint: BrowseEndpoint?
    }

    struct URLEndpoint: Decodable {
        let url: String?
    }

    struct BrowseEndpoint: Decodable {
        let browseId: String?
    }
}

nonisolated enum EpisodeDetailsParser {
    static func parse(_ response: EpisodeDetailsResponse) -> EpisodeDetails? {
        guard let shelf = response.contents?.sectionListRenderer?.contents?
            .lazy.compactMap(\.musicDescriptionShelfRenderer).first else { return nil }

        var description = AttributedString()
        for run in shelf.description?.runs ?? [] {
            guard let text = run.text else { continue }
            var part = AttributedString(text)
            if let url = run.navigationEndpoint?.urlEndpoint?.url.flatMap(URL.init(string:)) {
                part.link = url
            }
            description += part
        }
        guard !description.characters.isEmpty else { return nil }

        let showRun = shelf.subheader?.runs?.first
        let show = showRun.flatMap { run -> EntityLink? in
            guard let name = run.text,
                  let browseId = run.navigationEndpoint?.browseEndpoint?.browseId else { return nil }
            return EntityLink(name: name, browseId: browseId, kind: .podcast)
        }
        return EpisodeDetails(
            title: shelf.header?.runs?.first?.text ?? "",
            show: show,
            showName: showRun?.text ?? "",
            description: description
        )
    }
}
