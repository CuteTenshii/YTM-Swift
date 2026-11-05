//
//  InnerTubeClient.swift
//  YT Music
//

import Foundation
import OSLog

enum InnerTubeError: LocalizedError {
    case badStatus(Int)
    case emptyResponse
    /// An authenticated request was rejected (HTTP 401): the session expired.
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "YouTube Music returned HTTP \(code)."
        case .emptyResponse:       "YouTube Music returned an empty response."
        case .unauthorized:        "Your YouTube Music session expired. Sign in again."
        }
    }
}

extension Notification.Name {
    /// Posted on any thread when a signed request gets HTTP 401; `AuthStore` observes it.
    static let ytmSessionExpired = Notification.Name("moe.tenshii.YT-Music.sessionExpired")

    static let ytmCredentialsChanged = Notification.Name("moe.tenshii.YT-Music.credentialsChanged")
}

enum UploadError: LocalizedError {
    case notSignedIn
    case unsupportedFormat(String)
    case uploadURLMissing
    case failed(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in to upload music."
        case .unsupportedFormat(let ext):
            "Can't upload .\(ext) files. Use MP3, M4A, AAC, FLAC, OGG, or WMA."
        case .uploadURLMissing:
            "YouTube Music didn't return an upload URL."
        case .failed(let code):
            "Upload failed (HTTP \(code))."
        }
    }
}

private nonisolated struct EmptyActionResponse: Decodable {}

private nonisolated struct CreatePlaylistResponse: Decodable {
    let playlistId: String?
}

private nonisolated struct WatchNextInfo: Sendable {
    let lyricsBrowseId: String?
    let relatedBrowseId: String?
    let likeStatus: LikeStatus
    let likeCount: Int?
}

/// Small LRU cache; entries are invalidated on rating change and cleared on sign-in/out.
private actor WatchNextStore {
    private var entries: [String: WatchNextInfo] = [:]
    private var pending: [String: Task<WatchNextInfo, Error>] = [:]
    private var order: [String] = []
    private let limit = 16

    func info(
        for videoId: String,
        fetch: @escaping @Sendable () async throws -> WatchNextInfo
    ) async throws -> WatchNextInfo {
        if let cached = entries[videoId] { return cached }
        if let inFlight = pending[videoId] { return try await inFlight.value }
        let task = Task { try await fetch() }
        pending[videoId] = task
        do {
            let info = try await task.value
            if pending[videoId] == task {
                pending[videoId] = nil
                store(info, for: videoId)
            }
            return info
        } catch {
            if pending[videoId] == task { pending[videoId] = nil }
            throw error
        }
    }

    private func store(_ info: WatchNextInfo, for videoId: String) {
        if entries[videoId] == nil { order.append(videoId) }
        entries[videoId] = info
        while order.count > limit { entries[order.removeFirst()] = nil }
    }

    func invalidate(_ videoId: String) {
        entries[videoId] = nil
        pending[videoId] = nil
        order.removeAll { $0 == videoId }
    }

    func clear() {
        entries.removeAll()
        pending.removeAll()
        order.removeAll()
    }
}

private actor EntitlementStore {
    private(set) var value: Bool?
    func store(_ value: Bool) { self.value = value }
    func clear() { value = nil }
}

private actor VisitorStore {
    private(set) var value: String?
    func store(_ value: String) { self.value = value }
}

private nonisolated struct VisitorResponse: Decodable {
    let responseContext: Context?
    struct Context: Decodable { let visitorData: String? }
}

nonisolated enum PlaylistPrivacy: String, Sendable, CaseIterable {
    case `private` = "PRIVATE"
    case unlisted = "UNLISTED"
    case `public` = "PUBLIC"
}

nonisolated enum LikeStatus: String, Codable, Sendable {
    case indifferent
    case liked
    case disliked

    /// Unknown or nil raw values map to indifferent.
    init(innerTube raw: String?) {
        switch raw {
        case "LIKE":    self = .liked
        case "DISLIKE": self = .disliked
        default:        self = .indifferent
        }
    }
}

protocol LikeProviding: Sendable {
    func setLikeStatus(videoId: String, status: LikeStatus) async throws
    func likeStatus(for videoId: String) async throws -> LikeStatus
    func likeCount(for videoId: String) async throws -> Int?
}

extension InnerTubeClient: LikeProviding {}

protocol LyricsProviding: Sendable {
    func lyrics(for query: LyricsQuery) async throws -> Lyrics?
}

