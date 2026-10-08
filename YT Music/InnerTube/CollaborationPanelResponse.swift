//
//  CollaborationPanelResponse.swift
//  YT Music
//
//  Decodable model for `get_panel` with an owned playlist's collaboration panel
//  (`PAplaylist_collaborate`, opened from its edit header).
//
//  Response path:
//    content.engagementPanelSectionListRenderer.content.playlistCollaborationViewModel {
//      playlistCollaborationFormSchema.initialValues
//        { isCollaborationEnabled, isAllowNewCollaboratorsEnabled }
//      copyLinkButton.buttonViewModel.onTap.innertubeCommand.copyLinkCommand.shortUrl
//        <- the invite link, "" when none
//      playlistCollaborators[].contentListItemViewModel {
//        title.content, metadata…metadataParts[].text.content ("Owner"),
//        avatar.avatarViewModel.image.sources[].url,
//        rendererContext.commandContext.onTap.innertubeCommand.browseEndpoint.browseId
//      }
//    }
//

import Foundation

nonisolated struct CollaborationPanelResponse: Decodable {
    let content: Content?

    struct Content: Decodable {
        let engagementPanelSectionListRenderer: Panel?
    }

    struct Panel: Decodable {
        let content: PanelContent?
    }

    struct PanelContent: Decodable {
        let playlistCollaborationViewModel: ViewModel?
    }

    struct ViewModel: Decodable {
        let playlistCollaborationFormSchema: FormSchema?
        let copyLinkButton: CopyLinkButton?
        let playlistCollaborators: [Collaborator]?
    }

    struct FormSchema: Decodable {
        let initialValues: InitialValues?

        struct InitialValues: Decodable {
            let isCollaborationEnabled: Bool?
            let isAllowNewCollaboratorsEnabled: Bool?
        }
    }

    struct CopyLinkButton: Decodable {
        let buttonViewModel: ButtonViewModel?

        struct ButtonViewModel: Decodable { let onTap: OnTap? }
        struct OnTap: Decodable { let innertubeCommand: Command? }
        struct Command: Decodable { let copyLinkCommand: CopyLink? }
        struct CopyLink: Decodable { let shortUrl: String? }

        var url: URL? {
            buttonViewModel?.onTap?.innertubeCommand?.copyLinkCommand?.shortUrl
                .flatMap { $0.isEmpty ? nil : URL(string: $0) }
        }
    }

    struct Collaborator: Decodable {
        let contentListItemViewModel: Item?

        struct Item: Decodable {
            let title: TextContent?
            let metadata: Metadata?
            let avatar: Avatar?
            let rendererContext: RendererContext?
        }

        struct RendererContext: Decodable {
            let commandContext: CommandContext?

            struct CommandContext: Decodable { let onTap: OnTap? }
            struct OnTap: Decodable { let innertubeCommand: Command? }
            struct Command: Decodable { let browseEndpoint: Endpoint? }
            struct Endpoint: Decodable { let browseId: String? }

            var browseId: String? { commandContext?.onTap?.innertubeCommand?.browseEndpoint?.browseId }
        }

        struct TextContent: Decodable { let content: String? }

        struct Metadata: Decodable {
            let contentMetadataViewModel: ViewModel?

            struct ViewModel: Decodable { let metadataRows: [Row]? }
            struct Row: Decodable { let metadataParts: [Part]? }
            struct Part: Decodable { let text: TextContent? }

            var text: String {
                (contentMetadataViewModel?.metadataRows ?? [])
                    .flatMap { $0.metadataParts ?? [] }
                    .compactMap { $0.text?.content }
                    .joined(separator: " · ")
            }
        }

        struct Avatar: Decodable {
            let avatarViewModel: ViewModel?

            struct ViewModel: Decodable { let image: Image? }
            struct Image: Decodable { let sources: [Source]? }
            struct Source: Decodable { let url: String? }

            var url: URL? {
                avatarViewModel?.image?.sources?.last?.url.flatMap { URL(string: $0) }
            }
        }
    }
}

nonisolated enum CollaborationPanelParser {
    static func parse(_ response: CollaborationPanelResponse) -> PlaylistCollaboration? {
        guard let model = response.content?.engagementPanelSectionListRenderer?.content?
            .playlistCollaborationViewModel else { return nil }
        let values = model.playlistCollaborationFormSchema?.initialValues
        let collaborators = (model.playlistCollaborators ?? []).compactMap { entry -> PlaylistCollaborator? in
            guard let item = entry.contentListItemViewModel,
                  let name = item.title?.content, !name.isEmpty else { return nil }
            return PlaylistCollaborator(
                name: name,
                role: item.metadata?.text ?? "",
                avatarURL: item.avatar?.url,
                link: item.rendererContext?.browseId.map { EntityLink(name: name, browseId: $0, kind: .profile) }
            )
        }
        return PlaylistCollaboration(
            isEnabled: values?.isCollaborationEnabled ?? false,
            allowsNewCollaborators: values?.isAllowNewCollaboratorsEnabled ?? false,
            inviteURL: model.copyLinkButton?.url,
            collaborators: collaborators
        )
    }
}
