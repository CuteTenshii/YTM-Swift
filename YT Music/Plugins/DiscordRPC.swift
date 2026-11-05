//
//  DiscordRPC.swift
//  YT Music
//
//  Protocol: little-endian UInt32 opcode + UInt32 length + UTF-8 JSON. op 0 handshake, 1 frame, 2 close.
//

import Foundation
import Darwin

nonisolated enum DiscordStatusDisplay: String, CaseIterable, Sendable, Identifiable {
    case name       // "Listening to YT Music"
    case state      // "Listening to <state / artist>"
    case details    // "Listening to <details / song>"

    var id: Self { self }

    var discordValue: Int {
        switch self {
        case .name:    0
        case .state:   1
        case .details: 2
        }
    }

    var label: String {
        switch self {
        case .name:     "YT Music"
        case .state:    String(localized: "plugins.discord.display.artist")
        case .details:  String(localized: "plugins.discord.display.song")
        }
    }
}

final class DiscordRPC: @unchecked Sendable {
    /// Replace with your own id from the Discord Developer Portal.
    static let defaultClientID = "1177081335727267940"

    private static let base = "https://music.youtube.com"

    private let queue = DispatchQueue(label: "moe.tenshii.YT-Music.discord-rpc")
    private let clientID: String
    private let pid = Int(ProcessInfo.processInfo.processIdentifier)

    private var fd: Int32 = -1
    private var handshaken = false
    /// Rate-limits `openSocket()` retries while Discord isn't running.
    private var lastConnectAttempt: Date?
    private static let reconnectCooldown: TimeInterval = 10
    /// Retries while disconnected so presence returns if Discord launches mid-session.
    private var reconnectTimer: DispatchSourceTimer?
    /// Replayed once a background reconnect succeeds.
    private var pendingActivity: (snapshot: PlaybackSnapshot, style: DiscordStatusDisplay, parseTitle: Bool)?

    init(clientID: String = defaultClientID) { self.clientID = clientID }

    // MARK: - Public API (thread-safe; serialized onto `queue`)

    func update(_ snapshot: PlaybackSnapshot, style: DiscordStatusDisplay = .name,
                parseTitle: Bool = false) {
        queue.async { [weak self] in
            self?.pendingActivity = (snapshot, style, parseTitle)
            self?.syncUpdate(snapshot, style: style, parseTitle: parseTitle)
        }
    }

    func clearActivity() {
        queue.async { [weak self] in
            self?.pendingActivity = nil
            self?.syncClear()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.pendingActivity = nil
            self?.stopReconnectTimer()
            self?.syncDisconnect()
        }
    }

    // MARK: - Connection

    private func ensureConnected() -> Bool {
        if fd >= 0 && handshaken { return true }
        if fd < 0 {
            let now = Date()
            if let last = lastConnectAttempt, now.timeIntervalSince(last) < Self.reconnectCooldown {
                return false
            }
            lastConnectAttempt = now
            openSocket()
        }
        guard fd >= 0 else {
            scheduleReconnectTimer()
            return false
        }
        if !handshaken {
            handshaken = send(op: 0, payload: ["v": 1, "client_id": clientID])
        }
        if handshaken { stopReconnectTimer() }
        return handshaken
    }

