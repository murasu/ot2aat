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

extension ATIFGenerator {
    /// Generate ATIF for contextual substitution
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
        
        // Group decomposed rules by temp glyph family to avoid collisions
        var decomposedRuleSets: [[ExpandedContextualRule]] = []
        var regularRules: [ExpandedContextualRule] = []
        
        for rule in singlePassRules {
            let usesTemp = rule.substitutions.contains { sub in
                let target = sub.target
                let replacement = sub.replacement
                return (target.count >= 5 && Int(target.prefix(2)) ?? 0 >= 65) ||
                       (replacement.count >= 5 && Int(replacement.prefix(2)) ?? 0 >= 65)
            }
            
            if usesTemp {
                var tempGlyph: String? = nil
                for sub in rule.substitutions {
                    if sub.target.count >= 5, let val = Int(sub.target.prefix(2)), val >= 65 {
                        tempGlyph = sub.target
                        break
                    }
                    if sub.replacement.count >= 5, let val = Int(sub.replacement.prefix(2)), val >= 65 {
                        tempGlyph = sub.replacement
                        break
                    }
                }
                
                if let temp = tempGlyph {
                    if let existingIndex = decomposedRuleSets.firstIndex(where: { set in
                        set.contains { r in
                            r.substitutions.contains { $0.target == temp || $0.replacement == temp }
                        }
                    }) {
                        decomposedRuleSets[existingIndex].append(rule)
                    } else {
                        decomposedRuleSets.append([rule])
                    }
                } else {
                    regularRules.append(rule)
                }
            } else {
                regularRules.append(rule)
            }
        }
        
        // Group regular rules by context type
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
            if subtableNumber > 0 { output += "\n" }
            output += try generateContextualSubtable(
                rules: rulesForType,
                contextType: contextType,
                subtableNumber: subtableNumber
            )
            subtableNumber += 1
        }
        
        // Generate each decomposed rule set separately (keeps temp glyphs isolated)
        for ruleSet in decomposedRuleSets {
            let grouped = Dictionary(grouping: ruleSet) { rule -> String in
                switch rule.context {
                case .after: return "after"
                case .before: return "before"
                case .between: return "between"
                case .when: return "when"
                case .cleanup: return "cleanup"
                }
            }
            
            for (contextType, rulesForType) in grouped.sorted(by: { $0.key < $1.key }) {
                if subtableNumber > 0 { output += "\n" }
                output += try generateContextualSubtable(
                    rules: rulesForType,
                    contextType: contextType,
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
        
        // Generate cleanup rules
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
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (after context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        var contextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        
        for rule in rules {
            guard case .after(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        output += "    class ContextGlyphs { " + contextGlyphs.sorted().joined(separator: ", ") + " };\n"
        output += "    class TargetGlyphs { " + targetGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
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
        output += "        change state to Start;\n"
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
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (before context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        var targetGlyphs = Set<String>()
        var contextGlyphs = Set<String>()
        
        for rule in rules {
            guard case .before(let context) = rule.context else { continue }
            contextGlyphs.formUnion(context)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        output += "    class TargetGlyphs { " + targetGlyphs.sorted().joined(separator: ", ") + " };\n"
        output += "    class ContextGlyphs { " + contextGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
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
    
    // MARK: - Between Context
    
    private static func generateBetweenSubtable(
        rules: [ExpandedContextualRule],
        subtableNumber: Int
    ) throws -> String {
        var output = ""
        
        output += "// Contextual subtable \(subtableNumber) (between context)\n"
        output += "contextual subtable (SmartSwash, WordInitialSwashes) {\n"
        
        var firstContextGlyphs = Set<String>()
        var targetGlyphs = Set<String>()
        var secondContextGlyphs = Set<String>()
        
        for rule in rules {
            guard case .between(let first, let second) = rule.context else { continue }
            firstContextGlyphs.formUnion(first)
            secondContextGlyphs.formUnion(second)
            targetGlyphs.insert(rule.substitutions[0].target)
        }
        
        output += "    class FirstContext { " + firstContextGlyphs.sorted().joined(separator: ", ") + " };\n"
        output += "    class TargetGlyphs { " + targetGlyphs.sorted().joined(separator: ", ") + " };\n"
        output += "    class SecondContext { " + secondContextGlyphs.sorted().joined(separator: ", ") + " };\n\n"
        
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
}


