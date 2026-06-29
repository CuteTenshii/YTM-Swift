//
//  Credentials.swift
//  YT Music
//
//  Authenticated session for InnerTube requests. Built from the cookies captured
//  during web sign-in. Knows how to turn those cookies into the headers Google's
//  private API expects:
//    • `Cookie` — the raw cookie jar.
//    • `Authorization: SAPISIDHASH <ts>_<sha1>` — a per-request hash of the
//      timestamp, the SAPISID cookie, and the origin (same scheme the YT Music
//      web client uses; see ytmusicapi's `get_authorization`).
//

import Foundation
import CryptoKit

nonisolated struct Credentials: Codable, Sendable, Equatable {
    /// Cookie name → value, for the google.com / youtube.com jar.
    var cookies: [String: String]

    init(cookies: [String: String]) {
        self.cookies = cookies
    }

    /// Builds credentials from cookies captured in the login web view, keeping
    /// only the google/youtube jar.
    init(httpCookies: [HTTPCookie]) {
        var jar: [String: String] = [:]
        for cookie in httpCookies where Credentials.isRelevant(cookie) {
            jar[cookie.name] = cookie.value
        }
        self.cookies = jar
    }

    private static func isRelevant(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain.contains("google.com") || domain.contains("youtube.com")
    }

    /// The SAPISID used to sign requests (falls back to the 3P variant).
    var sapisid: String? {
        cookies["SAPISID"] ?? cookies["__Secure-3PAPISID"]
    }

    /// Whether this looks like a usable signed-in session.
    var isUsable: Bool { sapisid != nil }

    /// `name=value; name2=value2`, key-sorted for deterministic output.
    var cookieHeader: String {
        cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    /// Headers to attach to an authenticated InnerTube request.
    func requestHeaders(
        now: Date,
        origin: String = "https://music.youtube.com"
    ) -> [String: String] {
        guard !cookies.isEmpty else { return [:] }

        var headers = ["Cookie": cookieHeader]
        if let sapisid {
            headers["Authorization"] = Credentials.sapisidHash(
                sapisid: sapisid,
                origin: origin,
                now: now
            )
            headers["X-Goog-AuthUser"] = "0"
        }
        return headers
    }

    /// `SAPISIDHASH <ts>_<sha1hex(ts + " " + sapisid + " " + origin)>`.
    static func sapisidHash(sapisid: String, origin: String, now: Date) -> String {
        let timestamp = Int(now.timeIntervalSince1970)
        let payload = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hex)"
    }
}
