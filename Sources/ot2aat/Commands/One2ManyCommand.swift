import Foundation
import ArgumentParser

struct One2ManyCommand: ParsableCommand, OT2AATCommand {
    static let configuration = CommandConfiguration(
        commandName: "one2many",
        abstract: "Convert one-to-many glyph substitutions (e.g., splitting Sara AM)"
    )
    
    @Option(name: [.short, .long], help: "Output format (mif or atif)")
    var format: OutputFormat
    
    @Option(name: .shortAndLong, help: "Source glyph (for single rule)")
    var source: String?
    
    @Option(name: .shortAndLong, help: "Target glyphs (space-separated, for single rule)")
    var target: [String] = []
    
    @Option(name: .shortAndLong, help: "Input rules file")
    var input: String?
    
    @Option(name: .shortAndLong, help: "Output file (default: stdout)")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Feature name")
    var feature: String
    
    @Option(name: .long, help: "Selector number")
    var selector: Int
    
    var outputFormat: OutputFormat { format }
    var outputFile: String? { output }
    var featureName: String { feature }
    var selectorNumber: Int { selector }
    
    func validate() throws {
        // Must have either single rule or input file
        if source == nil && input == nil {
            throw ValidationError("Must provide either -s/--source or -i/--input")
        }
        
        if source != nil && target.isEmpty {
            throw ValidationError("When using -s/--source, must provide -t/--target")
        }
        
        if source != nil && input != nil {
            throw ValidationError("Cannot use both -s/--source and -i/--input")
        }
    }
    
    func run() throws {
        try execute()
    }
    
    func execute() throws {
        let rules: [SubstitutionRule]
        
        if let source = source {
            // Single rule from command line
            rules = [SubstitutionRule(source: source, targets: target)]
        } else if let inputPath = input {
            // Multiple rules from file
            rules = try RuleParser.parseOne2ManyRules(from: inputPath)
        } else {
            throw OT2AATError.generationFailed("No rules provided")
        }
        
        let result: String
        switch outputFormat {
        case .mif:
            result = try MIFGenerator.generateOne2Many(
                rules: rules,
                featureName: featureName,
                selectorNumber: selectorNumber
            )
        case .atif:
            result = try ATIFGenerator.generateOne2Many(
                rules: rules,
                featureName: featureName,
                selectorNumber: selectorNumber
            )
        }
        
        if let outputPath = outputFile {
            try result.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("✅ Generated \(outputFormat.rawValue.uppercased()) file: \(outputPath)")
        } else {
            print(result)
        }
    }
}
