//
//  Downloader.swift
//  YT Music
//
//  Downloads tracks' resolved audio streams to disk. Resolves each stream
//  through the same StreamResolver used for playback (so the user's audio
//  quality preference applies), then streams it to the chosen folder. Handles
//  both single tracks and whole albums/playlists (a batch saved into a
//  per-collection subfolder), one track at a time.
//

import Foundation

@MainActor
@Observable
final class Downloader {
    /// Progress of an in-flight batch (a single track is a batch of one).
    struct Progress: Equatable {
        var collection: String?     // album/playlist name; nil for a single track
        var currentTitle: String
        var index: Int              // 1-based position in the batch
        var total: Int
        var fraction: Double?       // current file's download fraction, if known
    }

    enum Status: Equatable {
        case idle
        case running(Progress)
        case finished(summary: String, folder: URL?)
        case failed(String)
    }

    /// One unit of work resolved from a Track / snapshot.
    private struct Job {
        let videoId: String
        let title: String
        let artist: String
    }

    private(set) var status: Status = .idle
    /// Files saved this session (most recent first), shown in Settings.
    private(set) var completed: [URL] = []
    /// Whether downloading is available (mirrors the Downloader plugin toggle).
    /// Gates the album/playlist buttons in entity pages.
    var isEnabled = false

    private let resolver: StreamResolving
    private var task: Task<Void, Never>?

    init(resolver: StreamResolving? = nil) {
        self.resolver = resolver ?? StreamResolver.shared
    }

    var isBusy: Bool {
        if case .running = status { return true }
        return false
    }

    // MARK: - Entry points

    /// Downloads the now-playing track (a batch of one, no subfolder).
    func download(_ snapshot: PlaybackSnapshot, to directory: URL, preferences: StreamPreferences) {
        start([Job(videoId: snapshot.videoId, title: snapshot.title, artist: snapshot.artist)],
              collection: nil, directory: directory, preferences: preferences)
    }

    /// Downloads every playable track of an album/playlist into a subfolder
    /// named after `collection`.
    func download(_ tracks: [Track], collection: String, to directory: URL, preferences: StreamPreferences) {
        let jobs = tracks.compactMap { track -> Job? in
            guard let videoId = track.videoId else { return nil }
            return Job(videoId: videoId, title: track.title, artist: track.subtitle)
        }
        start(jobs, collection: collection, directory: directory, preferences: preferences)
    }

    func cancel() {
        task?.cancel()
        status = .idle
    }

    // MARK: - Batch run

    private func start(_ jobs: [Job], collection: String?, directory: URL, preferences: StreamPreferences) {
        guard !jobs.isEmpty else { return }
        task?.cancel()
        task = Task { await run(jobs, collection: collection, directory: directory, preferences: preferences) }
    }

    private func run(_ jobs: [Job], collection: String?, directory: URL, preferences: StreamPreferences) async {
        // Albums/playlists land in their own subfolder; single tracks go straight in.
        let targetDir = collection.map { directory.appendingPathComponent(Self.sanitize($0), isDirectory: true) } ?? directory
        if collection != nil {
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        var downloaded = 0
        var failed = 0
        for (offset, job) in jobs.enumerated() {
            if Task.isCancelled { status = .idle; return }
            func report(_ fraction: Double?) {
                status = .running(Progress(
                    collection: collection, currentTitle: job.title,
                    index: offset + 1, total: jobs.count, fraction: fraction
                ))
            }
            report(nil)
            do {
                let url = try await downloadOne(job, to: targetDir, preferences: preferences, progress: report)
                completed.insert(url, at: 0)
                downloaded += 1
            } catch {
                if Task.isCancelled { status = .idle; return }
                failed += 1   // skip the failed track and keep going
            }
        }

        if Task.isCancelled { status = .idle; return }
        var summary = "\(downloaded) saved"
        if failed > 0 { summary += ", \(failed) failed" }
        if let collection { summary = "\(collection): \(summary)" }
        status = .finished(summary: summary, folder: collection != nil ? targetDir : nil)
    }

    /// Resolves and streams a single job to `directory`, reporting progress.
    /// Returns the written file URL.
    private func downloadOne(_ job: Job, to directory: URL, preferences: StreamPreferences,
                             progress: (Double?) -> Void) async throws -> URL {
        let resolved = try await resolver.audioStream(videoId: job.videoId, preferences: preferences)
        try Task.checkCancellation()

        let destination = directory.appendingPathComponent(Self.fileName(for: job))
        let (bytes, response) = try await URLSession.shared.bytes(from: resolved.url)
        let total = response.expectedContentLength

        var buffer = Data()
        if total > 0 { buffer.reserveCapacity(Int(total)) }
        var received: Int64 = 0
        var chunk = Data()
        chunk.reserveCapacity(1 << 16)
        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            received += 1
            if chunk.count >= (1 << 16) {
                buffer.append(chunk)
                chunk.removeAll(keepingCapacity: true)
                progress(total > 0 ? Double(received) / Double(total) : nil)
            }
        }
        buffer.append(chunk)
        try Task.checkCancellation()

        try? FileManager.default.removeItem(at: destination)
        try buffer.write(to: destination, options: .atomic)
        return destination
    }

    // MARK: - Naming

    /// "<artist> - <title>.m4a", with filesystem-illegal characters stripped.
    private static func fileName(for job: Job) -> String {
        let base = job.artist.isEmpty ? job.title : "\(job.artist) - \(job.title)"
        let cleaned = sanitize(base)
        return "\(cleaned.isEmpty ? job.videoId : cleaned).m4a"
    }

    private static func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
