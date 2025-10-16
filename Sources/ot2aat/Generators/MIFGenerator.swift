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
        
        // Separate into categories
        let cleanupRules = expandedRules.filter { $0.isCleanup }
        let multiPassRules = expandedRules.filter { $0.needsMultiPass && !$0.isCleanup }
        let singlePassRules = expandedRules.filter { !$0.needsMultiPass && !$0.isCleanup }
        
        var tableNumber = 0
        
        // Separate rules by type
        let decomposedRules = singlePassRules.filter { $0.ruleGroupID != nil }
        let regularRules = singlePassRules.filter { $0.ruleGroupID == nil }
        
        // Generate regular rules grouped by context type
        let groupedRegular = Dictionary(grouping: regularRules) { rule -> String in
            switch rule.context {
            case .after: return "after"
            case .before: return "before"
            case .between: return "between"
            case .when: return "when"
            case .cleanup: return "cleanup"
            }
        }
        
        for (contextType, rulesForType) in groupedRegular.sorted(by: { $0.key < $1.key }) {
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
        
        // Generate decomposed rules - EACH GROUP SEPARATELY
        // First, collect unique group IDs
        var seenGroupIDs = Set<String>()
        var orderedGroupIDs: [String] = []
        for rule in decomposedRules {
            if let groupID = rule.ruleGroupID, !seenGroupIDs.contains(groupID) {
                seenGroupIDs.insert(groupID)
                orderedGroupIDs.append(groupID)
            }
        }
        
        // For each unique group, generate its complete set of tables
        for groupID in orderedGroupIDs.sorted() {
            let rulesInGroup = decomposedRules.filter { $0.ruleGroupID == groupID }
            
            // Separate by context type within this group
            let afterRules = rulesInGroup.filter { if case .after = $0.context { return true }; return false }
            let beforeRules = rulesInGroup.filter { if case .before = $0.context { return true }; return false }
            let betweenRules = rulesInGroup.filter { if case .between = $0.context { return true }; return false }
            let cleanupRulesInGroup = rulesInGroup.filter { if case .cleanup = $0.context { return true }; return false }
            
            // Generate tables in order for this specific group
            if !afterRules.isEmpty {
                if tableNumber > 0 { output += "\n" }
                output += try generateContextualSubtable(
                    rules: afterRules,
                    contextType: "after",
                    featureName: featureName,
                    selectorNumber: selectorNumber,
                    tableNumber: tableNumber
                )
                tableNumber += 1
            }
            
            if !beforeRules.isEmpty {
                if tableNumber > 0 { output += "\n" }
                output += try generateContextualSubtable(
                    rules: beforeRules,
                    contextType: "before",
                    featureName: featureName,
                    selectorNumber: selectorNumber,
                    tableNumber: tableNumber
                )
                tableNumber += 1
            }
            
            if !betweenRules.isEmpty {
                if tableNumber > 0 { output += "\n" }
                output += try generateContextualSubtable(
                    rules: betweenRules,
                    contextType: "between",
                    featureName: featureName,
                    selectorNumber: selectorNumber,
                    tableNumber: tableNumber
                )
                tableNumber += 1
            }
            
            if !cleanupRulesInGroup.isEmpty {
                if tableNumber > 0 { output += "\n" }
                output += try generateCleanupTableForContextual(
                    rules: cleanupRulesInGroup,
                    featureName: featureName,
                    selectorNumber: selectorNumber,
                    tableNumber: tableNumber
                )
                tableNumber += 1
            }
        }
        
        // Generate multi-pass rules (each gets 3 tables)
        for multiPassRule in multiPassRules {
            if tableNumber > 0 { output += "\n" }
            output += try generateMultiPassTables(
                rule: multiPassRule,
                featureName: featureName,
                selectorNumber: selectorNumber,
                startTableNumber: tableNumber
            )
            tableNumber += 3
        }
        
        // Generate remaining cleanup rules (not part of decomposed groups)
        if !cleanupRules.isEmpty {
            if tableNumber > 0 { output += "\n" }
            output += try generateCleanupTableForContextual(
                rules: cleanupRules,
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: tableNumber
            )
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
        
        var contextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        
        for rule in rules {
            guard case .after(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        output += "ContextGlyphs\t\t" + contextGlyphs.sorted().joined(separator: " ") + "\n"
        output += "TargetGlyphs\t\t" + targetGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tContextGlyphs\tTargetGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "SawContext\t\t1\t1\t2\t1\t2\t\t\t\t3\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawContext\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tSawContext\t\tno\t\tyes\t\t\tnone\tdoSubst\n\n"
        
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
        output += "2\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n"
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
        output += "3\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n"
        output += "4\tStartText\t\tno\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
        output += "doSubst\n"
        for rule in rules {
            guard case .between = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
    
    // MARK: - When Context
    
    private static func generateWhenTable(rules: [ExpandedContextualRule]) throws -> String {
        var output = ""
        
        var allPatternGlyphs = Set<String>()
        
        for rule in rules {
            guard case .when(let pattern) = rule.context else { continue }
            allPatternGlyphs.formUnion(pattern)
        }
        
        output += "PatternGlyphs\t\t" + allPatternGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tPatternGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\n"
        output += "Matching\t\t1\t1\t2\t1\t3\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tMatching\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tMatching\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
        output += "doSubst\n"
        var substitutions: [(String, String)] = []
        for rule in rules {
            guard case .when = rule.context else { continue }
            for (target, replacement) in rule.substitutions {
                if !substitutions.contains(where: { $0.0 == target }) {
                    substitutions.append((target, replacement))
                }
            }
        }
        
        for (target, replacement) in substitutions {
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
    
    // MARK: - Multi-pass
    
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
        
        let tempGlyphs = (0..<(rule.substitutions.count - 1)).map { 65000 + $0 }
        
        output += try generateMarkingTableForMultiPass(
            pattern: pattern,
            substitutions: rule.substitutions,
            tempGlyphs: tempGlyphs,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: startTableNumber
        )
        
        output += "\n"
        
        output += try generateFinalSubstitutionTableForMultiPass(
            tempGlyphs: tempGlyphs,
            substitutions: rule.substitutions,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: startTableNumber + 1
        )
        
        output += "\n"
        
        output += try generateCleanupTableForMultiPass(
            tempGlyphs: tempGlyphs,
            featureName: featureName,
            selectorNumber: selectorNumber,
            tableNumber: startTableNumber + 2
        )
        
        return output
    }
    
    private static func generateMarkingTableForMultiPass(
        pattern: [String],
        substitutions: [(String, String)],
        tempGlyphs: [Int],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Multi-pass marking\n"
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
    
    private static func generateFinalSubstitutionTableForMultiPass(
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
    
    private static func generateCleanupTableForMultiPass(
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
    
    // MARK: - Cleanup for decomposed patterns
    
    private static func generateCleanupTableForContextual(
        rules: [ExpandedContextualRule],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Cleanup incomplete patterns\n"
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
        
        for rule in rules {
            guard case .cleanup = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\(target)\t\t\(replacement)\n"
        }
        
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
        output += "Type\t\t\t\tLigature\n"
        output += "Name\t\t\t\t\(featureName)\n"
        output += "Namecode\t\t\t8\n"
        output += "Setting\t\t\t\t\(featureName)\n"
        output += "Settingcode\t\t\t\(selectorNumber)\n"
        output += "Default\t\t\t\tyes\n"
        output += "Orientation\t\t\tHV\n"
        output += "Forward\t\t\t\tyes\n"
        output += "Exclusive\t\t\tno\n\n"
        
        // Ligatures
        for rule in rules {
            let components = rule.components.joined(separator: " ")
            output += "\(rule.target)\t\t\(components)\n"
        }
        
        return output
    }
}
