//
//  Credentials.swift
//  YT Music
//
//  InnerTube session built from web sign-in cookies; produces Cookie and SAPISIDHASH headers.
//

import Foundation
import CryptoKit

nonisolated struct Credentials: Codable, Sendable, Equatable {
    var cookies: [String: String]

    init(cookies: [String: String]) {
        self.cookies = cookies
    }

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

    var sapisid: String? {
        cookies["SAPISID"] ?? cookies["__Secure-3PAPISID"]
    }

    var isUsable: Bool { sapisid != nil }

    var cookieHeader: String {
        cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

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
