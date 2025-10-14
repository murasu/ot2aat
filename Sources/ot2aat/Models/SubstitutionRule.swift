import Foundation

/// Represents a glyph substitution rule
struct SubstitutionRule {
    let source: String
    let targets: [String]
    
    init(source: String, targets: [String]) {
        self.source = source
        self.targets = targets
    }
}
