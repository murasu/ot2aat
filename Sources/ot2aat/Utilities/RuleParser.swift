import Foundation

struct RuleParser {
    /// Parse one-to-many rules from a file
    /// Format: source > target1 target2 target3
    static func parseOne2ManyRules(from path: String) throws -> [SubstitutionRule] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw OT2AATError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var rules: [SubstitutionRule] = []
        
        for (lineNumber, line) in content.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse rule: source > target1 target2 ...
            let parts = trimmed.components(separatedBy: ">")
            guard parts.count == 2 else {
                throw OT2AATError.invalidRule("Line \(lineNumber + 1): Expected format 'source > target1 target2 ...'")
            }
            
            let source = parts[0].trimmingCharacters(in: .whitespaces)
            let targets = parts[1]
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            
            guard !source.isEmpty else {
                throw OT2AATError.invalidRule("Line \(lineNumber + 1): Source glyph cannot be empty")
            }
            
            guard !targets.isEmpty else {
                throw OT2AATError.invalidRule("Line \(lineNumber + 1): Must have at least one target glyph")
            }
            
            rules.append(SubstitutionRule(source: source, targets: targets))
        }
        
        if rules.isEmpty {
            throw OT2AATError.invalidRule("No valid rules found in file")
        }
        
        return rules
    }
}


extension RuleParser {
    /// Parse reorder rules from a file
    /// Format:
    ///   @class name = glyph1 glyph2 ...
    ///   pattern => pattern
    static func parseReorderRules(from path: String) throws -> (classes: [GlyphClass], rules: [ReorderRule]) {
        guard FileManager.default.fileExists(atPath: path) else {
            throw OT2AATError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var registry = GlyphClassRegistry()
        var classes: [GlyphClass] = []
        var rules: [ReorderRule] = []
        
        for (lineNumber, line) in content.components(separatedBy: .newlines).enumerated() {
            let lineNum = lineNumber + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Remove end-of-line comments
            let withoutComment = trimmed.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            // Parse class definition
            if withoutComment.hasPrefix("@class ") {
                let glyphClass = try parseClassDefinition(withoutComment, lineNumber: lineNum)
                try registry.register(glyphClass)
                classes.append(glyphClass)
                continue
            }
            
            // Parse reorder rule
            if withoutComment.contains("=>") {
                let rule = try parseReorderRule(withoutComment, lineNumber: lineNum, registry: registry)
                rules.append(rule)
                continue
            }
            
            // Unknown line format
            throw OT2AATError.invalidRule("Line \(lineNum): Unrecognized syntax: '\(trimmed)'")
        }
        
        if rules.isEmpty {
            throw OT2AATError.invalidRule("No valid rules found in file")
        }
        
        return (classes, rules)
    }
    
    /// Parse a class definition line
    /// Format: @class name = glyph1 glyph2 glyph3 ...
    private static func parseClassDefinition(_ line: String, lineNumber: Int) throws -> GlyphClass {
        // Remove "@class " prefix
        let withoutPrefix = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
        
        // Split on '='
        let parts = withoutPrefix.components(separatedBy: "=")
        guard parts.count == 2 else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Invalid class definition syntax
                Expected: @class name = glyph1 glyph2 ...
                Got: \(line)
                """
            )
        }
        
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let glyphsString = parts[1].trimmingCharacters(in: .whitespaces)
        
        // Validate class name
        guard !name.isEmpty else {
            throw OT2AATError.invalidRule("Line \(lineNumber): Class name cannot be empty")
        }
        
        guard isValidIdentifier(name) else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Invalid class name '@\(name)'
                Class names must start with a letter or underscore
                and contain only letters, digits, and underscores
                """
            )
        }
        
        // Parse glyph list
        let glyphs = glyphsString
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        guard !glyphs.isEmpty else {
            throw OT2AATError.invalidRule("Line \(lineNumber): Class '@\(name)' cannot be empty")
        }
        
