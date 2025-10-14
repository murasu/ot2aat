import Foundation

protocol OT2AATCommand {
    var outputFormat: OutputFormat { get }
    var outputFile: String? { get }
    var featureName: String { get }
    var selectorNumber: Int { get }
    
    func execute() throws
}

enum OutputFormat: String, ExpressibleByArgument {
    case mif = "mif"
    case atif = "atif"
}

enum OT2AATError: LocalizedError {
    case invalidRule(String)
    case fileNotFound(String)
    case invalidGlyphName(String)
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidRule(let msg): return "Invalid rule: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidGlyphName(let name): return "Invalid glyph name: \(name)"
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        }
    }
}
