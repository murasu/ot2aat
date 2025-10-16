import Foundation

struct ATIFGenerator {
    /// Generate ATIF for one-to-many substitution (splitting)
    static func generateOne2Many(
        rules: [SubstitutionRule],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated ATIF for one-to-many substitution\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Feature definition - using SmartSwash as it's a known working feature
        output += "feature (SmartSwash, \"\(featureName)\") {\n"
        output += "    selector(WordInitialSwashes, \"\(featureName)\");\n"
        output += "};\n\n"
        
        // Insertion subtable
        output += try generateInsertionSubtable(rules: rules)
        
        output += "\n"
        
        // Contextual substitution subtable
        output += try generateContextualSubtable(rules: rules)
        
        return output
    }
    
    private static func generateInsertionSubtable(
        rules: [SubstitutionRule]
    ) throws -> String {
        var output = ""
        
        output += "// Insertion subtable for one-to-many\n"
        output += "insertion subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Class definition with friendly name
        let sourceGlyphs = rules.map { $0.source }
        output += "    class SourceGlyphs { " + sourceGlyphs.joined(separator: ", ") + " };\n\n"
        
        // State definitions
        output += "    state Start {\n"
        output += "        SourceGlyphs: InsertGlyphs;\n"
        output += "    };\n\n"
        
        output += "    state SawSource {\n"
        output += "        SourceGlyphs: InsertGlyphs;\n"
        output += "    };\n\n"
        
        // Transition - use lowercase keywords and proper syntax
        output += "    transition InsertGlyphs {\n"
        output += "        change state to SawSource;\n"
        output += "        current glyph action: InsertAction;\n"
        output += "    };\n\n"
        
        // Action - use 'before glyph' not 'after current glyph'
        output += "    action InsertAction {\n"
        for rule in rules {
            let glyphsToInsert = Array(rule.targets.dropFirst())
            output += "        insert " + glyphsToInsert.joined(separator: " ") + " as kashida before glyph;\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    private static func generateContextualSubtable(
        rules: [SubstitutionRule]
    ) throws -> String {
        var output = ""
        
        output += "// Contextual substitution subtable\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Class definitions with friendly names
        let sourceGlyphs = rules.map { $0.source }
        output += "    class SourceGlyphs { " + sourceGlyphs.joined(separator: ", ") + " };\n"
        
        var insertedGlyphs = Set<String>()
        for rule in rules {
            insertedGlyphs.formUnion(Array(rule.targets.dropFirst()))
        }
        output += "    class InsertedGlyphs { " + insertedGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
        // State definitions with friendly names
        output += "    state Start {\n"
        output += "        SourceGlyphs: MarkSource;\n"
        output += "    };\n\n"
        
        output += "    state SawSource {\n"
        output += "        SourceGlyphs: MarkSource;\n"
        output += "        InsertedGlyphs: DoReplace;\n"
        output += "    };\n\n"
        
        // Transitions - lowercase keywords
        output += "    transition MarkSource {\n"
        output += "        change state to SawSource;\n"
        output += "        mark glyph;\n"
        output += "    };\n\n"
        
        output += "    transition DoReplace {\n"
        output += "        change state to Start;\n"
        output += "        marked glyph substitution: ReplaceSource;\n"
        output += "    };\n\n"
        
        // Substitution with friendly name
        output += "    substitution ReplaceSource {\n"
        for rule in rules {
            output += "        \(rule.source) => \(rule.targets.first!);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
}

// Add to existing ATIFGenerator struct

extension ATIFGenerator {
    /// Generate ATIF for rearrangement
    static func generateReorder(
        rules: [ReorderRule],
        classes: [GlyphClass],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated ATIF for rearrangement\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Feature definition
        output += "feature (SmartSwash, \"\(featureName)\") {\n"
        output += "    selector(WordInitialSwashes, \"\(featureName)\");\n"
        output += "};\n\n"
        
        // Expand all rules
        var registry = GlyphClassRegistry()
        for glyphClass in classes {
            try registry.register(glyphClass)
        }
        
        var expandedRules: [ExpandedReorderRule] = []
        for rule in rules {
            let expanded = try rule.expand(using: registry)
            expandedRules.append(contentsOf: expanded)
        }
        
        // Group rules by pattern
        let groupedRules = Dictionary(grouping: expandedRules) { $0.pattern }
        
        // Generate a subtable for each pattern group
        for (index, (pattern, rulesForPattern)) in groupedRules.enumerated() {
            if index > 0 {
                output += "\n"
            }
            output += try generateReorderSubtable(
                rules: rulesForPattern,
                pattern: pattern,
                subtableNumber: index
            )
        }
        
        return output
    }
    
    private static func generateReorderSubtable(
        rules: [ExpandedReorderRule],
        pattern: ReorderPattern,
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Rearrangement subtable \(subtableNumber) (\(pattern.rawValue))\n"
        output += "reorder subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Collect all unique glyphs
        var firstGlyphs = Set<String>()
        var lastGlyphs = Set<String>()
        
        for rule in rules {
            firstGlyphs.insert(rule.before.first!)
            lastGlyphs.insert(rule.before.last!)
        }
        
        // Class definitions
        output += "    class FirstGlyphs { " + firstGlyphs.sorted().joined(separator: ", ") + " };\n"
        output += "    class LastGlyphs { " + lastGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
        // State definitions
        output += "    state Start {\n"
        output += "        FirstGlyphs: MarkFirst;\n"
        output += "    };\n\n"
        
        output += "    state SawFirst {\n"
        output += "        FirstGlyphs: MarkFirst;\n"
        output += "        LastGlyphs: DoRearrange;\n"
        output += "    };\n\n"
        
        // Transitions
        output += "    transition MarkFirst {\n"
        output += "        change state to SawFirst;\n"
        output += "        mark first;\n"
        output += "    };\n\n"
        
        output += "    transition DoRearrange {\n"
        output += "        change state to Start;\n"
        output += "        mark last;\n"
        output += "        verb: \(pattern.rawValue);\n"
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
}

// MARK: - ATIFGenerator Extension

extension ATIFGenerator {
    /// Generate unified ATIF for all GSUB types
    static func generateGsub(
        rules: GsubRules,
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        var subtableNumber = 0
        
        output += "// " + String(repeating: "=", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated ATIF for GSUB (all substitution types)\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "=", count: 79) + "\n\n"
        
        // Feature definition
        output += "feature (SmartSwash, \"\(featureName)\") {\n"
        output += "    selector(WordInitialSwashes, \"\(featureName)\");\n"
        output += "};\n\n"
        
        // Generate simple substitutions (noncontextual)
        if !rules.simpleSubstitutions.isEmpty {
            output += try generateSimpleSubstitutionSubtable(
                rules: rules.simpleSubstitutions,
                subtableNumber: subtableNumber
            )
            subtableNumber += 1
            output += "\n"
        }
        
        // Generate ligatures
        if !rules.ligatures.isEmpty {
            output += try generateLigatureSubtable(
                rules: rules.ligatures,
                subtableNumber: subtableNumber
            )
            subtableNumber += 1
            output += "\n"
        }
        
        // Generate one-to-many
        if !rules.one2many.isEmpty {
            output += try generateOne2Many(
                rules: rules.one2many,
                featureName: featureName,
                selectorNumber: selectorNumber
            )
            output += "\n"
        }
        
        // Generate contextual
        if !rules.contextual.isEmpty {
            output += try generateContextual(
                rules: rules.contextual,
                classes: rules.classes,
                featureName: featureName,
                selectorNumber: selectorNumber
            )
            output += "\n"
        }
        
        // Generate reorder
        if !rules.reorder.isEmpty {
            output += try generateReorder(
                rules: rules.reorder,
                classes: rules.classes,
                featureName: featureName,
                selectorNumber: selectorNumber
            )
        }
        
        return output
    }
    
    /// Generate ATIF for simple substitutions
    private static func generateSimpleSubstitutionSubtable(
        rules: [SimpleSubstitution],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Noncontextual subtable \(subtableNumber) (simple substitutions)\n"
        output += "noncontextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        for rule in rules {
            output += "    \(rule.source) => \(rule.target);\n"
        }
        
        output += "};\n"
        
        return output
    }
    
    /// Generate ATIF for ligatures
    private static func generateLigatureSubtable(
        rules: [LigatureRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Ligature subtable \(subtableNumber)\n"
        output += "ligature subtable (SmartSwash, WordInitialSwashes) {\n"
        
        for rule in rules {
            let components = rule.components.joined(separator: " + ")
            output += "    \(rule.target) := \(components);\n"
        }
        
        output += "};\n"
        
        return output
    }
}
