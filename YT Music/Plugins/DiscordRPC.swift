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
//  NOTE: under the App Sandbox the process's temp dir is redirected to its
//  container, so Discord's socket isn't visible. Reaching a running Discord
//  therefore requires relaxing the sandbox (or a temporary-exception
//  entitlement). The client fails quietly when no socket is found.
//

import Foundation
import Darwin

final class DiscordRPC: @unchecked Sendable {
    /// A Discord application ("client") id — controls the app name and art shown
    /// in the presence. Replace with your own from the Discord Developer Portal.
    static let defaultClientID = "1126349523890221107"

    private let queue = DispatchQueue(label: "moe.tenshii.YT-Music.discord-rpc")
    private let clientID: String
    private let pid = Int(ProcessInfo.processInfo.processIdentifier)

    private var fd: Int32 = -1
    private var handshaken = false

    init(clientID: String = defaultClientID) { self.clientID = clientID }

    // MARK: - Public API (thread-safe; serialized onto `queue`)

    /// Mirrors `snapshot` as the user's Discord presence (connecting on demand).
    func update(_ snapshot: PlaybackSnapshot) {
        queue.async { [weak self] in self?.syncUpdate(snapshot) }
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
        dirs.append("/tmp")
        return dirs.flatMap { dir -> [String] in
            let base = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
            return (0..<10).map { "\(base)/discord-ipc-\($0)" }
        }
    }

    private func syncDisconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
        handshaken = false
    }

    // MARK: - Frames

    private func syncUpdate(_ s: PlaybackSnapshot) {
        guard ensureConnected() else { return }

        var activity: [String: Any] = [
            "type": 2,  // "Listening to …"
            "details": s.title.isEmpty ? "Unknown track" : s.title,
            "state": s.artist.isEmpty ? "Unknown artist" : s.artist,
        ]
        var assets: [String: Any] = [
            "large_text": s.album.isEmpty ? s.title : s.album,
        ]
        if let thumb = s.thumbnailURL?.absoluteString { assets["large_image"] = thumb }
        activity["assets"] = assets

        // Show a live progress bar only while actually playing.
        if s.isPlaying, s.duration > 0 {
            let now = Date().timeIntervalSince1970
            let start = now - s.currentTime
            activity["timestamps"] = [
                "start": Int(start * 1000),
                "end": Int((start + s.duration) * 1000),
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
