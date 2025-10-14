import Foundation

/// Represents a glyph with optional contextual information
struct GlyphRule {
    let name: String
    let context: [String]?
    
    init(name: String, context: [String]? = nil) {
        self.name = name
        self.context = context
    }
}