        return GlyphClass(name: name, glyphs: glyphs)
    }
    
    /// Parse a reorder rule line
    /// Format: element1 element2 => element1' element2'
    private static func parseReorderRule(
        _ line: String,
        lineNumber: Int,
        registry: GlyphClassRegistry
    ) throws -> ReorderRule {
        // Split on '=>'
        let parts = line.components(separatedBy: "=>")
        guard parts.count == 2 else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Invalid rule syntax
                Expected: pattern => pattern
                Got: \(line)
                """
            )
        }
        
        let beforeStr = parts[0].trimmingCharacters(in: .whitespaces)
        let afterStr = parts[1].trimmingCharacters(in: .whitespaces)
        
        // Parse elements
        let beforeElements = try parseRuleElements(beforeStr, lineNumber: lineNumber)
        let afterElements = try parseRuleElements(afterStr, lineNumber: lineNumber)
        
        // Validate element count
        guard beforeElements.count == afterElements.count else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Element count mismatch
                Left side has \(beforeElements.count) elements
                Right side has \(afterElements.count) elements
                Both sides must have the same number of elements
                """
            )
        }
        
        // Validate element count (2-4)
        guard beforeElements.count >= 2 && beforeElements.count <= 4 else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Invalid pattern length
                Pattern must have 2-4 elements, got \(beforeElements.count)
                AAT supports maximum 4-element rearrangement patterns
                """
            )
        }
        
        // Verify all class references exist
        for element in beforeElements + afterElements {
            if case .classRef(let name) = element {
                guard registry.contains(name) else {
                    throw OT2AATError.invalidRule(
                        """
                        Line \(lineNumber): Undefined class '@\(name)'
                        Define class before use: @class \(name) = ...
                        """
                    )
                }
            }
        }
        
        return ReorderRule(before: beforeElements, after: afterElements, lineNumber: lineNumber)
    }
    
    /// Parse rule elements from a string
    private static func parseRuleElements(_ string: String, lineNumber: Int) throws -> [RuleElement] {
        let tokens = string
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        guard !tokens.isEmpty else {
            throw OT2AATError.invalidRule("Line \(lineNumber): Empty pattern")
        }
        
        return tokens.map { token in
            if token.hasPrefix("@") {
                // Class reference
                let className = String(token.dropFirst())
                return .classRef(className)
            } else {
                // Explicit glyph
                return .glyph(token)
            }
        }
    }
    
    /// Parse a single reorder rule from command line (no classes)
    static func parseReorderRuleFromString(_ ruleString: String) throws -> ReorderRule {
        let parts = ruleString.components(separatedBy: "=>")
        guard parts.count == 2 else {
            throw OT2AATError.invalidRule(
                """
                Invalid rule syntax
                Expected: glyph1 glyph2 => glyph2 glyph1
                Got: \(ruleString)
                """
            )
        }
        
        let beforeStr = parts[0].trimmingCharacters(in: .whitespaces)
        let afterStr = parts[1].trimmingCharacters(in: .whitespaces)
        
        let beforeGlyphs = beforeStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let afterGlyphs = afterStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        // No class references allowed in CLI mode
        for glyph in beforeGlyphs + afterGlyphs {
            if glyph.hasPrefix("@") {
                throw OT2AATError.invalidRule(
                    """
                    Class references not supported in single-rule mode
                    Use -i/--input with a rules file for class support
                    Got: \(glyph)
                    """
                )
            }
        }
        
        guard beforeGlyphs.count == afterGlyphs.count else {
            throw OT2AATError.invalidRule(
                """
                Element count mismatch
                Left side has \(beforeGlyphs.count) elements
                Right side has \(afterGlyphs.count) elements
                """
            )
        }
        
        guard beforeGlyphs.count >= 2 && beforeGlyphs.count <= 4 else {
            throw OT2AATError.invalidRule(
                """
                Pattern must have 2-4 elements, got \(beforeGlyphs.count)
                """
            )
        }
        
        let beforeElements = beforeGlyphs.map { RuleElement.glyph($0) }
        let afterElements = afterGlyphs.map { RuleElement.glyph($0) }
        
        return ReorderRule(before: beforeElements, after: afterElements, lineNumber: 1)
    }
    
    /// Check if a string is a valid identifier
    private static func isValidIdentifier(_ string: String) -> Bool {
        guard !string.isEmpty else { return false }
        
        let first = string.first!
        guard first.isLetter || first == "_" else { return false }
        
        return string.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

extension RuleParser {
    /// Parse contextual substitution rules from a file
    static func parseContextualRules(from path: String) throws -> (classes: [GlyphClass], rules: [ContextualRule]) {
        guard FileManager.default.fileExists(atPath: path) else {
            throw OT2AATError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var registry = GlyphClassRegistry()
        var classes: [GlyphClass] = []
        var rules: [ContextualRule] = []
        
        for (lineNumber, line) in content.components(separatedBy: .newlines).enumerated() {
            let lineNum = lineNumber + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Remove end-of-line comments
            let withoutComment = trimmed.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            // Parse class definition
            if withoutComment.hasPrefix("@class ") {
                let glyphClass = try parseClassDefinition(withoutComment, lineNumber: lineNum)
                try registry.register(glyphClass)
                classes.append(glyphClass)
                continue
            }
            
            // Parse contextual rule
            if withoutComment.contains(":") && withoutComment.contains("=>") {
                let rule = try parseContextualRule(withoutComment, lineNumber: lineNum, registry: registry)
                rules.append(rule)
                continue
            }
            
            throw OT2AATError.invalidRule("Line \(lineNum): Unrecognized syntax: '\(trimmed)'")
        }
        
        if rules.isEmpty {
            throw OT2AATError.invalidRule("No valid rules found in file")
        }
        
        return (classes, rules)
    }
    
    /// Parse a single contextual rule line
    private static func parseContextualRule(
        _ line: String,
        lineNumber: Int,
        registry: GlyphClassRegistry
    ) throws -> ContextualRule {
        // Split by ':' to separate context from substitution
        let parts = line.components(separatedBy: ":")
        guard parts.count == 2 else {
            throw OT2AATError.invalidRule(
                "Line \(lineNumber): Expected format 'context: target => replacement'"
            )
        }
        
        let contextStr = parts[0].trimmingCharacters(in: .whitespaces)
        let substStr = parts[1].trimmingCharacters(in: .whitespaces)
        
        // Parse context
        let context = try parseContext(contextStr, lineNumber: lineNumber)
        
        // Parse substitutions
        let substitutions = try parseSubstitutions(substStr, lineNumber: lineNumber)
        
        // Validate substitutions based on context type
        if case .when = context {
            // Multiple substitutions allowed
        } else {
            // Only single substitution for after/before/between
            guard substitutions.count == 1 else {
                throw OT2AATError.invalidRule(
                    "Line \(lineNumber): Only 'when' context supports multiple substitutions"
                )
            }
        }
        
        return ContextualRule(context: context, substitutions: substitutions, lineNumber: lineNumber)
    }
    
    /// Parse context pattern
    private static func parseContext(_ contextStr: String, lineNumber: Int) throws -> ContextType {
        let lower = contextStr.lowercased()
        
        if lower.hasPrefix("after ") {
            let pattern = String(contextStr.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            let elements = try parseRuleElements(pattern, lineNumber: lineNumber)
            guard !elements.isEmpty && elements.count <= 10 else {
                throw OT2AATError.invalidRule("Line \(lineNumber): Context pattern must have 1-10 elements")
            }
            return .after(elements)
            
        } else if lower.hasPrefix("before ") {
            let pattern = String(contextStr.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            let elements = try parseRuleElements(pattern, lineNumber: lineNumber)
            guard !elements.isEmpty && elements.count <= 10 else {
                throw OT2AATError.invalidRule("Line \(lineNumber): Context pattern must have 1-10 elements")
            }
            return .before(elements)
            
        } else if lower.hasPrefix("between ") && lower.contains(" and ") {
            let betweenPart = String(contextStr.dropFirst(8))
            let andParts = betweenPart.components(separatedBy: " and ")
            guard andParts.count == 2 else {
                throw OT2AATError.invalidRule(
                    "Line \(lineNumber): Expected 'between pattern1 and pattern2'"
                )
            }
            
            let first = try parseRuleElements(andParts[0].trimmingCharacters(in: .whitespaces), lineNumber: lineNumber)
            let second = try parseRuleElements(andParts[1].trimmingCharacters(in: .whitespaces), lineNumber: lineNumber)
            
            guard !first.isEmpty && !second.isEmpty else {
                throw OT2AATError.invalidRule("Line \(lineNumber): Both patterns must be non-empty")
            }
            guard first.count <= 10 && second.count <= 10 else {
                throw OT2AATError.invalidRule("Line \(lineNumber): Context patterns must have max 10 elements")
            }
            
            return .between(first: first, second: second)
            
        } else if lower.hasPrefix("when ") {
            let pattern = String(contextStr.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let elements = try parseRuleElements(pattern, lineNumber: lineNumber)
            guard !elements.isEmpty && elements.count <= 10 else {
                throw OT2AATError.invalidRule("Line \(lineNumber): Pattern must have 1-10 elements")
            }
            return .when(elements)
            
        } else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Unknown context type
                Expected: 'after', 'before', 'between', or 'when'
                Got: '\(contextStr)'
                """
            )
        }
    }
    
    /// Parse substitutions (comma-separated for 'when' context)
    private static func parseSubstitutions(_ substStr: String, lineNumber: Int) throws -> [SubstitutionPair] {
        let substParts = substStr.components(separatedBy: ",")
        var substitutions: [SubstitutionPair] = []
        
        for part in substParts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let arrowParts = trimmed.components(separatedBy: "=>")
            
            guard arrowParts.count == 2 else {
                throw OT2AATError.invalidRule(
                    "Line \(lineNumber): Expected 'target => replacement' in substitution"
                )
            }
            
            let targetStr = arrowParts[0].trimmingCharacters(in: .whitespaces)
            let replStr = arrowParts[1].trimmingCharacters(in: .whitespaces)
            
            // Check for wildcard patterns
            if targetStr == "*" || replStr == "*" || targetStr.contains("*") || replStr.contains("*") {
                // Keep wildcards as-is (ftxenhancer will expand)
                let target: RuleElement = targetStr.hasPrefix("@") ? 
                    .classRef(String(targetStr.dropFirst())) : .glyph(targetStr)
                let repl: RuleElement = replStr.hasPrefix("@") ?
                    .classRef(String(replStr.dropFirst())) : .glyph(replStr)
                
                substitutions.append(SubstitutionPair(target: target, replacement: repl))
            } else {
                // Regular substitution
                let targetElements = try parseRuleElements(targetStr, lineNumber: lineNumber)
                let replElements = try parseRuleElements(replStr, lineNumber: lineNumber)
                
                guard targetElements.count == 1 && replElements.count == 1 else {
                    throw OT2AATError.invalidRule(
                        "Line \(lineNumber): Each substitution must have single target and replacement"
                    )
                }
                
                substitutions.append(SubstitutionPair(
                    target: targetElements[0],
                    replacement: replElements[0]
                ))
            }
        }
        
        return substitutions
    }
    
    /// Parse single contextual rule from CLI (no classes, explicit glyphs only)
    static func parseContextualRuleFromString(_ ruleString: String) throws -> ContextualRule {
        // Split by ':'
        let parts = ruleString.components(separatedBy: ":")
        guard parts.count == 2 else {
            throw OT2AATError.invalidRule(
                "Expected format: 'context: target => replacement'"
            )
        }
        
        let contextStr = parts[0].trimmingCharacters(in: .whitespaces)
        let substStr = parts[1].trimmingCharacters(in: .whitespaces)
        
        // Parse context (no classes allowed)
        let context = try parseContext(contextStr, lineNumber: 1)
        
        // Verify no class references
        let allText = ruleString
        if allText.contains("@") {
            throw OT2AATError.invalidRule(
                "Class references not supported in single-rule mode. Use -i/--input with a rules file."
            )
        }
        
        // Parse substitution
        let substitutions = try parseSubstitutions(substStr, lineNumber: 1)
        
        return ContextualRule(context: context, substitutions: substitutions, lineNumber: 1)
    }
}

