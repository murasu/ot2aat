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

extension MIFGenerator {
    /// Generate MIF for contextual substitution
    static func generateContextual(
        rules: [ContextualRule],
        classes: [GlyphClass],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated MIF for contextual substitution\n"
        output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
        output += "//  Generated: \(Date())\n"
        output += "//\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        // Expand all rules
        var registry = GlyphClassRegistry()
        for glyphClass in classes {
            try registry.register(glyphClass)
        }
        
        var expandedRules: [ExpandedContextualRule] = []
        for rule in rules {
            let expanded = try rule.expand(using: registry)
            expandedRules.append(contentsOf: expanded)
        }
        
        // Separate multi-pass rules
        let singlePassRules = expandedRules.filter { !$0.needsMultiPass }
        let multiPassRules = expandedRules.filter { $0.needsMultiPass }
        
        var tableNumber = 0
        
        // Generate single-pass rules grouped by context type
        let groupedSingle = Dictionary(grouping: singlePassRules) { rule -> String in
            switch rule.context {
            case .after: return "after"
            case .before: return "before"
            case .between: return "between"
            case .when: return "when"
            }
        }
        
        for (contextType, rulesForType) in groupedSingle.sorted(by: { $0.key < $1.key }) {
            if tableNumber > 0 { output += "\n" }
            output += try generateContextualSubtable(
                rules: rulesForType,
                contextType: contextType,
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: tableNumber
            )
            tableNumber += 1
        }
        
        // Generate multi-pass rules (each gets multiple tables)
        for multiPassRule in multiPassRules {
            if tableNumber > 0 { output += "\n" }
            output += try generateMultiPassTables(
                rule: multiPassRule,
                featureName: featureName,
                selectorNumber: selectorNumber,
                startTableNumber: tableNumber
            )
            tableNumber += 3 // Mark, substitute, cleanup
        }
        
        return output
    }
    
    private static func generateContextualSubtable(
        rules: [ExpandedContextualRule],
        contextType: String,
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Contextual substitution (\(contextType))\n"
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
        
        let tableContent: String
        switch contextType {
        case "after":
            tableContent = try generateAfterTable(rules: rules)
        case "before":
            tableContent = try generateBeforeTable(rules: rules)
        case "between":
            tableContent = try generateBetweenTable(rules: rules)
        case "when":
            tableContent = try generateWhenTable(rules: rules)
        default:
            throw OT2AATError.generationFailed("Unknown context type: \(contextType)")
        }
        
        return output + tableContent
    }
    
    // MARK: - After Context
    
