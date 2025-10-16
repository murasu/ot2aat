import Foundation

extension ATIFGenerator {
    /// Generate ATIF for contextual substitution
    
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
    
    // MARK: - Contextual substitution

    static func generateContextual(
        rules: [ContextualRule],
        classes: [GlyphClass],
        featureName: String,
        selectorNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// " + String(repeating: "-", count: 79) + "\n"
        output += "//\n"
        output += "//  Generated ATIF for contextual substitution\n"
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
        
        var expandedRules: [ExpandedContextualRule] = []
        for rule in rules {
            let expanded = try rule.expand(using: registry)
            expandedRules.append(contentsOf: expanded)
        }
        
        // Separate into categories
        let cleanupRules = expandedRules.filter { $0.isCleanup }
        let multiPassRules = expandedRules.filter { $0.needsMultiPass && !$0.isCleanup }
        let singlePassRules = expandedRules.filter { !$0.needsMultiPass && !$0.isCleanup }
        
        var subtableNumber = 0
        
        // Separate "after" rules by BOTH pattern length AND context set
        let allAfterRules = singlePassRules.filter {
            if case .after = $0.context { return true }
            return false
        }
        
        // Group by pattern length first
        let afterByLength = Dictionary(grouping: allAfterRules) { rule -> Int in
            guard case .after(let context) = rule.context else { return 0 }
            return context.count
        }
        
        // For each length, further group by context set
        var afterSubtableGroups: [(length: Int, contextKey: String, rules: [ExpandedContextualRule])] = []
        
        for (length, rulesForLength) in afterByLength {
            if length == 1 {
                // For single-element patterns, group by the actual context glyph
                let grouped = Dictionary(grouping: rulesForLength) { rule -> String in
                    guard case .after(let context) = rule.context else { return "" }
                    return context[0] // Group by the single context glyph
                }
                
                for (contextKey, rules) in grouped.sorted(by: { $0.key < $1.key }) {
                    afterSubtableGroups.append((length: length, contextKey: contextKey, rules: rules))
                }
            } else {
                // For multi-element patterns, keep them together
                afterSubtableGroups.append((length: length, contextKey: "", rules: rulesForLength))
            }
        }
        
        // Generate a separate subtable for each group
        for group in afterSubtableGroups {
            if subtableNumber > 0 { output += "\n" }
            
            if group.length > 1 {
                output += try generateMultiElementAfterSubtable(
                    rules: group.rules,
                    subtableNumber: subtableNumber
                )
            } else {
                output += try generateContextualSubtable(
                    rules: group.rules,
                    contextType: "after",
                    subtableNumber: subtableNumber
                )
            }
            subtableNumber += 1
        }
        
        // Separate "before" rules by BOTH pattern length AND context set
        let allBeforeRules = singlePassRules.filter {
            if case .before = $0.context { return true }
            return false
        }
        
        // Group by pattern length first
        let beforeByLength = Dictionary(grouping: allBeforeRules) { rule -> Int in
            guard case .before(let context) = rule.context else { return 0 }
            return context.count
        }
        
        // For each length, further group by context set
        var beforeSubtableGroups: [(length: Int, contextKey: String, rules: [ExpandedContextualRule])] = []
        
        for (length, rulesForLength) in beforeByLength {
            if length == 1 {
                // For single-element patterns, group by the actual context glyph
                let grouped = Dictionary(grouping: rulesForLength) { rule -> String in
                    guard case .before(let context) = rule.context else { return "" }
                    return context[0] // Group by the single context glyph
                }
                
                for (contextKey, rules) in grouped.sorted(by: { $0.key < $1.key }) {
                    beforeSubtableGroups.append((length: length, contextKey: contextKey, rules: rules))
                }
            } else {
                // For multi-element patterns, keep them together
                beforeSubtableGroups.append((length: length, contextKey: "", rules: rulesForLength))
            }
        }
        
        // Generate a separate subtable for each group
        for group in beforeSubtableGroups {
            if subtableNumber > 0 { output += "\n" }
            
            if group.length > 1 {
                output += try generateMultiElementBeforeSubtable(
                    rules: group.rules,
                    subtableNumber: subtableNumber
                )
            } else {
                output += try generateContextualSubtable(
                    rules: group.rules,
                    contextType: "before",
                    subtableNumber: subtableNumber
                )
            }
            subtableNumber += 1
        }
        
        // Between and when don't need context grouping
        let allBetweenRules = singlePassRules.filter {
            if case .between = $0.context { return true }
            return false
        }
        
        let allWhenRules = singlePassRules.filter {
            if case .when = $0.context { return true }
            return false
        }
        
        if !allBetweenRules.isEmpty {
            if subtableNumber > 0 { output += "\n" }
            output += try generateContextualSubtable(
                rules: allBetweenRules,
                contextType: "between",
                subtableNumber: subtableNumber
            )
            subtableNumber += 1
        }
        
        if !allWhenRules.isEmpty {
            if subtableNumber > 0 { output += "\n" }
            output += try generateContextualSubtable(
                rules: allWhenRules,
                contextType: "when",
                subtableNumber: subtableNumber
            )
            subtableNumber += 1
        }
        
        // Generate cleanup subtables grouped by ruleGroupID
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
                if subtableNumber > 0 { output += "\n" }
                output += try generateCleanupSubtable(
                    rules: cleanupRulesInGroup,
                    subtableNumber: subtableNumber
                )
                subtableNumber += 1
            }
        }
        
        // Generate multi-pass rules
        for multiPassRule in multiPassRules {
            if subtableNumber > 0 { output += "\n" }
            output += try generateMultiPassSubtablesForContextual(
                rule: multiPassRule,
                startSubtableNumber: subtableNumber
            )
            subtableNumber += 3
        }
        
        // Generate remaining cleanup rules
        if !cleanupRules.isEmpty {
            if subtableNumber > 0 { output += "\n" }
            output += try generateCleanupSubtable(
                rules: cleanupRules,
                subtableNumber: subtableNumber
            )
        }
        
        return output
    }
    
    private static func generateContextualSubtable(
        rules: [ExpandedContextualRule],
        contextType: String,
        subtableNumber: Int
    ) throws -> String {
        switch contextType {
        case "after":
            return try generateAfterSubtable(rules: rules, subtableNumber: subtableNumber)
        case "before":
            return try generateBeforeSubtable(rules: rules, subtableNumber: subtableNumber)
        case "between":
            return try generateBetweenSubtable(rules: rules, subtableNumber: subtableNumber)
        case "when":
            return try generateWhenSubtable(rules: rules, subtableNumber: subtableNumber)
        default:
            throw OT2AATError.generationFailed("Unknown context type: \(contextType)")
        }
    }
    
    // MARK: - After Context
    
    private static func generateAfterSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
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
            return try generateAfterSubtableWithOverlap(
                targetOnly: tgtOnly,
                contextOnly: ctxOnly,
                both: both,
                rules: rules,
                subtableNumber: subtableNumber
            )
        } else {
            return try generateAfterSubtableSimple(
                targets: targetGlyphs,
                contexts: contextGlyphs,
                rules: rules,
                subtableNumber: subtableNumber
            )
        }
    }
    
    private static func generateAfterSubtableSimple(
        targets: Set<String>,
        contexts: Set<String>,
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (after context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        output += "    class ContextGlyphs { " + contexts.sorted().joined(separator: ", ") + " };\n"
        output += "    class TargetGlyphs { " + targets.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        ContextGlyphs: SawContext;\n"
        output += "    };\n\n"
        
        output += "    state SawContext {\n"
        output += "        ContextGlyphs: SawContext;\n"
        output += "        TargetGlyphs: DoSubstitution;\n"
        output += "    };\n\n"
        
        output += "    transition SawContext {\n"
        output += "        change state to SawContext;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to SawContext;\n"
        output += "        current glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .after = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    private static func generateAfterSubtableWithOverlap(
        targetOnly: Set<String>,
        contextOnly: Set<String>,
        both: Set<String>,
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (after context with overlap)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Three classes
        output += "    class Context { " + contextOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class Target { " + targetOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class TrgtAndCntx { " + both.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        Context: SawContext;\n"
        output += "        TrgtAndCntx: SawContext;\n"
        output += "    };\n\n"
        
        output += "    state SawContext {\n"
        output += "        Context: SawContext;\n"
        output += "        Target: DoSubstitution;\n"
        output += "        TrgtAndCntx: DoSubstitutionBoth;\n"
        output += "    };\n\n"
        
        output += "    transition SawContext {\n"
        output += "        change state to SawContext;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to SawContext;\n"
        output += "        current glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitutionBoth {\n"
        output += "        change state to SawContext;\n"
        output += "        current glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .after = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    // MARK: - Before Context
    
    private static func generateBeforeSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
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
            return try generateBeforeSubtableWithOverlap(
                targetOnly: tgtOnly,
                contextOnly: ctxOnly,
                both: both,
                rules: rules,
                subtableNumber: subtableNumber
            )
        } else {
            return try generateBeforeSubtableSimple(
                targets: targetGlyphs,
                contexts: contextGlyphs,
                rules: rules,
                subtableNumber: subtableNumber
            )
        }
    }
    
    private static func generateBeforeSubtableSimple(
        targets: Set<String>,
        contexts: Set<String>,
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (before context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        output += "    class TargetGlyphs { " + targets.sorted().joined(separator: ", ") + " };\n"
        output += "    class ContextGlyphs { " + contexts.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        TargetGlyphs: MarkTarget;\n"
        output += "    };\n\n"
        
        output += "    state SawTarget {\n"
        output += "        TargetGlyphs: MarkTarget;\n"
        output += "        ContextGlyphs: DoSubstitution;\n"
        output += "    };\n\n"
        
        output += "    transition MarkTarget {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to Start;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .before = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    private static func generateBeforeSubtableWithOverlap(
        targetOnly: Set<String>,
        contextOnly: Set<String>,
        both: Set<String>,
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (before context with overlap)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Three classes
        output += "    class Target { " + targetOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class Context { " + contextOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class TrgtAndCntx { " + both.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        Target: MarkTarget;\n"
        output += "        TrgtAndCntx: MarkTarget;\n"
        output += "    };\n\n"
        
        output += "    state SawTarget {\n"
        output += "        Target: MarkTarget;\n"
        output += "        Context: DoSubstitution;\n"
        output += "        TrgtAndCntx: DoSubstitutionAndMark;\n"
        output += "    };\n\n"
        
        output += "    transition MarkTarget {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to Start;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitutionAndMark {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .before = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    // MARK: - Between Context
    
    private static func generateBetweenSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
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
            return try generateBetweenSubtableWithOverlap(
                firstContext: firstContextGlyphs,
                targetOnly: tgtOnly,
                secondContext: secondContextGlyphs,
                both: both,
                rules: rules,
                subtableNumber: subtableNumber
            )
        } else {
            return try generateBetweenSubtableSimple(
                firstContext: firstContextGlyphs,
                targets: targetGlyphs,
                secondContext: secondContextGlyphs,
                rules: rules,
                subtableNumber: subtableNumber
            )
        }
    }
    
    private static func generateBetweenSubtableSimple(
        firstContext: Set<String>,
        targets: Set<String>,
        secondContext: Set<String>,
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (between context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        output += "    class FirstContext { " + firstContext.sorted().joined(separator: ", ") + " };\n"
        output += "    class TargetGlyphs { " + targets.sorted().joined(separator: ", ") + " };\n"
        output += "    class SecondContext { " + secondContext.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        FirstContext: SawFirst;\n"
        output += "    };\n\n"
        
        output += "    state SawFirst {\n"
        output += "        FirstContext: SawFirst;\n"
        output += "        TargetGlyphs: MarkTarget;\n"
        output += "    };\n\n"
        
        output += "    state SawTarget {\n"
        output += "        TargetGlyphs: MarkTarget;\n"
        output += "        SecondContext: DoSubstitution;\n"
        output += "    };\n\n"
        
        output += "    transition SawFirst {\n"
        output += "        change state to SawFirst;\n"
        output += "    };\n\n"
        
        output += "    transition MarkTarget {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to Start;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .between = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    private static func generateBetweenSubtableWithOverlap(
        firstContext: Set<String>,
        targetOnly: Set<String>,
        secondContext: Set<String>,
        both: Set<String>,
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (between context with overlap)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Separate pure contexts from overlapping glyphs
        let firstOnly = firstContext.subtracting(targetOnly).subtracting(both)
        let secondOnly = secondContext.subtracting(targetOnly).subtracting(both)
        
        // Build classes carefully
        output += "    class FirstContext { " + firstOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class Target { " + targetOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class SecondContext { " + secondOnly.sorted().joined(separator: ", ") + " };\n"
        output += "    class TrgtAndCntx { " + both.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        FirstContext: SawFirst;\n"
        output += "        TrgtAndCntx: SawFirst;\n"
        output += "    };\n\n"
        
        output += "    state SawFirst {\n"
        output += "        FirstContext: SawFirst;\n"
        output += "        Target: MarkTarget;\n"
        output += "        TrgtAndCntx: MarkTargetBoth;\n"
        output += "    };\n\n"
        
        output += "    state SawTarget {\n"
        output += "        Target: MarkTarget;\n"
        output += "        SecondContext: DoSubstitution;\n"
        output += "        TrgtAndCntx: DoSubstitutionAndMark;\n"
        output += "    };\n\n"
        
        output += "    transition SawFirst {\n"
        output += "        change state to SawFirst;\n"
        output += "    };\n\n"
        
        output += "    transition MarkTarget {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition MarkTargetBoth {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to Start;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    transition DoSubstitutionAndMark {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .between = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    // MARK: - When Context
    
    private static func generateWhenSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (when context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        var allPatternGlyphs = Set<String>()
        
        for rule in rules {
            guard case .when(let pattern) = rule.context else { continue }
            allPatternGlyphs.formUnion(pattern)
        }
        
        output += "    class PatternGlyphs { " + allPatternGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        PatternGlyphs: Matching;\n"
        output += "    };\n\n"
        
        output += "    state Matching {\n"
        output += "        PatternGlyphs: CheckSubstitution;\n"
        output += "    };\n\n"
        
        output += "    transition Matching {\n"
        output += "        change state to Matching;\n"
        output += "    };\n\n"
        
        output += "    transition CheckSubstitution {\n"
        output += "        change state to Matching;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
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
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    // MARK: - Multi-pass Subtables
    
    private static func generateMultiPassSubtablesForContextual(
        rule: ExpandedContextualRule,
        startSubtableNumber: Int
    ) throws -> String {
        var output = ""
        
        guard case .when(let pattern) = rule.context else {
            throw OT2AATError.generationFailed("Multi-pass only for 'when' context")
        }
        
        let tempGlyphs = (0..<(rule.substitutions.count - 1)).map { 65000 + $0 }
        
        output += try generateMarkingSubtableForContextual(
            pattern: pattern,
            substitutions: rule.substitutions,
            tempGlyphs: tempGlyphs,
            subtableNumber: startSubtableNumber
        )
        
        output += "\n"
        
        output += try generateFinalSubstitutionSubtableForContextual(
            tempGlyphs: tempGlyphs,
            substitutions: rule.substitutions,
            subtableNumber: startSubtableNumber + 1
        )
        
        output += "\n"
        
        output += try generateCleanupSubtableForMultiPass(
            tempGlyphs: tempGlyphs,
            subtableNumber: startSubtableNumber + 2
        )
        
        return output
    }
    
    private static func generateMarkingSubtableForContextual(
        pattern: [String],
        substitutions: [(String, String)],
        tempGlyphs: [Int],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (multi-pass marking)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        output += "    class PatternGlyphs { " + pattern.joined(separator: ", ") + " };\n\n"
        
        output += "    state Start {\n"
        output += "        PatternGlyphs: DoMarking;\n"
        output += "    };\n\n"
        
        output += "    transition DoMarking {\n"
        output += "        change state to Start;\n"
        output += "        current glyph substitution: MarkWithTemp;\n"
        output += "    };\n\n"
        
        output += "    substitution MarkWithTemp {\n"
        for (idx, (target, _)) in substitutions.dropLast().enumerated() {
            output += "        \(target) => \(tempGlyphs[idx]);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
    
    private static func generateFinalSubstitutionSubtableForContextual(
        tempGlyphs: [Int],
        substitutions: [(String, String)],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Noncontextual subtable \(subtableNumber) (multi-pass final)\n"
        output += "noncontextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        for (idx, (_, replacement)) in substitutions.dropLast().enumerated() {
            output += "    \(tempGlyphs[idx]) => \(replacement);\n"
        }
        let (lastTarget, lastReplacement) = substitutions.last!
        output += "    \(lastTarget) => \(lastReplacement);\n"
        
        output += "};\n"
        
        return output
    }
    
    private static func generateCleanupSubtableForMultiPass(
        tempGlyphs: [Int],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Noncontextual subtable \(subtableNumber) (cleanup)\n"
        output += "noncontextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        for tempGlyph in tempGlyphs {
            output += "    \(tempGlyph) => DEL;\n"
        }
        
        output += "};\n"
        
        return output
    }
    
    // MARK: - Cleanup Subtable
    
    private static func generateCleanupSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Noncontextual subtable \(subtableNumber) (cleanup incomplete patterns)\n"
        output += "noncontextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        for rule in rules {
            guard case .cleanup = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "    \(target) => \(replacement);\n"
        }
        
        output += "};\n"
        
        return output
    }
    
    // MARK: - Multi-Element After Context

    private static func generateMultiElementAfterSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
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
        
        output += "// Contextual subtable \(subtableNumber) (after \(patternLength)-element)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        // Define class for each position
        for (idx, glyphs) in glyphsByPosition.enumerated() {
            output += "    class Context\(idx + 1) { " + glyphs.sorted().joined(separator: ", ") + " };\n"
        }
        output += "    class TargetGlyphs { " + targetGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
        // Start state
        output += "    state Start {\n"
        output += "        Context1: SawContext1;\n"
        output += "    };\n\n"
        
        // Intermediate states
        for stateIdx in 1..<patternLength {
            output += "    state SawContext\(stateIdx) {\n"
            output += "        Context\(stateIdx): SawContext\(stateIdx);\n"
            output += "        Context\(stateIdx + 1): SawContext\(stateIdx + 1);\n"
            output += "    };\n\n"
        }
        
        // Final state
        output += "    state SawContext\(patternLength) {\n"
        output += "        Context\(patternLength): SawContext\(patternLength);\n"
        output += "        TargetGlyphs: DoSubstitution;\n"
        output += "    };\n\n"
        
        // Transitions
        for stateIdx in 1...patternLength {
            output += "    transition SawContext\(stateIdx) {\n"
            output += "        change state to SawContext\(stateIdx);\n"
            output += "    };\n\n"
        }
        
        output += "    transition DoSubstitution {\n"
        output += "        change state to SawContext\(patternLength);\n"
        output += "        current glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .after = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }

    // MARK: - Multi-Element Before Context

    private static func generateMultiElementBeforeSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
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
        
        output += "// Contextual subtable \(subtableNumber) (before \(patternLength)-element)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        output += "    class TargetGlyphs { " + targetGlyphs.sorted().joined(separator: ", ") + " };\n"
        for (idx, glyphs) in glyphsByPosition.enumerated() {
            output += "    class Context\(idx + 1) { " + glyphs.sorted().joined(separator: ", ") + " };\n"
        }
        output += "\n"
        
        // Start state
        output += "    state Start {\n"
        output += "        TargetGlyphs: MarkTarget;\n"
        output += "    };\n\n"
        
        // SawTarget state
        output += "    state SawTarget {\n"
        output += "        TargetGlyphs: MarkTarget;\n"
        output += "        Context1: SawContext1;\n"
        output += "    };\n\n"
        
        // Intermediate states
        for stateIdx in 1..<patternLength {
            output += "    state SawContext\(stateIdx) {\n"
            output += "        TargetGlyphs: MarkTarget;\n"
            output += "        Context\(stateIdx + 1): SawContext\(stateIdx + 1);\n"
            output += "    };\n\n"
        }
        
        // Transitions
        output += "    transition MarkTarget {\n"
        output += "        change state to SawTarget;\n"
        output += "        mark glyph;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        for stateIdx in 1..<patternLength {
            output += "    transition SawContext\(stateIdx) {\n"
            output += "        change state to SawContext\(stateIdx);\n"
            output += "        marked glyph substitution: SubstTarget;\n"
            output += "    };\n\n"
        }
        
        output += "    transition SawContext\(patternLength) {\n"
        output += "        change state to Start;\n"
        output += "        marked glyph substitution: SubstTarget;\n"
        output += "    };\n\n"
        
        output += "    substitution SubstTarget {\n"
        for rule in rules {
            guard case .before = rule.context else { continue }
            let (target, replacement) = rule.substitutions[0]
            output += "        \(target) => \(replacement);\n"
        }
        output += "    };\n"
        
        output += "};\n"
        
        return output
    }
}


