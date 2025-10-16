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

extension MIFGenerator {
    /// Generate MIF for rearrangement (Type 0)
    static func generateReorder(
        rules: [ReorderRule],
        classes: [GlyphClass],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated MIF for rearrangement\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
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
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: index
            )
        }
        
        return output
    }
    
    private static func generateReorderSubtable(
        rules: [ExpandedReorderRule],
        pattern: ReorderPattern,
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Rearrangement (\(pattern.rawValue))\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Header
        output += "Type\t\t\t\tRearrangement\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        // Collect all unique glyphs from all rules
        var firstGlyphs = Set<String>()
        var lastGlyphs = Set<String>()
        
        for rule in rules {
            firstGlyphs.insert(rule.before.first!)
            lastGlyphs.insert(rule.before.last!)
        }
        
        // Define classes
        output += "FirstGlyphs\t\t" + firstGlyphs.sorted().joined(separator: " ") + "\n"
        output += "LastGlyphs\t\t" + lastGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        // State array
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tFirstGlyphs\tLastGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t1\n"
        output += "SawFirst\t\t1\t1\t3\t1\t2\t\t\t4\n\n"
        
        // Transition list
        output += "\tGoTo\t\t\tMarkFirst?\tMarkLast?\tAdvance?\tDoThis\n"
        output += "1\tStartText\t\tno\t\t\tno\t\t\tyes\t\t\tnone\n"
        output += "2\tSawFirst\t\tyes\t\t\tno\t\t\tyes\t\t\tnone\n"
        output += "3\tSawFirst\t\tno\t\t\tno\t\t\tyes\t\t\tnone\n"
        output += "4\tStartText\t\tno\t\t\tyes\t\t\tyes\t\t\t\(pattern.rawValue)\n"
        
        return output
    }
}

// MARK: - MIFGenerator Extension

extension MIFGenerator {
    /// Generate unified MIF for all GSUB types
    static func generateGsub(
        rules: GsubRules,
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        var tableNumber = 0
        
        output += "// " + String(repeating: "=", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated MIF for GSUB (all substitution types)\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "=", count: 79) + "\n\n"
        
        // Generate simple substitutions (noncontextual)
        if !rules.simpleSubstitutions.isEmpty {
            output += try generateSimpleSubstitutionTable(
                rules: rules.simpleSubstitutions,
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: tableNumber
            )
            tableNumber += 1
            output += "\n"
        }
        
        // Generate ligatures
        if !rules.ligatures.isEmpty {
            output += try generateLigatureTable(
                rules: rules.ligatures,
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: tableNumber
            )
            tableNumber += 1
            output += "\n"
        }
        
        // Generate one-to-many (insertion + contextual pair)
        if !rules.one2many.isEmpty {
            output += try generateOne2Many(
                rules: rules.one2many,
                featureName: featureName,
                selectorNumber: selectorNumber
            )
            // This generates 2 tables internally
            output += "\n"
        }
        
        // Generate contextual substitution
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
    
    /// Generate MIF for simple substitutions (Type 1 - Noncontextual)
    private static func generateSimpleSubstitutionTable(
        rules: [SimpleSubstitution],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Simple substitutions (Type 1)\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Header
        output += "Type\t\t\t\tNoncontextual\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        // Substitutions
        for rule in rules {
            output += "\(rule.source)\t\t\(rule.target)\n"
        }
        
        return output
    }
    
    /// Generate MIF for ligatures (Type 4)
    private static func generateLigatureTable(
        rules: [LigatureRule],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Ligatures (Type 4)\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Header
        output += "Type\t\t\t\tLigatureList\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        // Start of ligature list
        output += "List\n"
        
        // Ligatures
        for rule in rules {
            let components = rule.components.joined(separator: " ")
            output += "\t\(rule.target)\t\t\(components)\n"
        }
        
        return output
    }
}
