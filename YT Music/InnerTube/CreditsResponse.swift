//
//  CreditsResponse.swift
//  YT Music
//
//  Decodable model for browsing `MPTC<videoId>` (the "View song credits" page).
//
//  Response path:
//    onResponseReceivedActions[].openPopupAction.popup.dismissableDialogRenderer
//      .sections[].dismissableDialogContentSectionRenderer
//        .title.runs[].text      <- role, e.g. "Written by"
//        .subtitle.runs[].text   <- names, separated by "\n" runs
//
//  Music videos come back with no `sections` at all.
//

import Foundation

nonisolated struct CreditsResponse: Decodable {
    let onResponseReceivedActions: [Action]?

    struct Action: Decodable {
        let openPopupAction: OpenPopup?
    }

    struct OpenPopup: Decodable {
        let popup: Popup?
    }

    struct Popup: Decodable {
        let dismissableDialogRenderer: Dialog?
    }

    struct Dialog: Decodable {
        let sections: [Section]?
    }

    struct Section: Decodable {
        let dismissableDialogContentSectionRenderer: ContentSection?
    }

    struct ContentSection: Decodable {
        let title: InnerTubeText?
        let subtitle: InnerTubeText?
    }
}

nonisolated enum CreditsParser {
    static func parse(_ response: CreditsResponse) -> [CreditSection] {
        (response.onResponseReceivedActions ?? [])
            .compactMap { $0.openPopupAction?.popup?.dismissableDialogRenderer }
            .flatMap { $0.sections ?? [] }
            .compactMap { section in
                guard let content = section.dismissableDialogContentSectionRenderer,
                      let role = content.title?.text, !role.isEmpty else { return nil }
                let names = (content.subtitle?.text ?? "")
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return names.isEmpty ? nil : CreditSection(role: role, names: names)
            }
    }
}
