import Foundation
import ArgumentParser

struct ContextSubCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contextsub",
        abstract: "Convert contextual substitution rules to AAT contextual subtables"
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
        let rules: [ContextualRule]
        let classes: [GlyphClass]
        
        if let inputPath = input {
            // Parse from file (supports classes)
            let parsed = try RuleParser.parseContextualRules(from: inputPath)
            classes = parsed.classes
            rules = parsed.rules
            
            print("✅ Parsed \(classes.count) class(es) and \(rules.count) rule(s) from file", to: &standardError)
            
        } else if let ruleString = rule {
            // Parse single rule from command line (no classes)
            let singleRule = try RuleParser.parseContextualRuleFromString(ruleString)
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
        var allExpandedRules: [ExpandedContextualRule] = []
        
        for (index, rule) in rules.enumerated() {
            do {
                let expanded = try rule.expand(using: registry)
                totalCombinations += expanded.count
                allExpandedRules.append(contentsOf: expanded)
                
                // Debug: Show first expanded rule
                if expanded.count > 0 {
                    let first = expanded[0]
                    let contextDesc: String
                    switch first.context {
                    case .after(let pattern):
                        contextDesc = "after \(pattern.joined(separator: " "))"
                    case .before(let pattern):
                        contextDesc = "before \(pattern.joined(separator: " "))"
                    case .between(let first, let second):
                        contextDesc = "between \(first.joined(separator: " ")) and \(second.joined(separator: " "))"
                    case .when(let pattern):
                        contextDesc = "when \(pattern.joined(separator: " "))"
                    }
                    
                    let sub = first.substitutions[0]
                    print("  Rule \(index + 1): \(contextDesc): \(sub.target) => \(sub.replacement)", to: &standardError)
                }
            } catch let error as OT2AATError {
                // Print full error details
                print("❌ Error in rule \(index + 1):", to: &standardError)
                print(error.localizedDescription, to: &standardError)
                throw error
            }
        }
        
        print("✅ Expanded to \(totalCombinations) total combination(s)", to: &standardError)
        
        // Check for multi-pass rules
        let multiPassCount = allExpandedRules.filter { $0.needsMultiPass }.count
        if multiPassCount > 0 {
            print("ℹ️  \(multiPassCount) rule(s) require multi-pass generation", to: &standardError)
        }
        
        // Generate output
        let result: String
        let outputFormat = mifFormat ? "MIF" : "ATIF"
        
        print("⚙️  Generating \(outputFormat)...", to: &standardError)
        
        if mifFormat {
            result = try MIFGenerator.generateContextual(
                rules: rules,
                classes: classes,
                featureName: feature,
                selectorNumber: selector
            )
        } else {
            result = try ATIFGenerator.generateContextual(
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

// Helper for stderr output (shared with other commands)
private var standardError = FileHandle.standardError
