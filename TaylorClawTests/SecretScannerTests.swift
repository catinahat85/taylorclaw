import XCTest
@testable import TaylorClaw

final class SecretScannerTests: XCTestCase {

    func testDetectsAnthropicKey() {
        let s = "my key is sk-ant-abcdefghijklmnopqrstuv and that's all"
        let matches = SecretScanner.scan(s)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.provider, "Anthropic")
    }

    func testDetectsOpenAIKey() {
        let s = "try sk-abcdefghijklmnopqrstuv12345678"
        XCTAssertTrue(SecretScanner.contains(s))
    }

    func testDetectsAWSAccessKey() {
        let s = "aws AKIAIOSFODNN7EXAMPLE ok"
        XCTAssertTrue(SecretScanner.contains(s))
    }

    func testDetectsGitHubPAT() {
        let s = "token ghp_abcdefghijklmnopqrstuvwxyz0123456789 yep"
        XCTAssertTrue(SecretScanner.contains(s))
    }

    func testCleanStringHasNoMatches() {
        XCTAssertTrue(SecretScanner.scan("just a normal sentence").isEmpty)
        XCTAssertFalse(SecretScanner.contains(""))
    }

    func testRedactReplacesSecret() {
        let s = "before sk-ant-abcdefghijklmnopqrstuv after"
        let r = SecretScanner.redact(s)
        XCTAssertFalse(r.contains("sk-ant-abcdefghijklmnopqrstuv"))
        XCTAssertTrue(r.contains("[REDACTED]"))
        XCTAssertTrue(r.hasPrefix("before "))
        XCTAssertTrue(r.hasSuffix(" after"))
    }

    func testRedactMultipleSecretsPreservesSurroundingText() {
        let s = "one sk-ant-aaaaaaaaaaaaaaaaaaaa and two sk-ant-bbbbbbbbbbbbbbbbbbbb end"
        let r = SecretScanner.redact(s)
        XCTAssertFalse(r.contains("sk-ant-a"))
        XCTAssertFalse(r.contains("sk-ant-b"))
        XCTAssertTrue(r.hasPrefix("one "))
        XCTAssertTrue(r.hasSuffix(" end"))
    }

    func testDetectsJWT() {
        let s = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefg"
        XCTAssertTrue(SecretScanner.contains(s))
    }
}
