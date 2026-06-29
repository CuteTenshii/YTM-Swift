//
//  JSExtractionTests.swift
//  YT MusicTests
//
//  Unit tests for the base.js text-extraction helpers (regex + brace matching),
//  independent of any JavaScript execution.
//

import Testing
@testable import YT_Music

@Suite("JS extraction")
struct JSExtractionTests {
    private let decipher = SignatureDecipher.shared

    @Test("functionLiteral captures a full function assigned to a name")
    func functionLiteralAssignment() throws {
        let literal = try #require(decipher.functionLiteral(named: "decodeSig", in: sampleBaseJS))
        #expect(literal.hasPrefix("function"))
        #expect(literal.contains(#"a.split("")"#))
        #expect(literal.contains(#"a.join("")"#))
        #expect(literal.hasSuffix("}"))
    }

    @Test("functionLiteral captures a function declaration")
    func functionLiteralDeclaration() throws {
        let literal = try #require(decipher.functionLiteral(named: "nTransform", in: sampleBaseJS))
        #expect(literal.contains("toUpperCase"))
    }

    @Test("objectLiteral captures a balanced object body")
    func objectLiteralBalanced() throws {
        let literal = try #require(decipher.objectLiteral(named: "ZZ", in: sampleBaseJS))
        #expect(literal == "{ZA:function(a,b){a.reverse()}}")
    }

    @Test("arrayElement resolves an index into an array literal")
    func arrayElementResolution() throws {
        let element = try #require(decipher.arrayElement(named: "nArr", index: 0, in: sampleBaseJS))
        #expect(element == "nTransform")
    }

    @Test("Brace matching ignores braces inside string literals")
    func braceMatchingSkipsStrings() throws {
        let js = #"var Q=function(a){var s="}{)(";return a};"#
        let literal = try #require(decipher.functionLiteral(named: "Q", in: js))
        #expect(literal == #"function(a){var s="}{)(";return a}"#)
    }

    @Test("Returns nil for an unknown name")
    func unknownNameReturnsNil() {
        #expect(decipher.functionLiteral(named: "doesNotExist", in: sampleBaseJS) == nil)
        #expect(decipher.objectLiteral(named: "doesNotExist", in: sampleBaseJS) == nil)
    }
}