    private func scheduleReconnectTimer() {
        guard reconnectTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.reconnectCooldown, repeating: Self.reconnectCooldown)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.ensureConnected() else { return }
            self.stopReconnectTimer()
            if let pending = self.pendingActivity {
                self.syncUpdate(pending.snapshot, style: pending.style, parseTitle: pending.parseTitle)
            }
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func stopReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    private func openSocket() {
        for path in candidatePaths() {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { continue }
            // A write after Discord closes the socket must fail with EPIPE, not kill the app.
            var noSigPipe: Int32 = 1
            _ = setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let capacity = MemoryLayout.size(ofValue: addr.sun_path)
            let copied = path.withCString { cstr -> Bool in
                guard strlen(cstr) < capacity else { return false }
                withUnsafeMutablePointer(to: &addr.sun_path) { raw in
                    raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                        _ = strncpy(dst, cstr, capacity)
                    }
                }
                return true
            }
            guard copied else { close(s); continue }

            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(s, $0, size)
                }
            }
            if result == 0 { fd = s; return }
            close(s)
        }
    }

    /// Sockets are `discord-ipc-0...9` under `$TMPDIR` (the real host dir, as the sandbox is off).
    private func candidatePaths() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var dirs = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"].compactMap { env[$0] }
        if let darwinTemp = Self.darwinUserTempDir() { dirs.append(darwinTemp) }
        dirs.append("/tmp")
        var seen = Set<String>()
        let bases = dirs.compactMap { dir -> String? in
            let base = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
            return seen.insert(base).inserted ? base : nil
        }
        return bases.flatMap { base in (0..<10).map { "\(base)/discord-ipc-\($0)" } }
    }

    /// Per-user Darwin temp dir; canonical even when `TMPDIR` is unset.
    private static func darwinUserTempDir() -> String? {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) == size else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    private func syncDisconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
        handshaken = false
    }

    // MARK: - Frames

    /// `/channel/<id>` for artists, `/browse/<id>` otherwise (`VL` ids are playlists).
    private static func musicURL(browseId: String, kind: ShelfItem.Kind) -> String {
        if kind == .artist {
            return "\(base)/channel/\(browseId)"
        }
        if browseId.hasPrefix("VL") {
            return "\(base)/playlist?list=\(browseId.dropFirst(2))"
        }
        return "\(base)/browse/\(browseId)"
    }

    static func splitTitle(_ title: String) -> (artist: String, track: String)? {
        for sep in [" - ", " – "] {
            guard let range = title.range(of: sep) else { continue }
            let artist = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let track = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !track.isEmpty { return (artist, track) }
        }
        return nil
    }

    private func syncUpdate(_ s: PlaybackSnapshot, style: DiscordStatusDisplay, parseTitle: Bool) {
        guard ensureConnected() else { return }

        // Paused means no presence; clear it rather than show a frozen track.
        guard s.isPlaying else {
            syncClear()
            return
        }

        var title = s.title
        var artist = s.artist
        if parseTitle, let split = Self.splitTitle(s.title) {
            title = split.track
            artist = split.artist
        }
        var artistURL: String?
        if let link = s.artists.first, !link.browseId.isEmpty {
            artistURL = Self.musicURL(browseId: link.browseId, kind: link.kind)
        }

        var activity: [String: Any] = [
            "type": 2,  // "Listening to …"
            "details": title.isEmpty ? String(localized: "plugins.discord.unknown_track") : title,
            "state": artist.isEmpty ? String(localized: "plugins.discord.unknown_artist") : artist,
            // Which field feeds the "Listening to" status text: app name, state, or details.
            "status_display_type": style.discordValue,
        ]
        // `details_url`/`state_url` make each line clickable.
        if !s.videoId.isEmpty { activity["details_url"] = "\(Self.base)/watch?v=\(s.videoId)" }
        if let artistURL { activity["state_url"] = artistURL }

        // Only when the response has an album link; the album context string can leak a playlist title.
        var assets: [String: Any] = [:]
        if let thumb = s.thumbnailURL?.absoluteString { assets["large_image"] = thumb }
        if let album = s.albumLink, !album.browseId.isEmpty {
            assets["large_text"] = album.name
            assets["large_url"] = Self.musicURL(browseId: album.browseId, kind: album.kind)
        }
        activity["assets"] = assets

        // Button labels must be registered for this client id in the Developer Portal.
        if !s.videoId.isEmpty {
            activity["buttons"] = [
                ["label": "Listen on YouTube Music", "url": "\(Self.base)/watch?v=\(s.videoId)"],
            ]
        }

        // IPC uses Unix timestamps in seconds (the gateway uses ms).
        if s.duration > 0 {
            let now = Date().timeIntervalSince1970
            let start = now - s.currentTime
            activity["timestamps"] = [
                "start": Int(start),
                "end": Int(start + s.duration),
            ]
        }

        _ = send(op: 1, payload: [
            "cmd": "SET_ACTIVITY",
            "nonce": UUID().uuidString,
            "args": ["pid": pid, "activity": activity],
        ])
    }

    private func syncClear() {
        guard ensureConnected() else { return }
        _ = send(op: 1, payload: [
            "cmd": "SET_ACTIVITY",
            "nonce": UUID().uuidString,
            "args": ["pid": pid],   // omitting `activity` clears it
        ])
    }

    private func send(op: UInt32, payload: [String: Any]) -> Bool {
        guard fd >= 0,
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        var frame = Data()
        var opLE = op.littleEndian
        var lenLE = UInt32(body.count).littleEndian
        withUnsafeBytes(of: &opLE) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &lenLE) { frame.append(contentsOf: $0) }
        frame.append(body)
        return writeAll(frame)
    }

    private func writeAll(_ data: Data) -> Bool {
        var ok = true
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { ok = false; return }
            var total = 0
            while total < raw.count {
                let n = Darwin.write(fd, base + total, raw.count - total)
                if n <= 0 { ok = false; break }
                total += n
            }
        }
        if !ok {
            // Write failure means Discord dropped the socket; reconnect without waiting for playback.
            syncDisconnect()
            scheduleReconnectTimer()
        }
        return ok
    }
}
