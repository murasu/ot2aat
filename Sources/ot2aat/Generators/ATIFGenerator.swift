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
        
        // Feature definition
        output += "feature (\(featureName)) {\n"
        output += "    selector (\(selectorNumber));\n"
        output += "};\n\n"
        
        // Insertion subtable
        output += try generateInsertionSubtable(
            rules: rules,
            featureName: featureName,
            selectorNumber: selectorNumber
        )
        
        output += "\n"
        
        // Contextual substitution subtable
        output += try generateContextualSubtable(
            rules: rules,
            featureName: featureName,
            selectorNumber: selectorNumber
        )
        
        return output
    }
    
    private static func generateInsertionSubtable(
        rules: [SubstitutionRule],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Insertion subtable for one-to-many\n"
        output += "insertion subtable (\(featureName), \(selectorNumber)) {\n"
        
        // Class definition
        let sourceGlyphs = rules.map { $0.source }
        output += "    class SourceGlyphs { " + sourceGlyphs.joined(separator: ", ") + " };\n\n"
        
        // State definitions
        output += "    state Start {\n"
        output += "        SourceGlyphs: InsertGlyphs;\n"
        output += "    };\n\n"
        
        // Transition
        output += "    transition InsertGlyphs {\n"
        output += "        Change state to Start;\n"
        output += "        Action: DoInsert;\n"
        output += "    };\n\n"
        
        // Actions for each rule
        for (index, rule) in rules.enumerated() {
            let glyphsToInsert = Array(rule.targets.dropFirst())
            output += "    Action DoInsert_\(index) {\n"
            output += "        Insert " + glyphsToInsert.joined(separator: " ") + " as kashida after current glyph;\n"
            output += "    };\n"
            
            if index < rules.count - 1 {
                output += "\n"
            }
        }
        
        output += "};\n"
        
        return output
    }
    
    private static func generateContextualSubtable(
        rules: [SubstitutionRule],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual substitution subtable\n"
        output += "contextual subtable (\(featureName), \(selectorNumber)) {\n"
        
        // Class definitions
        let sourceGlyphs = rules.map { $0.source }
        output += "    class SourceGlyphs { " + sourceGlyphs.joined(separator: ", ") + " };\n"
        
        var insertedGlyphs = Set<String>()
        for rule in rules {
            insertedGlyphs.formUnion(Array(rule.targets.dropFirst()))
        }
        output += "    class InsertedGlyphs { " + insertedGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
        // State definitions
        output += "    state Start {\n"
        output += "        SourceGlyphs: MarkSource;\n"
        output += "    };\n\n"
        
        output += "    state SawSource {\n"
        output += "        InsertedGlyphs: DoReplace;\n"
        output += "    };\n\n"
        
        // Transitions
        output += "    transition MarkSource {\n"
        output += "        Change state to SawSource;\n"
        output += "        Mark glyph;\n"
        output += "    };\n\n"
        
        output += "    transition DoReplace {\n"
        output += "        Change state to Start;\n"
        output += "        Marked glyph substitution: ReplaceSource;\n"
        output += "    };\n\n"
        
        // Substitution
        output += "    substitution ReplaceSource {\n"
        for rule in rules {
            output += "        \(rule.source) => \(rule.targets.first!);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
}
