//
//  SignatureDecipherRealisticTests.swift
//  YT MusicTests
//
//  Exercises the run-the-player solver against fixtures shaped like a real modern
//  base.js (player 5b27766f generation): a module IIFE with a `g` namespace, a
//  URL class, and the signature/n transforms living as a URL-class method — there
//  is no standalone `n` function to extract. These cover the tricky bits the
//  production code must survive:
//    • a DECOY signer that also sets `alr=yes` but throws — must be probed and
//      rejected in favour of the working one;
//    • the real signer written in DECLARATION form (`function NAME(...)`);
//    • the transform reached only by running the player's own URL class.
//

import Testing
import Foundation
@testable import YT_Music

/// Realistic player: a decoy signer (`badSign`, throws) plus the real signer in
/// declaration form (`realSign`). The URL descramble reverses both `s` and `n`.
private let realisticPlayerJS = """
var _yt_player={};(function(g){
var window=this;
function U(u){this.q={};u=u||"";this.b=u.split("?")[0];var s=u.split("?")[1]||"";var t=this;\
s.split("&").forEach(function(p){if(!p)return;var i=p.indexOf("=");\
t.q[i<0?p:p.slice(0,i)]=decodeURIComponent(i<0?"":p.slice(i+1));});}
U.prototype.get=function(k){return this.q[k];};
U.prototype.set=function(k,v){this.q[k]=v;};
U.prototype.clone=function(){return this;};
U.prototype.unscramble=function(){if(this.q.s!=null)this.q.s=this.q.s.split("").reverse().join("");\
if(this.q.n!=null)this.q.n=this.q.n.split("").reverse().join("");};
g.lq=U;
var badSign=function(E,T,Z){E=new g.lq(E,!0);E.set("alr","yes");throw "decoy";};
function realSign(E,T,Z){T=T===void 0?"":T;Z=Z===void 0?"":Z;E=new g.lq(E,!0);E.set("alr","yes");Z&&E.set(T,Z);return E;}
g.signatureTimestamp=19999;
})(_yt_player)
"""

@Suite("Signature decipher (realistic player)")
struct SignatureDecipherRealisticTests {

    @Test("Probes past a decoy signer and uses the working declaration-form signer")
    func decoyRejectedAndDeclarationSignerUsed() throws {
        // "0123456789" reversed → "9876543210"; "abcXYZ" reversed → "ZYXcba".
        let cipher = "s=0123456789&sp=sig"
            + "&url=https%3A%2F%2Fr.example.com%2Fvideoplayback%3Fid%3D7%26n%3DabcXYZ"

        let url = try SignatureDecipher.shared.decipheredURL(cipher: cipher, baseJS: realisticPlayerJS)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = queryDictionary(components)

        #expect(components.host == "r.example.com")
        #expect(query["sig"] == "9876543210")
        #expect(query["n"] == "ZYXcba")
        #expect(query["id"] == "7")
    }

    @Test("Applies the n transform on a direct URL via the realistic player")
    func nTransformOnDirectURL() throws {
        let url = try SignatureDecipher.shared.nTransformedURL(
            "https://r.example.com/vp?n=hello&x=1",
            baseJS: realisticPlayerJS
        )
        let query = queryDictionary(try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)))
        #expect(query["n"] == "olleh")   // "hello" reversed
        #expect(query["x"] == "1")
    }

    @Test("Extracts the signatureTimestamp from a realistic player")
    func realisticTimestamp() {
        #expect(SignatureDecipher.shared.signatureTimestamp(fromBaseJS: realisticPlayerJS) == "19999")
    }
}
