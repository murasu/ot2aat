import Foundation

struct MIFGenerator {
    /// Generate MIF for one-to-many substitution (splitting)
    /// Creates both Insertion and Contextual substitution tables
    static func generateOne2Many(
        rules: [SubstitutionRule],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated MIF for one-to-many substitution\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Table 0: Insertion table
        output += try generateInsertionTable(
            rules: rules,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: 0
        )
        
        output += "\n"
        
        // Table 1: Contextual substitution table
        output += try generateContextualTable(
            rules: rules,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: 1
        )
        
        return output
    }
    
    private static func generateInsertionTable(
        rules: [SubstitutionRule],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Insertion for one-to-many substitution\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Header
        output += "Type\t\t\t\tInsertion\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        // Class definitions
        let sourceGlyphs = rules.map { $0.source }
        output += "SourceGlyphs\t\t" + sourceGlyphs.joined(separator: " ") + "\n\n"
        
        // State array
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tSourceGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\n"
        output += "SawSource\t\t1\t1\t2\t1\t2\n\n"
        
        // Transition list
        output += "\tGoTo\t\t\tMark?\tAdvance?\tInsertMark\tInsertCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawSource\t\tno\t\tyes\t\t\tnone\t\tinsertGlyphs\n\n"
        
        // Insertion lists for each rule
        for (index, rule) in rules.enumerated() {
            if index == 0 {
                output += "insertGlyphs\n"
            }
            output += "\tIsKashidaLike\tyes\n"
            output += "\tInsertBefore\tno\n"
            
            // Insert all target glyphs except the first one
            let glyphsToInsert = Array(rule.targets.dropFirst())
            output += "\tGlyphs\t\t\t" + glyphsToInsert.joined(separator: " ") + "\n"
            
            if index < rules.count - 1 {
                output += "\n"
            }
        }
        
        return output
    }
    
    private static func generateContextualTable(
        rules: [SubstitutionRule],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Contextual substitution for source glyphs\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Header
        output += "Type\t\t\t\tContextual\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        // Class definitions
        let sourceGlyphs = rules.map { $0.source }
        output += "SourceGlyphs\t\t" + sourceGlyphs.joined(separator: " ") + "\n"
        
        // Collect all inserted glyphs that will be in the stream
        var insertedGlyphs = Set<String>()
        for rule in rules {
            insertedGlyphs.formUnion(Array(rule.targets.dropFirst()))
        }
        output += "InsertedGlyphs\t\t" + insertedGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        // State array
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tSourceGlyphs\tInsertedGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "SawSource\t\t1\t1\t1\t1\t2\t\t\t\t3\n\n"
        
        // Transition list
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawSource\t\tyes\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tStartText\t\tno\t\tyes\t\t\tdoRepl\t\tnone\n\n"
        
        // Substitution list
        output += "doRepl\n"
        for rule in rules {
            output += "\t\(rule.source)\t\t\(rule.targets.first!)\n"
        }
        
        return output
    }
}