// MARK: - Mark Positioning Parser

extension RuleParser {
    
    /// Parse mark positioning rules from file
    /// Returns all four types: markclasses, distances, bases, basemarks, ligatures
    static func parseMarkPositioningRules(from path: String) throws -> MarkPositioningRules {
        guard FileManager.default.fileExists(atPath: path) else {
            throw OT2AATError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var registry = GlyphClassRegistry()
        var markClasses: [MarkClass] = []
        var bases: [BaseGlyph] = []
        var baseMarks: [BaseMarkGlyph] = []
        var ligatures: [LigatureGlyph] = []
        var distanceRules: [DistanceRule] = []
        var distanceMatrices: [DistanceMatrix] = []
        
        var lineIndex = 0
        while lineIndex < lines.count {
            let lineNum = lineIndex + 1
            let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") {
                lineIndex += 1
                continue
            }
            
            // Remove end-of-line comments
            let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            // Parse based on keyword
            if withoutComment.hasPrefix("@class ") {
                // Regular glyph class definition
                let glyphClass = try parseClassDefinition(withoutComment, lineNumber: lineNum)
                try registry.register(glyphClass)
                lineIndex += 1
                
            } else if withoutComment.hasPrefix("@markclass ") {
                // Mark class definition (may span multiple lines)
                let (markClass, linesConsumed) = try parseMarkClass(lines, startIndex: lineIndex)
                
                // Check for duplicate mark class names
                if markClasses.contains(where: { $0.name == markClass.name }) {
                    throw OT2AATError.invalidRule(
                        "Line \(lineNum): Duplicate mark class '@\(markClass.name)'"
                    )
                }
                
                markClasses.append(markClass)
                lineIndex += linesConsumed
                
            } else if withoutComment.hasPrefix("@distance ") {
                // Distance rule (single line)
                let rule = try parseDistanceRule(withoutComment, lineNumber: lineNum, registry: registry)
                distanceRules.append(rule)
                lineIndex += 1
                
            } else if withoutComment.hasPrefix("@matrix") {
                // Distance matrix (multi-line)
                let (matrix, linesConsumed) = try parseDistanceMatrix(lines, startIndex: lineIndex, registry: registry)
                distanceMatrices.append(matrix)
                lineIndex += linesConsumed
                
            } else if withoutComment.hasPrefix("@base ") {
                // Base definition (multi-line)
                let (newBases, linesConsumed) = try parseBaseDefinition(lines, startIndex: lineIndex, registry: registry)
                bases.append(contentsOf: newBases)
                lineIndex += linesConsumed
                
            } else if withoutComment.hasPrefix("@mark2mark ") {
                // Mark-to-mark definition (multi-line)
                let (newBaseMarks, linesConsumed) = try parseMark2MarkDefinition(lines, startIndex: lineIndex, registry: registry)
                baseMarks.append(contentsOf: newBaseMarks)
                lineIndex += linesConsumed
                
            } else if withoutComment.hasPrefix("@ligature ") {
                // Ligature definition (multi-line)
                let (ligature, linesConsumed) = try parseLigatureDefinition(lines, startIndex: lineIndex)
                ligatures.append(ligature)
                lineIndex += linesConsumed
                
            } else {
                throw OT2AATError.invalidRule(
                    "Line \(lineNum): Unrecognized syntax: '\(withoutComment)'"
                )
            }
        }
        
        let rules = MarkPositioningRules(
            markClasses: markClasses,
            bases: bases,
            baseMarks: baseMarks,
            ligatures: ligatures,
            distanceRules: distanceRules,
            distanceMatrices: distanceMatrices
        )
        
        // Validate all rules
        try rules.validate(using: registry)
        
        return rules
    }
    
