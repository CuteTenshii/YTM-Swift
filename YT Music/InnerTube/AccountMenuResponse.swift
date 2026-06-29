//
//  AccountMenuResponse.swift
//  YT Music
//
//  Decodable models + parser for the InnerTube `account/account_menu` endpoint,
//  which (when authenticated) returns the active account's name, handle, and
//  avatar in an `activeAccountHeaderRenderer`.
//
//  Path:
//    actions[].openPopupAction.popup.multiPageMenuRenderer.header
//      .activeAccountHeaderRenderer { accountName, channelHandle/email, accountPhoto }
//

import Foundation

struct AccountMenuResponse: Decodable {
    let actions: [Action]?

    struct Action: Decodable {
        let openPopupAction: OpenPopup?
    }

    struct OpenPopup: Decodable {
        let popup: Popup?
    }

    struct Popup: Decodable {
        let multiPageMenuRenderer: MultiPageMenu?
    }

    struct MultiPageMenu: Decodable {
        let header: Header?
    }

    struct Header: Decodable {
        let activeAccountHeaderRenderer: ActiveAccount?
    }

    struct ActiveAccount: Decodable {
        let accountName: InnerTubeText?
        let email: InnerTubeText?
        let channelHandle: InnerTubeText?
        let accountPhoto: Photo?
    }

    struct Photo: Decodable {
        let thumbnails: [Thumbnail]?

        struct Thumbnail: Decodable {
            let url: String
            let width: Int?
            let height: Int?
        }
    }
}

nonisolated enum AccountInfoParser {
    static func parse(_ response: AccountMenuResponse) -> AccountInfo? {
        let account = response.actions?
            .compactMap { $0.openPopupAction?.popup?.multiPageMenuRenderer?.header?.activeAccountHeaderRenderer }
            .first

        guard let account else { return nil }

        let name = account.accountName?.text ?? ""
        guard !name.isEmpty else { return nil }

        let handle = firstNonEmpty(account.channelHandle?.text, account.email?.text)

        let avatarURL = (account.accountPhoto?.thumbnails ?? [])
            .max { ($0.width ?? 0) < ($1.width ?? 0) }
            .flatMap { URL(string: $0.url) }

        return AccountInfo(name: name, handle: handle, avatarURL: avatarURL)
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
}
