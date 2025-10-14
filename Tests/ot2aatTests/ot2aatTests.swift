import XCTest
@testable import ot2aat

final class ot2aatTests: XCTestCase {
    func testSubstitutionRuleCreation() {
        let rule = SubstitutionRule(source: "uni0E33", targets: ["uni0E4D", "uni0E32"])
        XCTAssertEqual(rule.source, "uni0E33")
        XCTAssertEqual(rule.targets.count, 2)
    }
    
    func testRuleParserWithValidInput() throws {
        let tempFile = NSTemporaryDirectory() + "test_rules.txt"
        let content = """
        # Test rules file
        uni0E33 > uni0E4D uni0E32
        uni0E4D > uni0E19 uni0E4A
        
        # Another comment
        """
        
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        
        let rules = try RuleParser.parseOne2ManyRules(from: tempFile)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].source, "uni0E33")
        XCTAssertEqual(rules[0].targets, ["uni0E4D", "uni0E32"])
        
        try? FileManager.default.removeItem(atPath: tempFile)
    }
}