    private static func generateAfterTable(rules: [ExpandedContextualRule]) throws -> String {
        var output = ""
        
        // Collect glyphs
        var contextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        
        for rule in rules {
            guard case .after(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        // Classes
        output += "ContextGlyphs\t\t" + contextGlyphs.sorted().joined(separator: " ") + "\n"
        output += "TargetGlyphs\t\t" + targetGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        // State array
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tContextGlyphs\tTargetGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "SawContext\t\t1\t1\t2\t1\t2\t\t\t\t3\n\n"
        
        // Transitions
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawContext\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tStartText\t\tno\t\tyes\t\t\tnone\t\tdoSubst\n\n"
        
        // Substitutions
        output += "doSubst\n"
        for rule in rules {
            guard case .after = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
    
    // MARK: - Before Context
    
    private static func generateBeforeTable(rules: [ExpandedContextualRule]) throws -> String {
        var output = ""
        
        var targetGlyphs = Set<String>()
        var contextGlyphs = Set<String>()
        
        for rule in rules {
            guard case .before(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        output += "TargetGlyphs\t\t" + targetGlyphs.sorted().joined(separator: " ") + "\n"
        output += "ContextGlyphs\t\t" + contextGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tTargetGlyphs\tContextGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "SawTarget\t\t1\t1\t2\t1\t2\t\t\t\t3\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawTarget\t\tyes\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tStartText\t\tno\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
        output += "doSubst\n"
        for rule in rules {
            guard case .before = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
    
    // MARK: - Between Context
    
    private static func generateBetweenTable(rules: [ExpandedContextualRule]) throws -> String {
        var output = ""
        
        var firstContextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        var secondContextGlyphs = Set<String>()
        
        for rule in rules {
            guard case .between(let first, let second) = rule.context else { continue }
            firstContextGlyphs.formUnion(first)
            secondContextGlyphs.formUnion(second)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        output += "FirstContext\t\t" + firstContextGlyphs.sorted().joined(separator: " ") + "\n"
        output += "TargetGlyphs\t\t" + targetGlyphs.sorted().joined(separator: " ") + "\n"
        output += "SecondContext\t\t" + secondContextGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tFirstContext\tTargetGlyphs\tSecondContext\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\t\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\t\t\t\t1\n"
        output += "SawFirst\t\t1\t1\t2\t1\t2\t\t\t\t3\t\t\t\t1\n"
        output += "SawTarget\t\t1\t1\t3\t1\t1\t\t\t\t3\t\t\t\t4\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawFirst\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tSawTarget\t\tyes\t\tyes\t\t\tnone\t\tnone\n"
        output += "4\tStartText\t\tno\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
        output += "doSubst\n"
        for rule in rules {
            guard case .between = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
    
    // MARK: - When Context (single substitution)
    
private static func generateWhenTable(rules: [ExpandedContextualRule]) throws -> String {
        var output = ""
        
        // For 'when' context, we need to match the full pattern
        // Collect all unique glyphs from patterns
        var allPatternGlyphs = Set<String>()
        
        for rule in rules {
            guard case .when(let pattern) = rule.context else { continue }
            allPatternGlyphs.formUnion(pattern)
        }
        
        output += "PatternGlyphs\t\t" + allPatternGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        // Build a more sophisticated state machine
        // We need states for each position in the pattern matching
        
        // Simplified approach: mark as we go through pattern
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tPatternGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\n"
        output += "Matching\t\t1\t1\t2\t1\t3\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tMatching\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tMatching\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
        // Build substitution list
        // Only include glyphs that are actually being substituted
        var substitutions: [(String, String)] = []
        for rule in rules {
            guard case .when = rule.context else { continue }
            for (target, replacement) in rule.substitutions {
                if !substitutions.contains(where: { $0.0 == target }) {
                    substitutions.append((target, replacement))
                }
            }
        }
        
        output += "doSubst\n"
        for (target, replacement) in substitutions {
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
        
    // MARK: - Multi-pass for when context with multiple substitutions
    
    private static func generateMultiPassTables(
        rule: ExpandedContextualRule,
        featureName: String,
        selectorNumber: Int,
        startTableNumber: Int
    ) throws -> String {
        var output = ""
        
        guard case .when(let pattern) = rule.context else {
            throw OT2AATError.generationFailed("Multi-pass only for 'when' context")
        }
        
        // Generate temp glyph IDs
        let tempGlyphs = (0..<(rule.substitutions.count - 1)).map { 65000 + $0 }
        
        // Table 1: Mark positions with temp glyphs
        output += try generateMarkingTable(
            pattern: pattern,
            substitutions: rule.substitutions,
            tempGlyphs: tempGlyphs,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: startTableNumber
        )
        
        output += "\n"
        
        // Table 2: Final substitutions
        output += try generateFinalSubstitutionTable(
            tempGlyphs: tempGlyphs,
            substitutions: rule.substitutions,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: startTableNumber + 1
        )
        
        output += "\n"
        
        // Table 3: Cleanup temp glyphs
        output += try generateCleanupTable(
            tempGlyphs: tempGlyphs,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: startTableNumber + 2
        )
        
        return output
    }
    
    private static func generateMarkingTable(
        pattern: [String],
        substitutions: [(String, String)],
        tempGlyphs: [Int],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Multi-pass marking (when context)\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        output += "Type\t\t\t\tContextual\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        output += "PatternGlyphs\t\t" + pattern.joined(separator: " ") + "\n\n"
        
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tPatternGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tStartText\t\tno\t\tyes\t\t\tnone\t\tmarkTemp\n\n"
        
        output += "markTemp\n"
        for (idx, (target, _)) in substitutions.dropLast().enumerated() {
            output += "\t\(target)\t\t\(tempGlyphs[idx])\n"
        }
        
        return output
    }
    
    private static func generateFinalSubstitutionTable(
        tempGlyphs: [Int],
        substitutions: [(String, String)],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Multi-pass final substitution\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        output += "Type\t\t\t\tNoncontextual\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        for (idx, (_, replacement)) in substitutions.dropLast().enumerated() {
            output += "\(tempGlyphs[idx])\t\t\(replacement)\n"
        }
        let (lastTarget, lastReplacement) = substitutions.last!
        output += "\(lastTarget)\t\t\(lastReplacement)\n"
        
        return output
    }
    
    private static func generateCleanupTable(
        tempGlyphs: [Int],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Cleanup temp glyphs\n"
        output += "// " + String(repeating: "-", count: 79) + "\n\n"
        
        output += "Type\t\t\t\tNoncontextual\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        for tempGlyph in tempGlyphs {
            output += "\(tempGlyph)\t\tDEL\n"
        }
        
        return output
    }
}
