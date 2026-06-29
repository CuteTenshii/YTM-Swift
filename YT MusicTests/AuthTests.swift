//
//  AuthTests.swift
//  YT MusicTests
//
//  Tests for the pure authentication logic: cookie parsing, header building, and
//  the SAPISIDHASH scheme. (Keychain / WKWebView paths aren't unit-tested.)
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Credentials")
struct CredentialsTests {

    private let origin = "https://music.youtube.com"
    private let fixedDate = Date(timeIntervalSince1970: 1000)

    @Test("Builds Cookie + SAPISIDHASH headers when a SAPISID is present")
    func authHeaders() {
        let creds = Credentials(cookies: ["SAPISID": "secret", "SID": "x"])
        let headers = creds.requestHeaders(now: fixedDate, origin: origin)

        #expect(headers["Cookie"] == "SAPISID=secret; SID=x")
        #expect(headers["X-Goog-AuthUser"] == "0")

        let auth = headers["Authorization"]
        #expect(auth?.hasPrefix("SAPISIDHASH 1000_") == true)
        let hash = auth?.split(separator: "_").last.map(String.init) ?? ""
        #expect(hash.count == 40)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("Sends cookies but no Authorization when SAPISID is missing")
    func cookiesWithoutSapisid() {
        let creds = Credentials(cookies: ["SID": "x"])
        let headers = creds.requestHeaders(now: fixedDate)
        #expect(headers["Cookie"] == "SID=x")
        #expect(headers["Authorization"] == nil)
    }

    @Test("Empty jar yields no headers")
    func emptyHeaders() {
        #expect(Credentials(cookies: [:]).requestHeaders(now: fixedDate).isEmpty)
    }

    @Test("SAPISID is preferred over the 3P variant")
    func sapisidPreference() {
        let creds = Credentials(cookies: ["__Secure-3PAPISID": "threep", "SAPISID": "primary"])
        #expect(creds.sapisid == "primary")
        #expect(Credentials(cookies: ["__Secure-3PAPISID": "threep"]).sapisid == "threep")
    }

    @Test("SAPISIDHASH is deterministic and sensitive to the SAPISID")
    func sapisidHashStability() {
        let a = Credentials.sapisidHash(sapisid: "s1", origin: origin, now: fixedDate)
        let b = Credentials.sapisidHash(sapisid: "s1", origin: origin, now: fixedDate)
        let c = Credentials.sapisidHash(sapisid: "s2", origin: origin, now: fixedDate)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Cookie jar from HTTPCookies keeps only google/youtube cookies")
    func httpCookieFiltering() {
        let cookies = [
            cookie(domain: ".youtube.com", name: "SAPISID", value: "abc"),
            cookie(domain: ".google.com", name: "SID", value: "def"),
            cookie(domain: ".example.com", name: "OTHER", value: "nope"),
        ].compactMap { $0 }

        let creds = Credentials(httpCookies: cookies)
        #expect(creds.cookies["SAPISID"] == "abc")
        #expect(creds.cookies["SID"] == "def")
        #expect(creds.cookies["OTHER"] == nil)
        #expect(creds.isUsable)
    }

    @Test("Round-trips through Codable")
    func codableRoundTrip() throws {
        let creds = Credentials(cookies: ["SAPISID": "abc", "SID": "def"])
        let data = try JSONEncoder().encode(creds)
        let decoded = try JSONDecoder().decode(Credentials.self, from: data)
        #expect(decoded == creds)
    }

    private func cookie(domain: String, name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
        ])
    }
}
