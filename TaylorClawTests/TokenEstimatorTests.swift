import XCTest
@testable import TaylorClaw

final class TokenEstimatorTests: XCTestCase {

    func testEmptyStringIsZero() {
        XCTAssertEqual(TokenEstimator.estimate(""), 0)
    }

    func testShortStringIsAtLeastOne() {
        XCTAssertEqual(TokenEstimator.estimate("a"), 1)
        XCTAssertEqual(TokenEstimator.estimate("abcd"), 1)
    }

    func testRoughlyFourCharsPerToken() {
        // 40 chars -> ~10 tokens
        let s = String(repeating: "x", count: 40)
        XCTAssertEqual(TokenEstimator.estimate(s), 10)
    }

    func testMessageIncludesRoleOverhead() {
        let m = Message(role: .user, content: String(repeating: "x", count: 40))
        // 10 content + 4 role overhead
        XCTAssertEqual(TokenEstimator.estimate(m), 14)
    }

    func testMessagesSumCorrectly() {
        let m1 = Message(role: .user, content: String(repeating: "x", count: 40))
        let m2 = Message(role: .assistant, content: String(repeating: "y", count: 20))
        // (10+4) + (5+4) = 23
        XCTAssertEqual(TokenEstimator.estimate([m1, m2]), 23)
    }

    func testToolEstimateCountsDescriptionAndSchema() {
        let tool = MCPTool(
            name: "echo",
            description: "Echo text back",
            inputSchema: .object(["type": .string("object")])
        )
        XCTAssertGreaterThan(TokenEstimator.estimate(tool), 4)
    }
}
