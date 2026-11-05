//
//  SignatureDecipher.swift
//  YT Music
//
//  FRAGILE: relies on the `.set("alr","yes")` fingerprint and the IIFE shape; yt-dlp's ejs solver is the reference.

import Foundation
import OSLog
import JavaScriptCore

enum DecipherError: LocalizedError {
    case playerURLNotFound
    case baseJSDownloadFailed
    case signatureFunctionNotFound
    case jsEvaluationFailed(String)
    case malformedStreamURL

    var errorDescription: String? {
        switch self {
        case .playerURLNotFound:         String(localized: "error.decipher.player_url")
        case .baseJSDownloadFailed:      String(localized: "error.decipher.download")
        case .signatureFunctionNotFound: String(localized: "error.decipher.signature")
        case .jsEvaluationFailed(let m): String(format: String(localized: "error.decipher.evaluation"), m)
        case .malformedStreamURL:        String(localized: "error.decipher.malformed_url")
        }
    }
}

actor SignatureDecipher {
    private static let log = Logger(category: "playback")
    static let shared = SignatureDecipher()

    private struct Solver {
        let context: JSContext
        let signatureTimestamp: String?
        let signerIndex: Int?
        var canSolve: Bool { signerIndex != nil }
    }

    private var cached: Solver?
    private let session = NetworkSession.make()

    private let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

    // Tail of the player module; the solver is injected before it to close over `g`/`window`.
    private static let iifeClose = "})(_yt_player)"

    // Probe input; must come back changed and non-empty.
    private static let probeSample = "1234567890abcdefAB"

    // MARK: - Public API

    func signatureTimestamp() async throws -> String? {
        try await solver().signatureTimestamp
    }

    func streamURL(for format: PlayerResponse.Format) async throws -> URL {
        let solver = try await solver()

        if let cipher = format.cipherString {
            Self.log.note("format has signatureCipher - deciphering")
            return try decipheredURL(cipher: cipher, solver: solver)
        }
        if let urlString = format.url, var components = URLComponents(string: urlString) {
            Self.log.note("format has a direct url - applying n transform only")
            applyNTransform(to: &components, solver: solver)
            guard let url = components.url else { throw DecipherError.malformedStreamURL }
            return url
        }
        throw DecipherError.malformedStreamURL
    }

    // MARK: - Solver setup

    private func solver() async throws -> Solver {
        if let cached { return cached }

        let playerURL = try await fetchPlayerURL()
        Self.log.note("player JS: \(playerURL.absoluteString)")
        let js = try await fetchText(playerURL)
        let solver = buildSolver(fromBaseJS: js)
        cached = solver
        return solver
    }

    private nonisolated func buildSolver(fromBaseJS js: String) -> Solver {
        let signatureTimestamp = firstMatch(
            in: js,
            pattern: #"signatureTimestamp[=:](\d+)"#,
            group: 1
        )

        let context = JSContext()!
        context.exceptionHandler = { _, exception in
            Self.log.problem("JS exception: \(exception?.toString() ?? "?")")
        }
        context.evaluateScript(Self.setupScript)

        let signerIndex = installSolver(js, into: context)

        Self.log.note(
            "base.js \(js.count) chars · sts=\(signatureTimestamp ?? "nil") · "
            + "canSolve=\(signerIndex != nil)"
        )
        if signerIndex == nil, let path = DebugDump.write(Data(js.utf8), to: "yt-base.js") {
            Self.log.problem("dumped base.js (solver missing) → \(path)")
        }

        return Solver(
            context: context,
            signatureTimestamp: signatureTimestamp,
            signerIndex: signerIndex
        )
    }

    private nonisolated func installSolver(_ js: String, into context: JSContext) -> Int? {
        let candidates = signerCandidates(in: js)
        Self.log.note("solver: signer candidates \(candidates)")

        let script: String
        if let range = js.range(of: Self.iifeClose, options: .backwards) {
            script = js.replacingCharacters(
                in: range,
                with: solverInjection(candidates: candidates) + Self.iifeClose
            )
        } else {
            // Not a recognizable player module; nowhere to inject a solver.
            script = js
        }
        context.evaluateScript(script)

        if let err = context.objectForKeyedSubscript("__ytSolveErr"), !err.isUndefined {
            Self.log.problem("solver: injection error - \(err.toString() ?? "?")")
        }
        guard let solveWith = context.objectForKeyedSubscript("__ytSolveWith"),
              !solveWith.isUndefined else {
            return nil
        }

        for index in candidates.indices {
            guard let result = solveWith.call(withArguments: [index, NSNull(), Self.probeSample]),
                  let n = result.objectForKeyedSubscript("n"), n.isString,
                  let transformed = n.toString(),
                  !transformed.isEmpty, transformed != Self.probeSample else {
                Self.log.note("solver: candidate '\(candidates[index])' rejected")
                continue
            }
            Self.log.note("solver: using signer '\(candidates[index])' (index \(index))")
            return index
        }
        Self.log.problem("solver: no candidate produced a working n transform")
        return nil
    }

    /// Decoys may share the `alr=yes` flag, so all candidates are returned and probed.
    private nonisolated func signerCandidates(in js: String) -> [String] {
        let patterns = [
            #"([\w$]+)\s*=\s*function\([^)]*\)\s*\{[^{}]*?\.set\(\s*"alr"\s*,\s*"yes"\s*\)"#,
            #"function\s+([\w$]+)\s*\([^)]*\)\s*\{[^{}]*?\.set\(\s*"alr"\s*,\s*"yes"\s*\)"#,
        ]
        var result: [String] = []
        for pattern in patterns {
            for name in allMatches(in: js, pattern: pattern, group: 1) where !result.contains(name) {
                result.append(name)
            }
        }
        return result
    }

    /// Injected inside the IIFE: sig and `n` transforms only exist as methods on the player's URL class.
    private nonisolated func solverInjection(candidates: [String]) -> String {
        """
        ;try{
        window.__ytCands=[\(candidates.joined(separator: ","))];
        window.__ytSolveWith=function(fi,sig,n){
          try{
            var F=window.__ytCands[fi];
            var url=F("https://youtube.com/watch?v=yt-dlp-wins","s",sig?encodeURIComponent(sig):void 0);
            url.set("n",n);
            var proto=Object.getPrototypeOf(url);
            var keys=Object.keys(proto).concat(Object.getOwnPropertyNames(proto));
            for(var i=0;i<keys.length;i++){var k=keys[i];
              if(k!=="constructor"&&k!=="set"&&k!=="get"&&k!=="clone"){url[k]();break;}}
            var s=url.get("s");
            return {sig:s?decodeURIComponent(s):null,n:(url.get("n")==null?null:url.get("n"))};
          }catch(e){return {sig:null,n:null};}
        };
        }catch(e){window.__ytSolveErr=String(e);}
        """
    }

    // MARK: - Solving

    private nonisolated func solve(
        sig: String?,
        n: String?,
        solver: Solver
    ) -> (sig: String?, n: String?) {
        guard let index = solver.signerIndex,
              let fn = solver.context.objectForKeyedSubscript("__ytSolveWith"), !fn.isUndefined,
              let result = fn.call(withArguments: [index, sig ?? NSNull(), n ?? NSNull()]) else {
            return (nil, nil)
        }
        let s = result.objectForKeyedSubscript("sig")
        let nn = result.objectForKeyedSubscript("n")
        return (
            (s?.isString == true) ? s?.toString() : nil,
            (nn?.isString == true) ? nn?.toString() : nil
        )
    }

    // MARK: - Cipher handling

    nonisolated private func decipheredURL(cipher: String, solver: Solver) throws -> URL {
        // The cipher is itself a query string: s=<sig>&sp=<param>&url=<encoded url>.
        var cipherComponents = URLComponents()
        cipherComponents.percentEncodedQuery = cipher
        let items = cipherComponents.queryItems ?? []

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let scrambled = value("s"),
              let urlString = value("url"),
              var components = URLComponents(string: urlString) else {
            throw DecipherError.malformedStreamURL
        }
        let sigParam = value("sp") ?? "signature"

        guard solver.canSolve else { throw DecipherError.signatureFunctionNotFound }

        var query = components.queryItems ?? []
        let nIndex = query.firstIndex { $0.name == "n" }
        let nValue = nIndex.flatMap { query[$0].value }

        let result = solve(sig: scrambled, n: nValue, solver: solver)
        guard let signature = result.sig else {
            throw DecipherError.jsEvaluationFailed("signer returned no signature")
        }

        query.append(URLQueryItem(name: sigParam, value: signature))
        if let nIndex, let transformed = result.n, !transformed.isEmpty {
            query[nIndex].value = transformed
        }
        components.queryItems = query

        guard let url = components.url else { throw DecipherError.malformedStreamURL }
        return url
    }

    /// Best-effort: leaves the URL untouched if the solver is unavailable.
    /// `n` is mandatory: googlevideo returns 403 without the transformed value.
    private nonisolated func applyNTransform(to components: inout URLComponents, solver: Solver) {
        guard solver.canSolve,
              var query = components.queryItems,
              let index = query.firstIndex(where: { $0.name == "n" }),
              let original = query[index].value else {
            return
        }
        let result = solve(sig: nil, n: original, solver: solver)
        guard let transformed = result.n, !transformed.isEmpty else { return }
        query[index].value = transformed
        components.queryItems = query
    }

    // MARK: - Player URL / download

    private func fetchPlayerURL() async throws -> URL {
        let iframeURL = URL(string: "https://www.youtube.com/iframe_api")!
        let body = try await fetchText(iframeURL)
            .replacingOccurrences(of: #"\/"#, with: "/")

        guard let id = firstMatch(in: body, pattern: #"player/([\w-]{6,})/"#, group: 1) else {
            throw DecipherError.playerURLNotFound
        }
        let urlString = "https://www.youtube.com/s/player/\(id)/player_ias.vflset/en_US/base.js"
        guard let url = URL(string: urlString) else { throw DecipherError.playerURLNotFound }
        return url
    }

    private func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DecipherError.baseJSDownloadFailed
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw DecipherError.baseJSDownloadFailed
        }
        return text
    }

    // MARK: - Browser stubs

    /// JavaScriptCore is bare ECMAScript; stub the browser globals base.js touches at load.
    private static let setupScript = """
    var globalThis=(function(){return this})();
    if(typeof globalThis.console==='undefined')globalThis.console={
        log:function(){},warn:function(){},error:function(){},debug:function(){},info:function(){}
    };
    if(typeof globalThis.setTimeout==='undefined')
        globalThis.setTimeout=function(){return 0};
    if(typeof globalThis.clearTimeout==='undefined')globalThis.clearTimeout=function(){};
    if(typeof globalThis.setInterval==='undefined')globalThis.setInterval=function(){return 0};
    if(typeof globalThis.clearInterval==='undefined')globalThis.clearInterval=function(){};
    if(typeof globalThis.XMLHttpRequest==='undefined'){globalThis.XMLHttpRequest=function(){};globalThis.XMLHttpRequest.prototype={};}
    if(typeof globalThis.location==='undefined')globalThis.location={
        hash:'',host:'www.youtube.com',hostname:'www.youtube.com',
        href:'https://www.youtube.com/watch?v=yt-dlp-wins',
        origin:'https://www.youtube.com',password:'',pathname:'/watch',port:'',
        protocol:'https:',search:'?v=yt-dlp-wins',username:''
    };
    if(typeof globalThis.document==='undefined')globalThis.document=Object.create(null);
    if(typeof globalThis.navigator==='undefined')globalThis.navigator={userAgent:'Mozilla/5.0'};
    if(typeof globalThis.self==='undefined')globalThis.self=globalThis;
    if(typeof globalThis.window==='undefined')globalThis.window=globalThis;
    """

    // MARK: - Testing seams (network-free)

    nonisolated func decipheredURL(cipher: String, baseJS: String) throws -> URL {
        try decipheredURL(cipher: cipher, solver: buildSolver(fromBaseJS: baseJS))
    }

    nonisolated func nTransformedURL(_ urlString: String, baseJS: String) throws -> URL {
        guard var components = URLComponents(string: urlString) else {
            throw DecipherError.malformedStreamURL
        }
        applyNTransform(to: &components, solver: buildSolver(fromBaseJS: baseJS))
        guard let url = components.url else { throw DecipherError.malformedStreamURL }
        return url
    }

    nonisolated func signatureTimestamp(fromBaseJS js: String) -> String? {
        firstMatch(in: js, pattern: #"signatureTimestamp[=:](\d+)"#, group: 1)
    }
}
