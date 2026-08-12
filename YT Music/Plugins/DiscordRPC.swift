//
//  DiscordRPC.swift
//  YT Music
//
//  Minimal Discord Rich Presence client. Connects to the local Discord IPC
//  socket (`discord-ipc-N` in the temp dir), performs the v1 handshake, and
//  pushes SET_ACTIVITY frames mirroring the now-playing track.
//
//  Protocol: each frame is a little-endian UInt32 opcode + UInt32 byte-length +
//  UTF-8 JSON payload. op 0 = handshake, op 1 = frame (commands), op 2 = close.
//
//  Discord creates `discord-ipc-N` (N = 0…9) in the per-user Darwin temp dir
//  (`$TMPDIR`, e.g. `/var/folders/…/T/`). The App Sandbox is disabled for this
//  app, so that temp dir is the real host one and connecting to the socket is
//  permitted; `candidatePaths()` covers `$TMPDIR` plus the usual fallbacks. The
//  client fails quietly when no socket is found (Discord not running).
//

import Foundation
import Darwin

/// Controls which field feeds the user's status text ("Listening to …") in the
/// member list — see the gateway activity `status_display_type` field.
nonisolated enum DiscordStatusDisplay: String, CaseIterable, Sendable, Identifiable {
    case name       // "Listening to YT Music"
    case state      // "Listening to <state / artist>"
    case details    // "Listening to <details / song>"

    var id: Self { self }

    /// The integer Discord expects in `activity.status_display_type`.
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
        case .state:    "Artist"
        case .details:  "Song"
        }
    }
}

final class DiscordRPC: @unchecked Sendable {
    /// A Discord application ("client") id — controls the app name and art shown
    /// in the presence. Replace with your own from the Discord Developer Portal.
    static let defaultClientID = "1177081335727267940"

    private static let base = "https://music.youtube.com"

    private let queue = DispatchQueue(label: "moe.tenshii.YT-Music.discord-rpc")
    private let clientID: String
    private let pid = Int(ProcessInfo.processInfo.processIdentifier)

    private var fd: Int32 = -1
    private var handshaken = false

    init(clientID: String = defaultClientID) { self.clientID = clientID }

    // MARK: - Public API (thread-safe; serialized onto `queue`)

    /// Mirrors `snapshot` as the user's Discord presence (connecting on demand).
    func update(_ snapshot: PlaybackSnapshot, style: DiscordStatusDisplay = .name) {
        queue.async { [weak self] in self?.syncUpdate(snapshot, style: style) }
    }

    /// Clears the presence but keeps the connection open.
    func clearActivity() {
        queue.async { [weak self] in self?.syncClear() }
    }

    /// Tears down the connection entirely (e.g. when the plugin is disabled).
    func disconnect() {
        queue.async { [weak self] in self?.syncDisconnect() }
    }

    // MARK: - Connection

    private func ensureConnected() -> Bool {
        if fd >= 0 && handshaken { return true }
        if fd < 0 { openSocket() }
        guard fd >= 0 else { return false }
        if !handshaken {
            handshaken = send(op: 0, payload: ["v": 1, "client_id": clientID])
        }
        return handshaken
    }

    private func openSocket() {
        for path in candidatePaths() {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { continue }

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

    /// Likely socket locations: `discord-ipc-0` … `-9` under each temp dir.
    private func candidatePaths() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var dirs = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"].compactMap { env[$0] }
        if let darwinTemp = Self.darwinUserTempDir() { dirs.append(darwinTemp) }
        dirs.append("/tmp")
        // De-dupe while preserving order, then expand to per-index socket paths.
        var seen = Set<String>()
        let bases = dirs.compactMap { dir -> String? in
            let base = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
            return seen.insert(base).inserted ? base : nil
        }
        return bases.flatMap { base in (0..<10).map { "\(base)/discord-ipc-\($0)" } }
    }

    /// The per-user Darwin temp dir (`_CS_DARWIN_USER_TEMP_DIR`, e.g.
    /// `/var/folders/…/T/`) where Discord writes its socket. Canonical even when
    /// `TMPDIR` is absent from the launch environment.
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

    /// Canonical music.youtube.com URL for a browse id. Artists resolve to the
    /// `/channel/<id>` page; `VL…` ids are playlists; everything else is a
    /// `/browse/<id>` page (albums, playlists, …).
    private static func musicURL(browseId: String, kind: HomeItem.Kind) -> String {
        if kind == .artist {
            return "\(base)/channel/\(browseId)"
        }
        if browseId.hasPrefix("VL") {
            return "\(base)/playlist?list=\(browseId.dropFirst(2))"
        }
        return "\(base)/browse/\(browseId)"
    }

    private func syncUpdate(_ s: PlaybackSnapshot, style: DiscordStatusDisplay) {
        guard ensureConnected() else { return }

        // Paused (or otherwise not actually playing) means no presence at all —
        // clear it rather than show a frozen track.
        guard s.isPlaying else {
            syncClear()
            return
        }

        var activity: [String: Any] = [
            "type": 2,  // "Listening to …"
            "details": s.title.isEmpty ? "Unknown track" : s.title,
            "state": s.artist.isEmpty ? "Unknown artist" : s.artist,
            // Which field feeds the "Listening to …" status text in the member
            // list: the app name (default), the state line, or the details line.
            "status_display_type": style.discordValue,
        ]
        // `details_url`/`state_url` make the lines clickable, each pointing at
        // whatever that line shows.
        if !s.videoId.isEmpty { activity["details_url"] = "\(Self.base)/watch?v=\(s.videoId)" }
        if let artist = s.artists.first, !artist.browseId.isEmpty {
            activity["state_url"] = Self.musicURL(browseId: artist.browseId, kind: artist.kind)
        }

        // Show the album (as art hover + click-through) only when the track
        // genuinely has one — `s.albumLink` comes from the response's browse
        // endpoint, unlike the album-context string which can leak a playlist
        // title or stale context onto album-less videos.
        var assets: [String: Any] = [:]
        if let thumb = s.thumbnailURL?.absoluteString { assets["large_image"] = thumb }
        if let album = s.albumLink, !album.browseId.isEmpty {
            assets["large_text"] = album.name
            assets["large_url"] = Self.musicURL(browseId: album.browseId, kind: album.kind)
        }
        activity["assets"] = assets

        // Link out to the track. Button labels must be registered for this
        // client id in the Discord Developer Portal to render.
        if !s.videoId.isEmpty {
            activity["buttons"] = [
                ["label": "Listen on YouTube Music", "url": "\(Self.base)/watch?v=\(s.videoId)"],
            ]
        }

        // Show a live progress bar only while actually playing. The local IPC
        // protocol uses Unix timestamps in seconds (unlike the gateway's ms);
        // Discord renders the elapsed/remaining time from these on its side.
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
        if !ok { syncDisconnect() }
        return ok
    }
}
