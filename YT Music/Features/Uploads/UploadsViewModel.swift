//
//  UploadsViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class UploadsViewModel {
    enum State {
        case signedOut
        case loading
        case loaded([HomeShelf])
        case failed(String)
    }

    /// The state of an in-flight (or just-finished) upload, shown as a banner.
    enum UploadPhase: Equatable {
        case idle
        case uploading(name: String)
        case succeeded(name: String)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var uploadPhase: UploadPhase = .idle

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    var isUploading: Bool {
        if case .uploading = uploadPhase { return true }
        return false
    }

    func load(isSignedIn: Bool) async {
        guard isSignedIn else {
            state = .signedOut
            return
        }
        state = .loading
        do {
            state = .loaded(try await client.uploads())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Uploads a picked file, then reloads so it (eventually) appears. Newly
    /// uploaded tracks can take a while to finish processing server-side, so the
    /// reload may not show them immediately.
    func upload(fileURL: URL, isSignedIn: Bool) async {
        guard isSignedIn else {
            uploadPhase = .failed(UploadError.notSignedIn.localizedDescription)
            return
        }
        uploadPhase = .uploading(name: fileURL.lastPathComponent)
        do {
            try await client.uploadSong(fileURL: fileURL)
            uploadPhase = .succeeded(name: fileURL.lastPathComponent)
            await load(isSignedIn: isSignedIn)
        } catch {
            uploadPhase = .failed(error.localizedDescription)
        }
    }

    func dismissUploadBanner() {
        uploadPhase = .idle
    }

    /// Deletes an uploaded item (song or album), removing it optimistically and
    /// then server-side via its entity id. Reloads to reflect the true state if
    /// the request fails. No-op for items without a delete token.
    func delete(_ item: HomeItem) async {
        guard let entityId = item.deleteEntityId, case .loaded(var shelves) = state else { return }
        for index in shelves.indices {
            shelves[index].items.removeAll { $0.id == item.id }
        }
        shelves.removeAll { $0.items.isEmpty }
        state = .loaded(shelves)
        do {
            try await client.deleteUpload(entityId: entityId)
        } catch {
            await load(isSignedIn: true)
        }
    }
}