extension InnerTubeClient: LyricsProviding {}

protocol RelatedProviding: Sendable {
    func related(for videoId: String) async throws -> [Shelf]
}

extension InnerTubeClient: RelatedProviding {}

protocol CommentsProviding: Sendable {
    func comments(for videoId: String) async throws -> CommentPage
    func moreComments(token: String) async throws -> CommentPage
    func commentReplies(token: String, parentId: String) async throws -> CommentPage
}

extension InnerTubeClient: CommentsProviding {}

nonisolated final class InnerTubeClient: Sendable, WatchHistoryReporting {
    static let shared = InnerTubeClient()

    // Public constants shipped in the YT Music web bundle.
    private let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private let clientName = "WEB_REMIX"
    private let clientVersion = "1.20260623.13.00"
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    private let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

    private static let log = Logger(category: "requests")
    private let session: URLSession

    private let watchNextCache = WatchNextStore()
    private let visitor = VisitorStore()
    private let entitlement = EntitlementStore()

    init(session: URLSession? = nil) {
        self.session = session ?? NetworkSession.make()
        // Cached like status is account-relative.
        NotificationCenter.default.addObserver(
            forName: .ytmCredentialsChanged, object: nil, queue: nil
        ) { [watchNextCache, entitlement] _ in
            Task {
                await watchNextCache.clear()
                await entitlement.clear()
            }
        }
    }

    func homeFeed() async throws -> HomeFeed {
        try await homeFeed(browseId: "FEmusic_home")
    }

    func homeFeed(browseId: String, params: String? = nil) async throws -> HomeFeed {
        var body: [String: Any] = ["browseId": browseId]
        if let params { body["params"] = params }
        let response: BrowseResponse = try await post(
            "browse",
            body: body
        )
        return HomeFeedParser.parse(response)
    }

    func homeContinuation(_ token: String, visitorData: String?) async throws -> HomeFeed {
        let response: BrowseResponse = try await post(
            "browse",
            body: ["continuation": token],
            visitorData: visitorData
        )
        return HomeFeedParser.parseContinuation(response)
    }

    func explore() async throws -> [Shelf] {
        let response: BrowseResponse = try await post(
            "browse",
            body: ["browseId": "FEmusic_explore"]
        )
        return ExploreParser.parse(response)
    }

    /// Non-`.all` filters return pre-grouped, server-titled shelves.
    func search(_ query: String, filter: SearchFilter = .all) async throws -> [Shelf] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var body: [String: Any] = ["query": trimmed]
        if let params = filter.params { body["params"] = params }
        let response: SearchResponse = try await post("search", body: body)
        return SearchParser.parse(response)
    }

    func searchSuggestions(_ input: String) async throws -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: SearchSuggestionsResponse = try await post(
            "music/get_search_suggestions",
            body: ["input": trimmed]
        )
        return SearchSuggestionsParser.parse(response)
    }

    func entity(_ destination: EntityDestination) async throws -> EntityPage {
        let response: EntityBrowseResponse = try await post(
            "browse",
            body: ["browseId": destination.browseId]
        )
        return EntityPageParser.parse(response, fallback: destination)
    }

    func entityContinuation(
        _ token: String,
        startIndex: Int,
        header: EntityHeader
    ) async throws -> EntityPage {
        let response: EntityBrowseResponse = try await post(
            "browse",
            body: ["continuation": token]
        )
        let next = EntityPageParser.parseContinuation(
            response,
            startIndex: startIndex,
            header: header
        )
        return EntityPage(
            header: header,
            tracks: next.tracks,
            shelves: [],
            continuationToken: next.continuationToken
        )
    }

    func entityTrackReload(_ token: String, header: EntityHeader) async throws -> EntityPage {
        let response: EntityBrowseResponse = try await post("browse", body: ["continuation": token])
        return EntityPageParser.parseTrackReload(response, header: header)
    }

    func entityReload(browseId: String, params: String, fallback: EntityDestination) async throws -> EntityPage {
        let response: EntityBrowseResponse = try await post("browse", body: ["browseId": browseId, "params": params])
        return EntityPageParser.parse(response, fallback: fallback)
    }

    /// Names and IDs only, to avoid creating thousands of rows.
    func playlistFilterMetadata(playlistId: String) async throws -> [Track] {
        let response: PlaylistFilterMetadataResponse = try await post(
            "get_playlist_filter_search_metadata",
            body: ["playlistId": playlistId]
        )
        var seenVideoIds = Set<String>()
        return (response.tracks ?? []).compactMap(\.track).filter { track in
            guard let videoId = track.videoId else { return false }
            return seenVideoIds.insert(videoId).inserted
        }
    }

    func playlistFilterSearch(playlistId: String, tracks: [Track]) async throws -> [Track] {
        let identifiers = tracks.compactMap { track -> [String: String]? in
            guard let videoId = track.videoId,
                  let setVideoId = track.playlistSetVideoId else { return nil }
            return ["videoId": videoId, "encryptedSetVideoId": setVideoId]
        }
        guard !identifiers.isEmpty else { return [] }

        let response: EntityBrowseResponse = try await post(
            "browse",
            body: [
                "browseId": "FEplaylist_filter_search",
                "formData": [
                    "playlistFilterSearchFormData": [
                        "playlistId": playlistId,
                        "playlistVideoItemIdentifiers": identifiers,
                    ],
                ],
            ]
        )
        let fallback = EntityDestination(
            browseId: "VL\(playlistId)", kind: .playlist,
            title: "", subtitle: "", thumbnailURL: nil
        )
        return EntityPageParser.parse(response, fallback: fallback).tracks
    }

    func library(browseId: String = "FEmusic_library_landing", params: String? = nil) async throws -> LibraryPage {
        var body: [String: Any] = ["browseId": browseId]
        if let params { body["params"] = params }
        let response: BrowseResponse = try await post("browse", body: body)
        return LibraryParser.parse(response)
    }

    func libraryContinuation(_ token: String) async throws -> LibraryPage {
        let response: BrowseResponse = try await post("browse", body: ["continuation": token])
        return LibraryParser.parseContinuation(response)
    }

    /// Requires auth; anonymous requests return nothing.
    func uploads() async throws -> [Shelf] {
        let data = try await postData(
            "browse",
            body: ["browseId": "FEmusic_library_privately_owned_landing"]
        )
        let response = try JSONDecoder().decode(BrowseResponse.self, from: data)
        let shelves = UploadsParser.parse(response)
        if shelves.isEmpty {
            // Dump empty responses to Caches/yt-uploads.json to diagnose the layout.
            let path = DebugDump.write(data, to: "yt-uploads.json") ?? "(dump failed)"
            Self.log.problem("uploads: parsed 0 shelves - dumped response to \(path)")
        } else {
            Self.log.note("uploads: parsed \(shelves.count) shelves")
        }
        return shelves
    }

    /// Two-step resumable upload to `upload.youtube.com`; tracks appear in `uploads()` after transcoding.
    func uploadSong(fileURL: URL) async throws {
        let headers = await CredentialStore.shared.requestHeaders()
        guard !headers.isEmpty else { throw UploadError.notSignedIn }

        let ext = fileURL.pathExtension.lowercased()
        guard Self.uploadableExtensions.contains(ext) else {
            throw UploadError.unsupportedFormat(ext)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let authUser = headers["X-Goog-AuthUser"] ?? "0"

        var startComponents = URLComponents(string: "https://upload.youtube.com/upload/usermusic/http")!
        startComponents.queryItems = [URLQueryItem(name: "authuser", value: authUser)]
        var start = URLRequest(url: startComponents.url!)
        start.httpMethod = "POST"
        for (header, value) in headers { start.setValue(value, forHTTPHeaderField: header) }
        start.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        start.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue(String(size), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.httpBody = Data("filename=\(fileURL.lastPathComponent)".utf8)

        let (_, startResponse) = try await session.data(for: start)
        guard let startHTTP = startResponse as? HTTPURLResponse else { throw InnerTubeError.emptyResponse }
        Self.log.note("upload: start → HTTP \(startHTTP.statusCode) for \(fileURL.lastPathComponent) (\(size) bytes)")
        guard (200..<300).contains(startHTTP.statusCode) else { throw UploadError.failed(startHTTP.statusCode) }
        guard let uploadURLString = startHTTP.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            Self.log.problem("upload: no X-Goog-Upload-URL header in start response")
            throw UploadError.uploadURLMissing
        }

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        for (header, value) in headers { upload.setValue(value, forHTTPHeaderField: header) }
        upload.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        upload.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        upload.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")

        let (uploadBody, uploadResponse) = try await session.upload(for: upload, fromFile: fileURL)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse else { throw InnerTubeError.emptyResponse }
        let status = uploadHTTP.value(forHTTPHeaderField: "X-Goog-Upload-Status") ?? "?"
        Self.log.note("upload: finalize → HTTP \(uploadHTTP.statusCode), upload-status=\(status)")
        guard (200..<300).contains(uploadHTTP.statusCode) else {
            let bodyText = String(data: uploadBody.prefix(400), encoding: .utf8) ?? ""
            Self.log.problem("upload: finalize failed \(uploadHTTP.statusCode) - \(bodyText)")
            throw UploadError.failed(uploadHTTP.statusCode)
        }
    }

    static let uploadableExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "ogg", "wma"]

    /// Requires auth; anonymous requests return no history.
    func history() async throws -> [HistorySection] {
        let response: BrowseResponse = try await post(
            "browse",
            body: ["browseId": "FEmusic_history"]
        )
        return HistoryParser.parse(response)
    }

    func accountInfo() async throws -> AccountInfo? {
        let response: AccountMenuResponse = try await post("account/account_menu", body: [:])
        return AccountInfoParser.parse(response)
    }

    /// `signatureTimestamp` must match the player JS used to decipher.
    func player(videoId: String, signatureTimestamp: String?, playlistId: String? = nil) async throws -> PlayerResponse {
        var body: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]
        if let playlistId {
            body["playlistId"] = playlistId
        }
        if let signatureTimestamp, let sts = Int(signatureTimestamp) {
            body["playbackContext"] = [
                "contentPlaybackContext": ["signatureTimestamp": sts]
            ]
        }
        return try await post("player", body: body)
    }

    func signedOutPlayer(videoId: String) async throws -> PlayerResponse {
        try await post(
            "player",
            body: ["videoId": videoId, "contentCheckOk": true, "racyCheckOk": true],
            client: visionOS,
            authenticated: false,
            visitorData: try await visitorData()
        )
    }

    /// Members' `SPunlimited` page shows a "Manage" button; others get a sign-up offer.
    func hasPremium() async -> Bool {
        if let known = await entitlement.value { return known }
        guard let data = try? await postData("browse", body: ["browseId": "SPunlimited"]) else { return false }

        func hasManageButton(_ node: Any) -> Bool {
            if let dict = node as? NSDictionary {
                if let header = dict["lpHeaderSectionViewModel"] as? NSDictionary {
                    let path = "primaryButton.buttonViewModel.onTap.innertubeCommand.browseEndpoint.browseId"
                    return header.value(forKeyPath: path) as? String == "FEmemberships_and_purchases"
                }
                return dict.allValues.contains(where: hasManageButton)
            }
            if let array = node as? [Any] { return array.contains(where: hasManageButton) }
            return false
        }
        let premium = (try? JSONSerialization.jsonObject(with: data)).map(hasManageButton) ?? false
        await entitlement.store(premium)
        return premium
    }

    private func visitorData() async throws -> String {
        if let cached = await visitor.value { return cached }
        let response: VisitorResponse = try await post("visitor_id", body: [:], client: web, authenticated: false)
        guard let value = response.responseContext?.visitorData else { throw InnerTubeError.emptyResponse }
        await visitor.store(value)
        return value
    }

    /// Resend the returned continuation via `continueRadio` to keep the same mix going.
    func radio(for videoId: String) async throws -> RadioPage {
        // RDAMVM<id> is this song's radio.
        let response = try await nextResponse(videoId: videoId, playlistId: MixIds.songRadio(for: videoId))
        return RadioPage(tracks: WatchNextParser.parse(response), continuation: WatchNextParser.continuationToken(response))
    }

    func continueRadio(_ token: String) async throws -> RadioPage {
        let response: RadioContinuationResponse = try await post("next", body: ["continuation": token])
        return RadioPage(tracks: WatchNextParser.parse(response), continuation: WatchNextParser.continuationToken(response))
    }

    func watchQueue(videoId: String, playlistId: String) async throws -> [Track] {
        WatchNextParser.parse(try await nextResponse(videoId: videoId, playlistId: playlistId))
    }

    private func nextResponse(videoId: String, playlistId: String) async throws -> WatchNextResponse {
        try await post(
            "next",
            body: [
                "videoId": videoId,
                "playlistId": playlistId,
                "isAudioOnly": true,
                "enablePersistentPlaylistPanel": true,
                "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            ]
        )
    }

    private func watchNextInfo(for videoId: String) async throws -> WatchNextInfo {
        try await watchNextCache.info(for: videoId) { [self] in
            let response: WatchNextResponse = try await post("next", body: ["videoId": videoId])
            return WatchNextInfo(
                lyricsBrowseId: WatchNextParser.lyricsBrowseId(response),
                relatedBrowseId: WatchNextParser.relatedBrowseId(response),
                likeStatus: WatchNextParser.likeStatus(response, expecting: videoId),
                likeCount: WatchNextParser.likeCount(response)
            )
        }
    }

    /// Two steps: `next` yields the lyrics tab browse id (`MPLYt…`), then browse it.
    func lyrics(for query: LyricsQuery) async throws -> Lyrics? {
        guard let browseId = try await watchNextInfo(for: query.videoId).lyricsBrowseId else {
            return nil
        }
        let response: LyricsResponse = try await post("browse", body: ["browseId": browseId])
        return LyricsParser.parse(response)
    }

    func credits(videoId: String) async throws -> [CreditSection] {
        let response: CreditsResponse = try await post("browse", body: ["browseId": "MPTC" + videoId])
        return CreditsParser.parse(response)
    }

    func episodeDetails(videoId: String) async throws -> EpisodeDetails? {
        let response: EpisodeDetailsResponse = try await post("browse", body: ["browseId": "MPPE" + videoId])
        return EpisodeDetailsParser.parse(response)
    }

    /// Two steps: the `next` Related tab browse id (`MPTRt…`), then browse it.
    func related(for videoId: String) async throws -> [Shelf] {
        guard let browseId = try await watchNextInfo(for: videoId).relatedBrowseId else {
            return []
        }
        let response: BrowseResponse = try await post("browse", body: ["browseId": browseId])
        return RelatedParser.parse(response)
    }

    /// Resolves a channel handle (`@name`, with or without the `@`) to its page.
    func resolveHandle(_ handle: String) async throws -> EntityLink? {
        let name = handle.hasPrefix("@") ? handle : "@" + handle
        let data = try await postData(
            "navigation/resolve_url",
            body: ["url": "https://www.youtube.com/\(name)"],
            client: web, authenticated: false)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoint = json["endpoint"] as? [String: Any],
              let browse = endpoint["browseEndpoint"] as? [String: Any],
              let browseId = browse["browseId"] as? String else { return nil }
        return EntityLink(name: name, browseId: browseId, kind: .artist)
    }

    /// Comments use the anonymous `web` client; the WEB_REMIX `next` has no comments panel.
    func comments(for videoId: String) async throws -> CommentPage {
        let token: CommentsTokenResponse = try await post(
            "next", body: ["videoId": videoId], client: web, authenticated: false)
        guard let continuation = CommentsParser.continuationToken(token) else { return .empty }
        return try await moreComments(token: continuation)
    }

    func moreComments(token: String) async throws -> CommentPage {
        let response: CommentsResponse = try await post(
            "next", body: ["continuation": token], client: web, authenticated: false)
        return CommentsParser.parse(response)
    }

    /// `parentId` is excluded since the reply feed can echo the parent.
    func commentReplies(token: String, parentId: String) async throws -> CommentPage {
        let response: CommentsResponse = try await post(
            "next", body: ["continuation": token], client: web, authenticated: false)
        return CommentsParser.parseReplies(response, excluding: parentId)
    }

    /// Requires auth; the request is a no-op server-side without session headers.
    func setSubscription(channelId: String, params: String?, subscribe: Bool) async throws {
        let endpoint = subscribe ? "subscription/subscribe" : "subscription/unsubscribe"
        var body: [String: Any] = ["channelIds": [channelId]]
        if let params { body["params"] = params }
        let _: EmptyActionResponse = try await post(endpoint, body: body)
    }

    func setLikeStatus(videoId: String, status: LikeStatus) async throws {
        let endpoint = switch status {
        case .liked:       "like/like"
        case .disliked:    "like/dislike"
        case .indifferent: "like/removelike"
        }
        let _: EmptyActionResponse = try await post(
            endpoint,
            body: ["target": ["videoId": videoId]]
        )
        // Cached info carries the now-stale rating.
        await watchNextCache.invalidate(videoId)
    }

    /// Uses the `like/*` endpoints with a `playlistId` target.
    func setPlaylistSaved(playlistId: String, saved: Bool) async throws {
        let endpoint = saved ? "like/like" : "like/removelike"
        let _: EmptyActionResponse = try await post(
            endpoint,
            body: ["target": ["playlistId": playlistId]]
        )
    }

    // MARK: - Playlist editing

    /// Editable playlists only (excludes saved-but-not-owned and "Liked Music").
    func addToPlaylistOptions(videoId: String) async throws -> [EditablePlaylist] {
        let data = try await postData(
            "playlist/get_add_to_playlist",
            body: ["videoIds": [videoId], "excludeWatchLater": true]
        )
        do {
            let response = try JSONDecoder().decode(AddToPlaylistResponse.self, from: data)
            return AddToPlaylistParser.parse(response)
        } catch {
            // Dump decode failures to Caches/yt-add-to-playlist.json to diagnose the layout.
            let path = DebugDump.write(data, to: "yt-add-to-playlist.json") ?? "(dump failed)"
            Self.log.problem("add-to-playlist: decode failed (\(error)) - dumped response to \(path)")
            throw error
        }
    }

    @discardableResult
    func createPlaylist(title: String, videoIds: [String] = []) async throws -> String {
        var body: [String: Any] = ["title": title, "privacyStatus": "PRIVATE"]
        if !videoIds.isEmpty { body["videoIds"] = videoIds }
        let response: CreatePlaylistResponse = try await post("playlist/create", body: body)
        guard let id = response.playlistId else { throw InnerTubeError.emptyResponse }
        return id
    }

    func deletePlaylist(playlistId: String) async throws {
        let _: EmptyActionResponse = try await post(
            "playlist/delete",
            body: ["playlistId": playlistId]
        )
    }

    func renamePlaylist(playlistId: String, title: String) async throws {
        try await editPlaylist(playlistId: playlistId, actions: [
            ["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": title]
        ])
    }

    /// Nil fields produce no action.
    func updatePlaylist(
        playlistId: String,
        title: String? = nil,
        description: String? = nil,
        privacy: PlaylistPrivacy? = nil,
        votePermission: Int? = nil
    ) async throws {
        var actions: [[String: Any]] = []
        if let title {
            actions.append(["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": title])
        }
        if let description {
            actions.append([
                "action": "ACTION_SET_PLAYLIST_DESCRIPTION",
                "playlistDescription": description,
            ])
        }
        if let privacy {
            actions.append([
                "action": "ACTION_SET_PLAYLIST_PRIVACY",
                "playlistPrivacy": privacy.rawValue,
            ])
        }
        if let votePermission {
            actions.append(["action": "ACTION_SET_ALLOW_ITEM_VOTE", "itemVotePermission": votePermission])
        }
        try await editPlaylist(playlistId: playlistId, actions: actions)
    }

    /// Duplicate adds are an idempotent server no-op.
    func addToPlaylist(playlistId: String, videoIds: [String]) async throws {
        guard !videoIds.isEmpty else { return }
        try await editPlaylist(
            playlistId: playlistId,
            actions: videoIds.map { ["action": "ACTION_ADD_VIDEO", "addedVideoId": $0] }
        )
    }

    /// Remove needs both `videoId` and the playlist-scoped `setVideoId`.
    func removeFromPlaylist(
        playlistId: String,
        items: [(videoId: String, setVideoId: String)]
    ) async throws {
        guard !items.isEmpty else { return }
        try await editPlaylist(
            playlistId: playlistId,
            actions: items.map {
                [
                    "action": "ACTION_REMOVE_VIDEO",
                    "removedVideoId": $0.videoId,
                    "setVideoId": $0.setVideoId,
                ]
            }
        )
    }

    /// A nil `successor` moves the track to the end.
    func movePlaylistItem(playlistId: String, setVideoId: String, before successor: String?) async throws {
        var action: [String: Any] = ["action": "ACTION_MOVE_VIDEO_BEFORE", "setVideoId": setVideoId]
        if let successor { action["movedSetVideoIdSuccessor"] = successor }
        try await editPlaylist(playlistId: playlistId, actions: [action])
    }

    // MARK: - Playlist collaboration

    /// Each load issues a fresh invite link while new collaborators are allowed.
    func collaboration(panel: CollaborationPanelRef) async throws -> PlaylistCollaboration {
        let response: CollaborationPanelResponse = try await post(
            "get_panel",
            body: ["panelId": panel.panelId, "params": panel.params]
        )
        guard let collaboration = CollaborationPanelParser.parse(response) else {
            throw InnerTubeError.emptyResponse
        }
        return collaboration
    }

    func setCollaborationEnabled(playlistId: String, _ enabled: Bool) async throws {
        try await editPlaylist(playlistId: playlistId, actions: [
            enabled
                ? ["action": "ACTION_CREATE_COLLABORATION_INVITE_LINK"]
                : ["action": "ACTION_SET_CLOSED_TO_CONTRIBUTIONS", "closedToContributions": true],
        ])
    }

    func setAllowsNewCollaborators(playlistId: String, _ allowed: Bool) async throws {
        try await editPlaylist(playlistId: playlistId, actions: [
            ["action": allowed ? "ACTION_CREATE_COLLABORATION_INVITE_LINK" : "ACTION_REVOKE_COLLABORATION_TOKENS"],
        ])
    }

    func sortPlaylist(playlistId: String, by edit: PlaylistSortEdit) async throws {
        try await editPlaylist(
            playlistId: playlistId,
            actions: [["action": edit.action, edit.field: edit.value]],
            params: edit.params
        )
    }

    func votePlaylistItem(token: String) async throws {
        let _: EmptyActionResponse = try await post("feedback", body: ["feedbackTokens": [token]])
    }

    private func editPlaylist(playlistId: String, actions: [[String: Any]], params: String? = nil) async throws {
        var body: [String: Any] = ["playlistId": playlistId, "actions": actions]
        if let params { body["params"] = params }
        let _: EmptyActionResponse = try await post("browse/edit_playlist", body: body)
    }

    // MARK: - History / uploads editing

    /// Passing every row's token clears the whole history.
    func removeHistoryItems(feedbackTokens: [String]) async throws {
        guard !feedbackTokens.isEmpty else { return }
        let _: EmptyActionResponse = try await post(
            "feedback",
            body: ["feedbackTokens": feedbackTokens]
        )
    }

    func deleteUpload(entityId: String) async throws {
        let _: EmptyActionResponse = try await post(
            "music/delete_privately_owned_entity",
            body: ["entityId": entityId]
        )
    }

    func likeStatus(for videoId: String) async throws -> LikeStatus {
        guard await CredentialStore.shared.isSignedIn else { return .indifferent }
        return try await watchNextInfo(for: videoId).likeStatus
    }

    func likeCount(for videoId: String) async throws -> Int? {
        try await watchNextInfo(for: videoId).likeCount
    }

    /// No-op when signed out; history is per-account.
    func reportPlaybackStart(playbackURL: URL, cpn: String, position: Double, length: Double?) async {
        let headers = await CredentialStore.shared.requestHeaders()
        guard !headers.isEmpty else { return }
        if let url = WatchHistory.playbackURL(base: playbackURL, cpn: cpn, position: position,
                                              length: length, client: statsClientParams) {
            await ping(url, credentialHeaders: headers)
        }
    }

    func reportWatchtime(watchtimeURL: URL, cpn: String, position: Double, length: Double?) async {
        let headers = await CredentialStore.shared.requestHeaders()
        guard !headers.isEmpty else { return }
        if let url = WatchHistory.watchtimeURL(base: watchtimeURL, cpn: cpn, position: position,
                                               length: length, client: statsClientParams) {
            await ping(url, credentialHeaders: headers)
        }
    }

    /// Beacons need `c=WEB_REMIX` to count as a Music listen (lands in YTM History).
    private var statsClientParams: [String: String] {
        [
            "c": clientName,            // WEB_REMIX
            "cver": clientVersion,
            "cplayer": "UNIPLAYER",
            "cos": "Macintosh",
            "cosver": "10_15_7",
            "cplatform": "DESKTOP",
            "cbrand": "apple",
            "cbr": "Chrome",
            "cbrver": "149.0.0.0",
            "hl": "en",
        ]
    }

    private func ping(_ url: URL, credentialHeaders: [String: String]) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyClientHeaders(to: &request)
        for (header, value) in credentialHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        _ = try? await session.data(for: request)
    }

    // MARK: - Request plumbing

    private struct ClientProfile {
        let baseURL: URL
        let clientName: String        // context.client.clientName
        let clientVersion: String
        let clientNameHeader: String  // X-YouTube-Client-Name
        let origin: String
        let apiKey: String?
        var userAgent: String?
        var device: [String: String] = [:]
    }

    private var webRemix: ClientProfile {
        ClientProfile(baseURL: baseURL, clientName: clientName, clientVersion: clientVersion,
                      clientNameHeader: "67", origin: "https://music.youtube.com", apiKey: apiKey)
    }

    /// Comments live only on the www.youtube.com web client.
    private let web = ClientProfile(
        baseURL: URL(string: "https://www.youtube.com/youtubei/v1/")!,
        clientName: "WEB",
        clientVersion: "2.20240620.05.00",
        clientNameHeader: "1",
        origin: "https://www.youtube.com",
        apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    )

    /// Signed-out playback: WEB_REMIX streams need a PO token without Premium; these don't.
    private static let visionOSUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    /// Needs a visitor id or it asks to sign in; stream URLs come unciphered.
    private let visionOS = ClientProfile(
        baseURL: URL(string: "https://www.youtube.com/youtubei/v1/")!,
        clientName: "VISIONOS",
        clientVersion: "1.02",
        clientNameHeader: "101",
        origin: "https://www.youtube.com",
        apiKey: nil,
        userAgent: InnerTubeClient.visionOSUserAgent,
        device: [
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "userAgent": InnerTubeClient.visionOSUserAgent,
            "osName": "visionOS",
            "osVersion": "26.5.23O471",
        ]
    )

    /// `authenticated: false` omits session headers; the WEB origin wouldn't match the Music SAPISIDHASH.
    private func post<T: Decodable>(
        _ endpoint: String,
        body: [String: Any],
        client: ClientProfile? = nil,
        authenticated: Bool = true,
        visitorData: String? = nil
    ) async throws -> T {
        let data = try await postData(
            endpoint, body: body, client: client, authenticated: authenticated, visitorData: visitorData
        )
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postData(
        _ endpoint: String,
        body: [String: Any],
        client: ClientProfile? = nil,
        authenticated: Bool = true,
        visitorData: String? = nil
    ) async throws -> Data {
        let profile = client ?? webRemix
        var components = URLComponents(
            url: profile.baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        if let apiKey = profile.apiKey {
            components.queryItems?.append(URLQueryItem(name: "key", value: apiKey))
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyClientHeaders(to: &request, client: profile)

        if let visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        var payload = body
        payload["context"] = context(client: profile, visitorData: visitorData)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Credentials are empty when signed out, so unauthenticated requests are unaffected.
        var didAttachCredentials = false
        if authenticated {
            let credentialHeaders = await CredentialStore.shared.requestHeaders()
            didAttachCredentials = !credentialHeaders.isEmpty
            for (header, value) in credentialHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }
        }

        let started = ContinuousClock.now
        let target = (body["browseId"] as? String) ?? (body["continuation"] == nil ? nil : "continuation")
        let label = "\(Date.now.formatted(.iso8601)) \(endpoint)\(target.map { " \($0)" } ?? "") (\(profile.clientName))"
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            let elapsed = started.duration(to: .now).description
            Self.log.error("\(label, privacy: .public) failed after \(elapsed, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        let elapsed = started.duration(to: .now).description
        Self.log.notice("\(label, privacy: .public) HTTP \(status), \(data.count) bytes, \(elapsed, privacy: .public)")

        if let http = urlResponse as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            // A 401 on a signed request means the session expired.
            if http.statusCode == 401, didAttachCredentials {
                Self.log.problem("auth: 401 on \(endpoint) - session expired")
                NotificationCenter.default.post(name: .ytmSessionExpired, object: nil)
                throw InnerTubeError.unauthorized
            }
            throw InnerTubeError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw InnerTubeError.emptyResponse }

        return data
    }

    /// Content-Type is set per-request since stats pings are GETs.
    private func applyClientHeaders(to request: inout URLRequest, client: ClientProfile? = nil) {
        let profile = client ?? webRemix
        request.setValue(profile.origin, forHTTPHeaderField: "Origin")
        request.setValue(profile.origin + "/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(profile.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(profile.clientNameHeader, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(profile.userAgent ?? userAgent, forHTTPHeaderField: "User-Agent")
    }

    private func context(client: ClientProfile? = nil, visitorData: String? = nil) -> [String: Any] {
        let profile = client ?? webRemix
        var clientContext: [String: Any] = [
            "clientName": profile.clientName,
            "clientVersion": profile.clientVersion,
            "hl": "en",
            "gl": "US",
        ]
        clientContext.merge(profile.device) { current, _ in current }
        if let visitorData { clientContext["visitorData"] = visitorData }
        return ["client": clientContext, "user": [:]]
    }
}