    // MARK: - Mark Class Parser
    
    /// Parse @markclass definition
    /// Format: @markclass NAME <x, y>
    ///             glyph1 glyph2 glyph3
    private static func parseMarkClass(_ lines: [String], startIndex: Int) throws -> (MarkClass, Int) {
        let lineNum = startIndex + 1
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        
        // Remove @markclass prefix
        let withoutPrefix = firstLine.dropFirst(11).trimmingCharacters(in: .whitespaces)
        
        // Split into name and anchor
        // Format: NAME <x, y> [glyph1 glyph2 ...]
        let parts = withoutPrefix.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        guard parts.count >= 2 else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNum): Invalid @markclass syntax
                Expected: @markclass NAME <x, y> glyph1 glyph2 ...
                Got: \(firstLine)
                """
            )
        }
        
        let name = parts[0]
        
        // Find anchor (must have < and >)
        var anchorStr = ""
        var glyphStartIndex = 1
        
        // Anchor might be split across multiple parts like "< 100 , 150 >"
        var foundStart = false
        var foundEnd = false
        for i in 1..<parts.count {
            if parts[i].contains("<") {
                foundStart = true
                anchorStr = parts[i]
                glyphStartIndex = i + 1
            } else if foundStart && !foundEnd {
                anchorStr += " " + parts[i]
            }
            
            if parts[i].contains(">") {
                foundEnd = true
                break
            }
        }
        
        guard foundStart && foundEnd else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNum): Missing anchor point in @markclass
                Expected: @markclass \(name) <x, y> ...
                """
            )
        }
        
        let anchor = try AnchorPoint.parse(anchorStr)
        
        // Collect glyphs (may span multiple lines)
        var glyphs: [String] = []
        
        // Glyphs on first line
        if glyphStartIndex < parts.count {
            glyphs.append(contentsOf: parts[glyphStartIndex...])
        }
        
        // Check subsequent lines for continuation
        var linesConsumed = 1
        var currentLine = startIndex + 1
        
        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Stop at empty line or next keyword
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("@") {
                break
            }
            
            // Add glyphs from this line
            let lineGlyphs = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            glyphs.append(contentsOf: lineGlyphs)
            
            linesConsumed += 1
            currentLine += 1
        }
        
        guard !glyphs.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): Mark class '@\(name)' has no glyphs"
            )
        }
        
        let markClass = MarkClass(name: name, marks: glyphs, anchor: anchor, lineNumber: lineNum)
        return (markClass, linesConsumed)
    }
    
    // MARK: - Distance Rule Parser
    
    /// Parse @distance rule
    /// Format: @distance context target value [direction]
    private static func parseDistanceRule(_ line: String, lineNumber: Int, registry: GlyphClassRegistry) throws -> DistanceRule {
        // Remove @distance prefix
        let withoutPrefix = line.dropFirst(10).trimmingCharacters(in: .whitespaces)
        let parts = withoutPrefix.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        guard parts.count >= 3 else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Invalid @distance syntax
                Expected: @distance context target value [direction]
                Got: \(line)
                """
            )
        }
        
        let contextStr = parts[0]
        let targetStr = parts[1]
        let valueStr = parts[2]
        
        // Parse context and target (glyph or class)
        let context = try parseRuleElement(contextStr, lineNumber: lineNumber)
        let target = try parseRuleElement(targetStr, lineNumber: lineNumber)
        
        // Parse value
        guard let value = Int(valueStr) else {
            throw OT2AATError.invalidRule(
                "Line \(lineNumber): Invalid adjustment value '\(valueStr)'. Must be an integer"
            )
        }
        
        // Parse optional direction
        var direction = DistanceRule.Direction.horizontal  // Default
        if parts.count >= 4 {
            let dirStr = parts[3].lowercased()
            if let dir = DistanceRule.Direction(rawValue: dirStr) {
                direction = dir
            } else {
                throw OT2AATError.invalidRule(
                    """
                    Line \(lineNumber): Invalid direction '\(parts[3])'
                    Valid directions: horizontal, vertical, both
                    """
                )
            }
        }
        
        return DistanceRule(
            context: context,
            target: target,
            adjustment: value,
            direction: direction,
            lineNumber: lineNumber
        )
    }
    
    // MARK: - Distance Matrix Parser
    
    /// Parse @matrix definition
    /// Format:
    /// @matrix
    ///     left @CLASS1 @CLASS2
    ///     right @CLASS3 @CLASS4
    ///     @CLASS3 @CLASS1 => value
    private static func parseDistanceMatrix(_ lines: [String], startIndex: Int, registry: GlyphClassRegistry) throws -> (DistanceMatrix, Int) {
        let lineNum = startIndex + 1
        
        var leftClasses: [String] = []
        var rightClasses: [String] = []
        var adjustments: [(String, String, Int)] = []
        
        var currentLine = startIndex + 1
        var linesConsumed = 1
        
        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") {
                currentLine += 1
                linesConsumed += 1
                continue
            }
            
            // Remove end-of-line comments
            let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            // Stop at next keyword
            if withoutComment.hasPrefix("@") && !withoutComment.contains("=>") {
                // Check if it's left/right or a new definition
                if withoutComment.hasPrefix("left ") {
                    // Parse left classes
                    let classesStr = withoutComment.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    let classes = classesStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    
                    for className in classes {
                        guard className.hasPrefix("@") else {
                            throw OT2AATError.invalidRule(
                                "Line \(currentLine + 1): Class name must start with @: '\(className)'"
                            )
                        }
                        leftClasses.append(String(className.dropFirst()))
                    }
                    
                } else if withoutComment.hasPrefix("right ") {
                    // Parse right classes
                    let classesStr = withoutComment.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    let classes = classesStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    
                    for className in classes {
                        guard className.hasPrefix("@") else {
                            throw OT2AATError.invalidRule(
                                "Line \(currentLine + 1): Class name must start with @: '\(className)'"
                            )
                        }
                        rightClasses.append(String(className.dropFirst()))
                    }
                    
                } else {
                    // End of matrix
                    break
                }
                
            } else if withoutComment.contains("=>") {
                // Parse adjustment: @CLASS1 @CLASS2 => value
                let parts = withoutComment.components(separatedBy: "=>")
                guard parts.count == 2 else {
                    throw OT2AATError.invalidRule(
                        """
                        Line \(currentLine + 1): Invalid adjustment syntax
                        Expected: @RIGHT_CLASS @LEFT_CLASS => value
                        Got: \(withoutComment)
                        """
                    )
                }
                
                let classNames = parts[0].trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                
                guard classNames.count == 2 else {
                    throw OT2AATError.invalidRule(
                        """
                        Line \(currentLine + 1): Expected two class names
                        Format: @RIGHT_CLASS @LEFT_CLASS => value
                        Got: \(parts[0])
                        """
                    )
                }
                
                guard classNames[0].hasPrefix("@") && classNames[1].hasPrefix("@") else {
                    throw OT2AATError.invalidRule(
                        "Line \(currentLine + 1): Class names must start with @"
                    )
                }
                
                let rightClass = String(classNames[0].dropFirst())
                let leftClass = String(classNames[1].dropFirst())
                
                let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
                guard let value = Int(valueStr) else {
                    throw OT2AATError.invalidRule(
                        "Line \(currentLine + 1): Invalid adjustment value '\(valueStr)'. Must be an integer"
                    )
                }
                
                adjustments.append((rightClass, leftClass, value))
                
            } else {
                // Unknown line in matrix
                throw OT2AATError.invalidRule(
                    "Line \(currentLine + 1): Unexpected content in @matrix block: '\(withoutComment)'"
                )
            }
            
            currentLine += 1
            linesConsumed += 1
        }
        
        guard !leftClasses.isEmpty && !rightClasses.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @matrix must have both 'left' and 'right' class definitions"
            )
        }
        
        let matrix = DistanceMatrix(
            leftClasses: leftClasses,
            rightClasses: rightClasses,
            adjustments: adjustments,
            lineNumber: lineNum
        )
        
        return (matrix, linesConsumed)
    }
    
    // MARK: - Base Definition Parser
    
    /// Parse @base definition
    /// Format:
    /// @base glyph
    ///     MARK_CLASS1 <x, y>
    ///     MARK_CLASS2 <x, y>
    /// OR
    /// @base @CLASS
    ///     MARK_CLASS1 <x, y>
    /// OR
    /// @base @CLASS
    ///     glyph1: MARK_CLASS1 <x, y>, MARK_CLASS2 <x, y>
    ///     glyph2: MARK_CLASS1 <x, y>, MARK_CLASS2 <x, y>
    private static func parseBaseDefinition(_ lines: [String], startIndex: Int, registry: GlyphClassRegistry) throws -> ([BaseGlyph], Int) {
        let lineNum = startIndex + 1
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        
        // Remove @base prefix
        let glyphOrClass = firstLine.dropFirst(6).trimmingCharacters(in: .whitespaces)
        
        guard !glyphOrClass.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @base requires glyph name or @CLASS"
            )
        }
        
        let isClass = glyphOrClass.hasPrefix("@")
        
        // Parse attachment lines
        var currentLine = startIndex + 1
        var linesConsumed = 1
        var attachmentLines: [String] = []
        
        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") {
                currentLine += 1
                linesConsumed += 1
                continue
            }
            
            // Remove end-of-line comments
            let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            // Stop at next keyword
            if withoutComment.hasPrefix("@") {
                break
            }
            
            attachmentLines.append(withoutComment)
            currentLine += 1
            linesConsumed += 1
        }
        
        guard !attachmentLines.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @base '\(glyphOrClass)' has no attachment points"
            )
        }
        
        var bases: [BaseGlyph] = []
        
        if isClass {
            // Class-based definition
            let className = String(glyphOrClass.dropFirst())
            guard let glyphClass = registry.lookup(className) else {
                throw OT2AATError.invalidRule(
                    """
                    Line \(lineNum): Undefined class '@\(className)'
                    Define class with: @class \(className) = ...
                    """
                )
            }
            
            // Check format: uniform or per-glyph
            let firstAttachmentLine = attachmentLines[0]
            if firstAttachmentLine.contains(":") {
                // Per-glyph format
                for attachmentLine in attachmentLines {
                    let parts = attachmentLine.components(separatedBy: ":")
                    guard parts.count == 2 else {
                        throw OT2AATError.invalidRule(
                            "Line \(lineNum): Invalid per-glyph syntax. Expected: glyph: MARK_CLASS <x, y>, ..."
                        )
                    }
                    
                    let glyphName = parts[0].trimmingCharacters(in: .whitespaces)
                    guard glyphClass.glyphs.contains(glyphName) else {
                        throw OT2AATError.invalidRule(
                            "Line \(lineNum): Glyph '\(glyphName)' not in class '@\(className)'"
                        )
                    }
                    
                    let attachments = try parseAttachments(parts[1], lineNumber: lineNum)
                    bases.append(BaseGlyph(glyph: glyphName, attachments: attachments, lineNumber: lineNum))
                }
                
            } else {
                // Uniform format - same attachments for all glyphs
                var attachments: [String: AnchorPoint] = [:]
                for attachmentLine in attachmentLines {
                    let (markClass, anchor) = try parseAttachment(attachmentLine, lineNumber: lineNum)
                    attachments[markClass] = anchor
                }
                
                for glyph in glyphClass.glyphs {
                    bases.append(BaseGlyph(glyph: glyph, attachments: attachments, lineNumber: lineNum))
                }
            }
            
        } else {
            // Individual glyph
            var attachments: [String: AnchorPoint] = [:]
            for attachmentLine in attachmentLines {
                let (markClass, anchor) = try parseAttachment(attachmentLine, lineNumber: lineNum)
                attachments[markClass] = anchor
            }
            
            bases.append(BaseGlyph(glyph: glyphOrClass, attachments: attachments, lineNumber: lineNum))
        }
        
        return (bases, linesConsumed)
    }
    
    // MARK: - Mark2Mark Parser
    
    /// Parse @mark2mark definition
    /// Same format as @base
    private static func parseMark2MarkDefinition(_ lines: [String], startIndex: Int, registry: GlyphClassRegistry) throws -> ([BaseMarkGlyph], Int) {
        let lineNum = startIndex + 1
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        
        // Remove @mark2mark prefix
        let glyphOrClass = firstLine.dropFirst(11).trimmingCharacters(in: .whitespaces)
        
        guard !glyphOrClass.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @mark2mark requires glyph name or @CLASS"
            )
        }
        
        let isClass = glyphOrClass.hasPrefix("@")
        
        // Parse attachment lines (same as @base)
        var currentLine = startIndex + 1
        var linesConsumed = 1
        var attachmentLines: [String] = []
        
        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty || line.hasPrefix("#") {
                currentLine += 1
                linesConsumed += 1
                continue
            }
            
            let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            if withoutComment.hasPrefix("@") {
                break
            }
            
            attachmentLines.append(withoutComment)
            currentLine += 1
            linesConsumed += 1
        }
        
        guard !attachmentLines.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @mark2mark '\(glyphOrClass)' has no attachment points"
            )
        }
        
        var baseMarks: [BaseMarkGlyph] = []
        
        if isClass {
            let className = String(glyphOrClass.dropFirst())
            guard let glyphClass = registry.lookup(className) else {
                throw OT2AATError.invalidRule(
                    """
                    Line \(lineNum): Undefined class '@\(className)'
                    Define class with: @class \(className) = ...
                    """
                )
            }
            
            // Check format
            let firstAttachmentLine = attachmentLines[0]
            if firstAttachmentLine.contains(":") {
                // Per-glyph format
                for attachmentLine in attachmentLines {
                    let parts = attachmentLine.components(separatedBy: ":")
                    guard parts.count == 2 else {
                        throw OT2AATError.invalidRule(
                            "Line \(lineNum): Invalid per-glyph syntax"
                        )
                    }
                    
                    let glyphName = parts[0].trimmingCharacters(in: .whitespaces)
                    guard glyphClass.glyphs.contains(glyphName) else {
                        throw OT2AATError.invalidRule(
                            "Line \(lineNum): Glyph '\(glyphName)' not in class '@\(className)'"
                        )
                    }
                    
                    let attachments = try parseAttachments(parts[1], lineNumber: lineNum)
                    baseMarks.append(BaseMarkGlyph(mark: glyphName, attachments: attachments, lineNumber: lineNum))
                }
                
            } else {
                // Uniform format
                var attachments: [String: AnchorPoint] = [:]
                for attachmentLine in attachmentLines {
                    let (markClass, anchor) = try parseAttachment(attachmentLine, lineNumber: lineNum)
                    attachments[markClass] = anchor
                }
                
                for glyph in glyphClass.glyphs {
                    baseMarks.append(BaseMarkGlyph(mark: glyph, attachments: attachments, lineNumber: lineNum))
                }
            }
            
        } else {
            // Individual mark glyph
            var attachments: [String: AnchorPoint] = [:]
            for attachmentLine in attachmentLines {
                let (markClass, anchor) = try parseAttachment(attachmentLine, lineNumber: lineNum)
                attachments[markClass] = anchor
            }
            
            baseMarks.append(BaseMarkGlyph(mark: glyphOrClass, attachments: attachments, lineNumber: lineNum))
        }
        
        return (baseMarks, linesConsumed)
    }
    
    // MARK: - Ligature Parser
    
    /// Parse @ligature definition
    /// Format:
    /// @ligature glyph
    ///     MARK_CLASS1 <x1, y1> <x2, y2> <x3, y3>
    ///     MARK_CLASS2 <x1, y1> <x2, y2> <x3, y3>
    private static func parseLigatureDefinition(_ lines: [String], startIndex: Int) throws -> (LigatureGlyph, Int) {
        let lineNum = startIndex + 1
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        
        // Remove @ligature prefix
        let ligatureName = firstLine.dropFirst(10).trimmingCharacters(in: .whitespaces)
        
        guard !ligatureName.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @ligature requires glyph name"
            )
        }
        
        // Parse component anchor lines
        var currentLine = startIndex + 1
        var linesConsumed = 1
        var componentAnchorLines: [String] = []
        
        while currentLine < lines.count {
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty || line.hasPrefix("#") {
                currentLine += 1
                linesConsumed += 1
                continue
            }
            
            let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            
            if withoutComment.hasPrefix("@") {
                break
            }
            
            componentAnchorLines.append(withoutComment)
            currentLine += 1
            linesConsumed += 1
        }
        
        guard !componentAnchorLines.isEmpty else {
            throw OT2AATError.invalidRule(
                "Line \(lineNum): @ligature '\(ligatureName)' has no component anchors"
            )
        }
        
        // Parse each line: MARK_CLASS <x1, y1> <x2, y2> ...
        var componentAnchors: [String: [AnchorPoint]] = [:]
        
        for anchorLine in componentAnchorLines {
            let parts = anchorLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            guard parts.count >= 2 else {
                throw OT2AATError.invalidRule(
                    """
                    Line \(lineNum): Invalid ligature component syntax
                    Expected: MARK_CLASS <x1, y1> <x2, y2> ...
                    Got: \(anchorLine)
                    """
                )
            }
            
            let markClassName = parts[0]
            
            // Parse anchor points (rest of the parts)
            var anchors: [AnchorPoint] = []
            var i = 1
            var currentAnchor = ""
            
            while i < parts.count {
                currentAnchor += parts[i]
                
                if parts[i].contains(">") {
                    // Complete anchor
                    let anchor = try AnchorPoint.parse(currentAnchor)
                    anchors.append(anchor)
                    currentAnchor = ""
                } else {
                    currentAnchor += " "
                }
                
                i += 1
            }
            
            guard !anchors.isEmpty else {
                throw OT2AATError.invalidRule(
                    "Line \(lineNum): No valid anchor points for mark class '\(markClassName)'"
                )
            }
            
            componentAnchors[markClassName] = anchors
        }
        
        let ligature = LigatureGlyph(
            ligature: ligatureName,
            componentAnchors: componentAnchors,
            lineNumber: lineNum
        )
        
        return (ligature, linesConsumed)
    }
    
    // MARK: - Helper Parsers
    
    /// Parse single attachment: MARK_CLASS <x, y>
    private static func parseAttachment(_ line: String, lineNumber: Int) throws -> (String, AnchorPoint) {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        guard parts.count >= 2 else {
            throw OT2AATError.invalidRule(
                """
                Line \(lineNumber): Invalid attachment syntax
                Expected: MARK_CLASS <x, y>
                Got: \(line)
                """
            )
        }
        
        let markClass = parts[0]
        
        // Reconstruct anchor (may be split across parts)
        var anchorStr = ""
        for i in 1..<parts.count {
            anchorStr += parts[i]
            if parts[i].contains(">") {
                break
            }
            anchorStr += " "
        }
        
        let anchor = try AnchorPoint.parse(anchorStr)
        return (markClass, anchor)
    }
    
    /// Parse multiple attachments: MARK_CLASS1 <x, y>, MARK_CLASS2 <x, y>
    private static func parseAttachments(_ line: String, lineNumber: Int) throws -> [String: AnchorPoint] {
        var attachments: [String: AnchorPoint] = [:]
        
        // Split by comma
        let parts = line.components(separatedBy: ",")
        
        for part in parts {
            let (markClass, anchor) = try parseAttachment(part.trimmingCharacters(in: .whitespaces), lineNumber: lineNumber)
            attachments[markClass] = anchor
        }
        
        return attachments
    }
    
    /// Parse rule element (glyph or @class)
    private static func parseRuleElement(_ string: String, lineNumber: Int) throws -> RuleElement {
        if string.hasPrefix("@") {
            let className = String(string.dropFirst())
            return .classRef(className)
        } else {
            return .glyph(string)
        }
    }
}
