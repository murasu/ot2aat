import Foundation

extension MIFGenerator {
    /// Generate MIF for contextual substitution (OPTIMIZED)
    
    // MARK: - Helper: Analyze Glyph Overlap
    private static func analyzeGlyphSets(
        targets: Set<String>,
        contexts: Set<String>
    ) -> (targetOnly: Set<String>, contextOnly: Set<String>, both: Set<String>, hasOverlap: Bool) {
        
        let both = targets.intersection(contexts)
        let targetOnly = targets.subtracting(contexts)
        let contextOnly = contexts.subtracting(targets)
        
        return (targetOnly, contextOnly, both, !both.isEmpty)
    }
    
    // MARK: - Generate Contextual
    
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
        
        // OPTIMIZED: Group "after" rules by pattern length, then by substitution pattern
        let allAfterRules = singlePassRules.filter {
            if case .after = $0.context { return true }
            return false
        }
        
        let afterByLength = Dictionary(grouping: allAfterRules) { rule -> Int in
            guard case .after(let context) = rule.context else { return 0 }
            return context.count
        }
        
        for (length, rulesForLength) in afterByLength.sorted(by: { $0.key < $1.key }) {
            if length > 1 {
                // Multi-element: ONE table for all rules with this pattern length
                output += try generateMultiElementAfterSubtable(
                    rules: rulesForLength,
                    featureName: featureName,
                    selectorNumber: selectorNumber,
                    tableNumber: tableNumber
                )
                tableNumber += 1
                
            } else {
                // Single-element: Group by substitution pattern
                let bySubstitution = Dictionary(grouping: rulesForLength) { rule -> String in
                    return rule.substitutions
                        .map { "\($0.target)→\($0.replacement)" }
                        .sorted()
                        .joined(separator: ",")
                }
                
                for (_, groupedRules) in bySubstitution.sorted(by: { $0.key < $1.key }) {
                    output += try generateContextualSubtable(
                        rules: groupedRules,
                        contextType: "after",
                        featureName: featureName,
                        selectorNumber: selectorNumber,
                        tableNumber: tableNumber
                    )
                    tableNumber += 1
                }
            }
        }
        
        // OPTIMIZED: Group "before" rules by pattern length, then by substitution pattern
        let allBeforeRules = singlePassRules.filter {
            if case .before = $0.context { return true }
            return false
        }
        
        let beforeByLength = Dictionary(grouping: allBeforeRules) { rule -> Int in
            guard case .before(let context) = rule.context else { return 0 }
            return context.count
        }
        
        for (length, rulesForLength) in beforeByLength.sorted(by: { $0.key < $1.key }) {
            if length > 1 {
                output += try generateMultiElementBeforeSubtable(
                    rules: rulesForLength,
                    featureName: featureName,
                    selectorNumber: selectorNumber,
                    tableNumber: tableNumber
                )
                tableNumber += 1
                
            } else {
                let bySubstitution = Dictionary(grouping: rulesForLength) { rule -> String in
                    return rule.substitutions
                        .map { "\($0.target)→\($0.replacement)" }
                        .sorted()
                        .joined(separator: ",")
                }
                
                for (_, groupedRules) in bySubstitution.sorted(by: { $0.key < $1.key }) {
                    output += try generateContextualSubtable(
                        rules: groupedRules,
                        contextType: "before",
                        featureName: featureName,
                        selectorNumber: selectorNumber,
                        tableNumber: tableNumber
                    )
                    tableNumber += 1
                }
            }
        }
        
        // Between and when don't need optimization - they're already minimal
        let allBetweenRules = singlePassRules.filter {
            if case .between = $0.context { return true }
            return false
        }
        
        let allWhenRules = singlePassRules.filter {
            if case .when = $0.context { return true }
            return false
        }
        
        if !allBetweenRules.isEmpty {
            output += try generateContextualSubtable(
                rules: allBetweenRules,
                contextType: "between",
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: tableNumber
            )
            tableNumber += 1
        }
        
