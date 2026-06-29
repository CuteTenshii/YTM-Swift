//
//  SignatureDecipherTests.swift
//  YT MusicTests
//
//  Exercises the full signature + n-parameter decipher pipeline against a
//  synthetic player — no network, fully deterministic. The fixture mimics the
//  shape of a real modern base.js: a module IIFE exposing a `g` namespace with a
//  URL class (get/set/clone + a descramble method) and a signer function that
//  builds that URL and sets the `alr=yes` flag (the fingerprint the solver finds).
//  Here the descramble reverses `s` and uppercases `n`, so outputs are trivial.
//

import Testing
import Foundation
@testable import YT_Music

/// Minimal text fixture for the JS-text extraction helpers (see JSExtractionTests):
/// not a real player, just the literal shapes those helpers parse.
let sampleBaseJS = """
var ZZ={ZA:function(a,b){a.reverse()}};
var decodeSig=function(a){a=a.split("");ZZ.ZA(a,7);return a.join("")};
function nTransform(a){return a.toUpperCase()}
var nArr=[nTransform];
var hook=function(b){var c;(c=b.get("n"))&&(c=nArr[0](c))&&b.set("n",c)};
var cfg={signatureTimestamp:20123};
"""

/// Synthetic player whose URL descramble reverses `s` and uppercases `n`.
let samplePlayerJS = """
var _yt_player={};(function(g){
var window=this;
function U(u){this.q={};u=u||"";this.b=u.split("?")[0];var s=u.split("?")[1]||"";var t=this;\
s.split("&").forEach(function(p){if(!p)return;var i=p.indexOf("=");\
t.q[i<0?p:p.slice(0,i)]=decodeURIComponent(i<0?"":p.slice(i+1));});}
U.prototype.get=function(k){return this.q[k];};
U.prototype.set=function(k,v){this.q[k]=v;};
U.prototype.clone=function(){return this;};
U.prototype.descramble=function(){if(this.q.s!=null)this.q.s=this.q.s.split("").reverse().join("");\
if(this.q.n!=null)this.q.n=this.q.n.toUpperCase();};
g.lq=U;
var s2=function(E,T,Z){T=T===void 0?"":T;Z=Z===void 0?"":Z;E=new g.lq(E,!0);E.set("alr","yes");Z&&E.set(T,Z);return E;};
var cfg={signatureTimestamp:20123};
})(_yt_player)
"""

@Suite("Signature decipher")
struct SignatureDecipherTests {

    @Test("Deciphers a signatureCipher: reverses the signature and transforms n")
    func decipherCipher() throws {
        let cipher = "s=0123456789&sp=mysig"
            + "&url=https%3A%2F%2Fr1.example.com%2Fvideoplayback%3Fid%3D42%26n%3DabcDEF"

        let url = try SignatureDecipher.shared.decipheredURL(cipher: cipher, baseJS: samplePlayerJS)

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "r1.example.com")
        #expect(components.path == "/videoplayback")

        let query = queryDictionary(components)
        #expect(query["mysig"] == "9876543210")     // "0123456789" reversed
        #expect(query["n"] == "ABCDEF")             // "abcDEF" uppercased
        #expect(query["id"] == "42")                // untouched
    }

    @Test("Applies the n transform to a direct URL, leaving other params intact")
    func nTransformOnDirectURL() throws {
        let url = try SignatureDecipher.shared.nTransformedURL(
            "https://r2.example.com/vp?n=hello&x=1",
            baseJS: samplePlayerJS
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = queryDictionary(components)
        #expect(query["n"] == "HELLO")
        #expect(query["x"] == "1")
    }

    @Test("Extracts the signatureTimestamp")
    func extractsSignatureTimestamp() {
        #expect(SignatureDecipher.shared.signatureTimestamp(fromBaseJS: samplePlayerJS) == "20123")
    }

    @Test("Throws when the signature function can't be found")
    func missingSignatureFunctionThrows() {
        let cipher = "s=abc&url=https%3A%2F%2Fx.example.com%2Fvp"
        #expect(throws: DecipherError.self) {
            try SignatureDecipher.shared.decipheredURL(cipher: cipher, baseJS: "var unrelated=1;")
        }
    }

    @Test("Leaves the URL unchanged when the solver is absent")
    func missingNFunctionLeavesURLUntouched() throws {
        let url = try SignatureDecipher.shared.nTransformedURL(
            "https://r3.example.com/vp?n=keepme",
            baseJS: "var unrelated=1;"
        )
        let query = queryDictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)!)
        #expect(query["n"] == "keepme")
    }
}

/// Flattens query items into a dictionary for order-independent assertions.
func queryDictionary(_ components: URLComponents) -> [String: String] {
    var result: [String: String] = [:]
    for item in components.queryItems ?? [] {
        result[item.name] = item.value
    }
    return result
}
