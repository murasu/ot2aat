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
    static func parseClassDefinition(_ line: String, lineNumber: Int) throws -> GlyphClass {
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
    internal static func parseReorderRule(
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
    internal static func parseContextualRule(
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