        if !allWhenRules.isEmpty {
            output += try generateContextualSubtable(
                rules: allWhenRules,
                contextType: "when",
                featureName: featureName,
                selectorNumber: selectorNumber,
                tableNumber: tableNumber
            )
            tableNumber += 1
        }
        
        // Generate cleanup tables grouped by ruleGroupID
        let decomposedRules = singlePassRules.filter { $0.ruleGroupID != nil }
        var seenGroupIDs = Set<String>()
        var orderedGroupIDs: [String] = []
        for rule in decomposedRules {
            if let groupID = rule.ruleGroupID, !seenGroupIDs.contains(groupID) {
                seenGroupIDs.insert(groupID)
                orderedGroupIDs.append(groupID)
            }
        }
        
        for groupID in orderedGroupIDs.sorted() {
            let cleanupRulesInGroup = decomposedRules.filter {
                $0.ruleGroupID == groupID && $0.isCleanup
            }
            
            if !cleanupRulesInGroup.isEmpty {
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
        var contextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        
        for rule in rules {
            guard case .after(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        // Analyze overlap
        let (tgtOnly, ctxOnly, both, hasOverlap) = analyzeGlyphSets(
            targets: targetGlyphs,
            contexts: contextGlyphs
        )
        
        if hasOverlap {
            return try generateAfterTableWithOverlap(
                targetOnly: tgtOnly,
                contextOnly: ctxOnly,
                both: both,
                rules: rules
            )
        } else {
            return try generateAfterTableSimple(
                targets: targetGlyphs,
                contexts: contextGlyphs,
                rules: rules
            )
        }
    }
    
    private static func generateAfterTableSimple(
        targets: Set<String>,
        contexts: Set<String>,
        rules: [ExpandedContextualRule]
    ) throws -> String {
        var output = ""
        
        output += "ContextGlyphs\t\t" + contexts.sorted().joined(separator: " ") + "\n"
        output += "TargetGlyphs\t\t" + targets.sorted().joined(separator: " ") + "\n\n"
        
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tContextGlyphs\tTargetGlyphs\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\n"
        output += "SawContext\t\t1\t1\t2\t1\t2\t\t\t\t3\n\n"
        
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawContext\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tSawContext\t\tno\t\tyes\t\t\tnone\t\tdoSubst\n\n"
        
        output += "doSubst\n"
        for rule in rules {
            guard case .after = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
    
    private static func generateAfterTableWithOverlap(
        targetOnly: Set<String>,
        contextOnly: Set<String>,
        both: Set<String>,
        rules: [ExpandedContextualRule]
    ) throws -> String {
        var output = ""
        
        // Three classes
        output += "Context\t\t\t" + contextOnly.sorted().joined(separator: " ") + "\n"
        output += "Target\t\t\t" + targetOnly.sorted().joined(separator: " ") + "\n"
        output += "TrgtAndCntx\t\t" + both.sorted().joined(separator: " ") + "\n\n"
        
        // State array with 3 classes
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tContext\tTarget\tTrgtAndCntx\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t1\t\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t1\t\t2\n"
        output += "SawContext\t\t1\t1\t2\t1\t2\t\t3\t\t4\n\n"
        
        // Four transitions
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawContext\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tSawContext\t\tno\t\tyes\t\t\tnone\t\tdoSubst\n"
        output += "4\tSawContext\t\tno\t\tyes\t\t\tnone\t\tdoSubst\n\n"
        
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
        var targetGlyphs = Set<String>()
        var contextGlyphs = Set<String>()
        
        for rule in rules {
            guard case .before(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        // Analyze overlap
        let (tgtOnly, ctxOnly, both, hasOverlap) = analyzeGlyphSets(
            targets: targetGlyphs,
            contexts: contextGlyphs
        )
        
        if hasOverlap {
            return try generateBeforeTableWithOverlap(
                targetOnly: tgtOnly,
                contextOnly: ctxOnly,
                both: both,
                rules: rules
            )
        } else {
            return try generateBeforeTableSimple(
                targets: targetGlyphs,
                contexts: contextGlyphs,
                rules: rules
            )
        }
    }
    
    private static func generateBeforeTableSimple(
        targets: Set<String>,
        contexts: Set<String>,
        rules: [ExpandedContextualRule]
    ) throws -> String {
        var output = ""
        
        output += "TargetGlyphs\t\t" + targets.sorted().joined(separator: " ") + "\n"
        output += "ContextGlyphs\t\t" + contexts.sorted().joined(separator: " ") + "\n\n"
        
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
    
    private static func generateBeforeTableWithOverlap(
        targetOnly: Set<String>,
        contextOnly: Set<String>,
        both: Set<String>,
        rules: [ExpandedContextualRule]
    ) throws -> String {
        var output = ""
        
        // Three classes
        output += "Target\t\t\t" + targetOnly.sorted().joined(separator: " ") + "\n"
        output += "Context\t\t\t" + contextOnly.sorted().joined(separator: " ") + "\n"
        output += "TrgtAndCntx\t\t" + both.sorted().joined(separator: " ") + "\n\n"
        
        // State array with 3 classes
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tTarget\tContext\tTrgtAndCntx\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t1\t\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t1\t\t2\n"
        output += "SawTarget\t\t1\t1\t2\t1\t2\t\t3\t\t4\n\n"
        
        // Four transitions
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n"
        output += "3\tStartText\t\tno\t\tyes\t\t\tdoSubst\t\tnone\n"
        output += "4\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
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
        var firstContextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        var secondContextGlyphs = Set<String>()
        
        for rule in rules {
            guard case .between(let first, let second) = rule.context else { continue }
            firstContextGlyphs.formUnion(first)
            secondContextGlyphs.formUnion(second)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        // For between, we need to check overlap with BOTH context sets
        let allContextGlyphs = firstContextGlyphs.union(secondContextGlyphs)
        let (tgtOnly, _, both, hasOverlap) = analyzeGlyphSets(
            targets: targetGlyphs,
            contexts: allContextGlyphs
        )
        
        if hasOverlap {
            return try generateBetweenTableWithOverlap(
                firstContext: firstContextGlyphs,
                targetOnly: tgtOnly,
                secondContext: secondContextGlyphs,
                both: both,
                rules: rules
            )
        } else {
            return try generateBetweenTableSimple(
                firstContext: firstContextGlyphs,
                targets: targetGlyphs,
                secondContext: secondContextGlyphs,
                rules: rules
            )
        }
    }
    
    private static func generateBetweenTableSimple(
        firstContext: Set<String>,
        targets: Set<String>,
        secondContext: Set<String>,
        rules: [ExpandedContextualRule]
    ) throws -> String {
        var output = ""
        
        output += "FirstContext\t\t" + firstContext.sorted().joined(separator: " ") + "\n"
        output += "TargetGlyphs\t\t" + targets.sorted().joined(separator: " ") + "\n"
        output += "SecondContext\t\t" + secondContext.sorted().joined(separator: " ") + "\n\n"
        
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
    
    private static func generateBetweenTableWithOverlap(
        firstContext: Set<String>,
        targetOnly: Set<String>,
        secondContext: Set<String>,
        both: Set<String>,
        rules: [ExpandedContextualRule]
    ) throws -> String {
        var output = ""
        
        // Separate pure contexts from overlapping glyphs
        let firstOnly = firstContext.subtracting(targetOnly).subtracting(both)
        let secondOnly = secondContext.subtracting(targetOnly).subtracting(both)
        
        // Build classes carefully
        output += "FirstContext\t\t" + firstOnly.sorted().joined(separator: " ") + "\n"
        output += "Target\t\t\t" + targetOnly.sorted().joined(separator: " ") + "\n"
        output += "SecondContext\t\t" + secondOnly.sorted().joined(separator: " ") + "\n"
        output += "TrgtAndCntx\t\t" + both.sorted().joined(separator: " ") + "\n\n"
        
        // State array - this gets complex with 4 classes
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tFirstContext\tTarget\tSecondContext\tTrgtAndCntx\n"
        output += "StartText\t\t1\t1\t1\t1\t2\t\t\t\t1\t\t1\t\t\t\t2\n"
        output += "StartLine\t\t1\t1\t1\t1\t2\t\t\t\t1\t\t1\t\t\t\t2\n"
        output += "SawFirst\t\t1\t1\t2\t1\t2\t\t\t\t3\t\t1\t\t\t\t3\n"
        output += "SawTarget\t\t1\t1\t3\t1\t1\t\t\t\t3\t\t4\t\t\t\t5\n\n"
        
        // Five transitions to handle all cases
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawFirst\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "3\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n"
        output += "4\tStartText\t\tno\t\tyes\t\t\tdoSubst\t\tnone\n"
        output += "5\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
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
    
    // MARK: - Multi-Element After Context

    private static func generateMultiElementAfterSubtable(
        rules: [ExpandedContextualRule],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        guard let firstRule = rules.first,
              case .after(let sampleContext) = firstRule.context,
              sampleContext.count >= 2 else {
            throw OT2AATError.generationFailed("Multi-element after requires 2+ elements")
        }
        
        let patternLength = sampleContext.count
        
        // Collect glyphs at each position
        var glyphsByPosition: [[String]] = Array(repeating: [], count: patternLength)
        var targetGlyphs = Set<String>()
        
        for rule in rules {
            guard case .after(let context) = rule.context else { continue }
            for (idx, glyph) in context.enumerated() {
                if !glyphsByPosition[idx].contains(glyph) {
                    glyphsByPosition[idx].append(glyph)
                }
            }
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Contextual substitution (after \(patternLength)-element)\n"
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
        
        // Define class for each position
        for (idx, glyphs) in glyphsByPosition.enumerated() {
            output += "Context\(idx + 1)\t\t\t" + glyphs.sorted().joined(separator: " ") + "\n"
        }
        output += "TargetGlyphs\t\t" + targetGlyphs.sorted().joined(separator: " ") + "\n\n"
        
        // Build state array
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL"
        for idx in 0..<patternLength {
            output += "\tContext\(idx + 1)"
        }
        output += "\tTargetGlyphs\n"
        
        // StartText state
        output += "StartText\t\t1\t1\t1\t1"
        output += "\t2"
        for _ in 1..<patternLength {
            output += "\t\t\t\t1"
        }
        output += "\t\t\t\t1\n"
        
        // StartLine state
        output += "StartLine\t\t1\t1\t1\t1"
        output += "\t2"
        for _ in 1..<patternLength {
            output += "\t\t\t\t1"
        }
        output += "\t\t\t\t1\n"
        
        // Intermediate states (SawContext1, SawContext2, etc.)
        for stateIdx in 0..<(patternLength - 1) {
            output += "SawContext\(stateIdx + 1)\t1\t1\t\(stateIdx + 2)\t1"
            
            for colIdx in 0..<patternLength {
                if colIdx == stateIdx + 1 {
                    output += "\t\(stateIdx + 3)"
                } else {
                    output += "\t\t\t\t1"
                }
            }
            output += "\t\t\t\t1\n"
        }
        
        // Final state (SawContextN)
        output += "SawContext\(patternLength)\t1\t1\t\(patternLength + 1)\t1"
        for _ in 0..<patternLength {
            output += "\t\t\t\t1"
        }
        output += "\t\t\t\t\(patternLength + 2)\n\n"
        
        // Transitions
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        
        for stateIdx in 0..<patternLength {
            output += "\(stateIdx + 2)\tSawContext\(stateIdx + 1)\tno\t\tyes\t\t\tnone\t\tnone\n"
        }
        
        output += "\(patternLength + 2)\tSawContext\(patternLength)\tno\t\tyes\t\t\tnone\t\tdoSubst\n\n"
        
        output += "doSubst\n"
        for rule in rules {
            guard case .after = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }

    // MARK: - Multi-Element Before Context

    private static func generateMultiElementBeforeSubtable(
        rules: [ExpandedContextualRule],
        featureName: String,
        selectorNumber: Int,
        tableNumber: Int
    ) throws -> String {
        guard let firstRule = rules.first,
              case .before(let sampleContext) = firstRule.context,
              sampleContext.count >= 2 else {
            throw OT2AATError.generationFailed("Multi-element before requires 2+ elements")
        }
        
        let patternLength = sampleContext.count
        
        // Collect glyphs at each position
        var targetGlyphs = Set<String>()
        var glyphsByPosition: [[String]] = Array(repeating: [], count: patternLength)
        
        for rule in rules {
            guard case .before(let context) = rule.context else { continue }
            targetGlyphs.insert(rule.substitutions[0].target)
            for (idx, glyph) in context.enumerated() {
                if !glyphsByPosition[idx].contains(glyph) {
                    glyphsByPosition[idx].append(glyph)
                }
            }
        }
        
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "// TABLE \(tableNumber): Contextual substitution (before \(patternLength)-element)\n"
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
        
        output += "TargetGlyphs\t\t" + targetGlyphs.sorted().joined(separator: " ") + "\n"
        for (idx, glyphs) in glyphsByPosition.enumerated() {
            output += "Context\(idx + 1)\t\t\t" + glyphs.sorted().joined(separator: " ") + "\n"
        }
        output += "\n"
        
        // Build state array
        output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tTargetGlyphs"
        for idx in 0..<patternLength {
            output += "\tContext\(idx + 1)"
        }
        output += "\n"
        
        // StartText state
        output += "StartText\t\t1\t1\t1\t1\t2"
        for _ in 0..<patternLength {
            output += "\t\t\t\t1"
        }
        output += "\n"
        
        // StartLine state
        output += "StartLine\t\t1\t1\t1\t1\t2"
        for _ in 0..<patternLength {
            output += "\t\t\t\t1"
        }
        output += "\n"
        
        // SawTarget state
        output += "SawTarget\t\t1\t1\t2\t1\t2"
        output += "\t\t\t\t3"
        for _ in 1..<patternLength {
            output += "\t\t\t\t1"
        }
        output += "\n"
        
        // Intermediate states
        for stateIdx in 1..<patternLength {
            output += "SawContext\(stateIdx)\t1\t1\t\(stateIdx + 2)\t1\t2"
            
            for colIdx in 0..<patternLength {
                if colIdx == stateIdx {
                    output += "\t\t\t\t\(stateIdx + 3)"
                } else {
                    output += "\t\t\t\t1"
                }
            }
            output += "\n"
        }
        output += "\n"
        
        // Transitions
        output += "\tGoTo\t\t\tMark?\tAdvance?\tSubstMark\tSubstCurrent\n"
        output += "1\tStartText\t\tno\t\tyes\t\t\tnone\t\tnone\n"
        output += "2\tSawTarget\t\tyes\t\tyes\t\t\tdoSubst\t\tnone\n"
        
        for stateIdx in 0..<(patternLength - 1) {
            output += "\(stateIdx + 3)\tSawContext\(stateIdx + 1)\tno\t\tyes\t\t\tdoSubst\t\tnone\n"
        }
        
        output += "\(patternLength + 2)\tStartText\t\tno\t\tyes\t\t\tdoSubst\t\tnone\n\n"
        
        output += "doSubst\n"
        for rule in rules {
            guard case .before = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "\t\(target)\t\t\(replacement)\n"
        }
        
        return output
    }
}

