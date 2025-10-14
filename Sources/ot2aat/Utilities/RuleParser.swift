import Foundation

struct RuleParser {
    /// Parse one-to-many rules from a file
    /// Format: source > target1 target2 target3
    static func parseOne2ManyRules(from path: String) throws -> [SubstitutionRule] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw OT2AATError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var rules: [SubstitutionRule] = []
        
        for (lineNumber, line) in content.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse rule: source > target1 target2 ...
            let parts = trimmed.components(separatedBy: ">")
            guard parts.count == 2 else {
                throw OT2AATError.invalidRule("Line \(lineNumber + 1): Expected format 'source > target1 target2 ...'")
            }
            
            let source = parts[0].trimmingCharacters(in: .whitespaces)
            let targets = parts[1]
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            
            guard !source.isEmpty else {
                throw OT2AATError.invalidRule("Line \(lineNumber + 1): Source glyph cannot be empty")
            }
            
            guard !targets.isEmpty else {
                throw OT2AATError.invalidRule("Line \(lineNumber + 1): Must have at least one target glyph")
            }
            
            rules.append(SubstitutionRule(source: source, targets: targets))
        }
        
        if rules.isEmpty {
            throw OT2AATError.invalidRule("No valid rules found in file")
        }
        
        return rules
    }
}
