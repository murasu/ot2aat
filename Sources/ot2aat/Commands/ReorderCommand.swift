import Foundation
import ArgumentParser

struct ReorderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reorder",
        abstract: "Convert glyph reordering rules to AAT rearrangement subtables"
    )
    
    @Flag(name: .customLong("mif"), help: "Output MIF format")
    var mifFormat: Bool = false
    
    @Flag(name: .customLong("atif"), help: "Output ATIF format")
    var atifFormat: Bool = false
    
    @Option(name: .shortAndLong, help: "Input rules file")
    var input: String?
    
    @Option(name: .shortAndLong, help: "Single rule (explicit glyphs only, no classes)")
    var rule: String?
    
    @Option(name: .shortAndLong, help: "Output file (default: stdout)")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Feature name")
    var feature: String
    
    @Option(name: .long, help: "Selector number")
    var selector: Int
    
    func validate() throws {
        // Must have either input file or single rule
        if input == nil && rule == nil {
            throw ValidationError("Must provide either -i/--input or -r/--rule")
        }
        
        if input != nil && rule != nil {
            throw ValidationError("Cannot use both -i/--input and -r/--rule")
        }
        
        // Must specify exactly one format
        if mifFormat && atifFormat {
            throw ValidationError("Cannot specify both --mif and --atif")
        }
        
        if !mifFormat && !atifFormat {
            throw ValidationError("Must specify either --mif or --atif")
        }
    }
    
    func run() throws {
        let rules: [ReorderRule]
        let classes: [GlyphClass]
        
        if let inputPath = input {
            // Parse from file (supports classes)
            let parsed = try RuleParser.parseReorderRules(from: inputPath)
            classes = parsed.classes
            rules = parsed.rules
            
            print("✅ Parsed \(classes.count) class(es) and \(rules.count) rule(s) from file", to: &standardError)
            
        } else if let ruleString = rule {
            // Parse single rule from command line (no classes)
            let singleRule = try RuleParser.parseReorderRuleFromString(ruleString)
            rules = [singleRule]
            classes = []
            
            print("✅ Parsed single rule from command line", to: &standardError)
            
        } else {
            throw OT2AATError.generationFailed("No rules provided")
        }
        
        // Expand rules to check total combinations
        var registry = GlyphClassRegistry()
        for glyphClass in classes {
            try registry.register(glyphClass)
        }
        
        var totalCombinations = 0
        var allExpandedRules: [ExpandedReorderRule] = []
        
        for (index, rule) in rules.enumerated() {
            do {
                let expanded = try rule.expand(using: registry)
                totalCombinations += expanded.count
                allExpandedRules.append(contentsOf: expanded)
                
                // Debug: Show first few expanded rules
                if expanded.count > 0 {
                    let first = expanded[0]
                    print("  Rule \(index + 1): \(first.before.joined(separator: " ")) => \(first.after.joined(separator: " ")) [\(first.pattern.rawValue)]", to: &standardError)
                }
            } catch let error as OT2AATError {
                // Print full error details
                print("❌ Error in rule \(index + 1):", to: &standardError)
                print(error.localizedDescription, to: &standardError)
                throw error
            }
        }
        
        print("✅ Expanded to \(totalCombinations) total combination(s)", to: &standardError)
                
        // Generate output
        let result: String
        let outputFormat = mifFormat ? "MIF" : "ATIF"
        
        print("⚙️  Generating \(outputFormat)...", to: &standardError)
        
        if mifFormat {
            result = try MIFGenerator.generateReorder(
                rules: rules,
                classes: classes,
                featureName: feature,
                selectorNumber: selector
            )
        } else {
            result = try ATIFGenerator.generateReorder(
                rules: rules,
                classes: classes,
                featureName: feature,
                selectorNumber: selector
            )
        }
        
        // Output result
        if let outputPath = output {
            try result.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("✅ Generated \(outputFormat) file: \(outputPath)", to: &standardError)
        } else {
            print(result)
        }
    }
}

// Helper for stderr output
private var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.write(data)
    }
}

