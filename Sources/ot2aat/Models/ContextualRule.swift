import Foundation

/// Contextual substitution rule before expansion
struct ContextualRule {
	let context: ContextType
	let substitutions: [SubstitutionPair]
	let lineNumber: Int
	
	/// Expand rule using class registry
	func expand(using registry: GlyphClassRegistry) throws -> [ExpandedContextualRule] {
		switch context {
		case .after(let pattern):
			return try expandAfter(pattern: pattern, using: registry)
		case .before(let pattern):
			return try expandBefore(pattern: pattern, using: registry)
		case .between(let first, let second):
			return try expandBetween(first: first, second: second, using: registry)
		case .when(let pattern):
			return try expandWhen(pattern: pattern, using: registry)
		}
	}
	
	// MARK: - After Context
	
    private func expandAfter(pattern: [RuleElement], using registry: GlyphClassRegistry) throws -> [ExpandedContextualRule] {
        let contextGlyphs = try resolveElements(pattern, using: registry)
        let targetGlyphs = try resolveElements([substitutions[0].target], using: registry)
        let replacementGlyphs = try resolveElements([substitutions[0].replacement], using: registry)
        
        guard targetGlyphs[0].count == replacementGlyphs[0].count else {
            throw OT2AATError.invalidRule(
                "Line \(lineNumber): Target and replacement class sizes must match (\(targetGlyphs[0].count) vs \(replacementGlyphs[0].count))"
            )
        }
        
        var rules: [ExpandedContextualRule] = []
        
        // Generate cartesian product of all context positions
        let contextCombinations = cartesianProduct(contextGlyphs)
        
        // For each context combination, create rules for all target/replacement pairs
        for contextPattern in contextCombinations {
            for targetIdx in 0..<targetGlyphs[0].count {
                rules.append(ExpandedContextualRule(
                    context: .after(contextPattern),
                    substitutions: [(target: targetGlyphs[0][targetIdx], replacement: replacementGlyphs[0][targetIdx])],
                    lineNumber: lineNumber,
                    ruleGroupID: nil
                ))
            }
        }
        
        return rules
    }
	
	// MARK: - Before Context
	
    private func expandBefore(pattern: [RuleElement], using registry: GlyphClassRegistry) throws -> [ExpandedContextualRule] {
        let contextGlyphs = try resolveElements(pattern, using: registry)
        let targetGlyphs = try resolveElements([substitutions[0].target], using: registry)
        let replacementGlyphs = try resolveElements([substitutions[0].replacement], using: registry)
        
        guard targetGlyphs[0].count == replacementGlyphs[0].count else {
            throw OT2AATError.invalidRule(
                "Line \(lineNumber): Target and replacement class sizes must match"
            )
        }
        
        var rules: [ExpandedContextualRule] = []
        
        let contextCombinations = cartesianProduct(contextGlyphs)
        
        for contextPattern in contextCombinations {
            for targetIdx in 0..<targetGlyphs[0].count {
                rules.append(ExpandedContextualRule(
                    context: .before(contextPattern),
                    substitutions: [(target: targetGlyphs[0][targetIdx], replacement: replacementGlyphs[0][targetIdx])],
                    lineNumber: lineNumber,
                    ruleGroupID: nil
                ))
            }
        }
        
        return rules
    }
	
	// MARK: - Between Context
	
    private func expandBetween(first: [RuleElement], second: [RuleElement], using registry: GlyphClassRegistry) throws -> [ExpandedContextualRule] {
        let firstGlyphs = try resolveElements(first, using: registry)
        let secondGlyphs = try resolveElements(second, using: registry)
        let targetGlyphs = try resolveElements([substitutions[0].target], using: registry)
        let replacementGlyphs = try resolveElements([substitutions[0].replacement], using: registry)
        
        guard targetGlyphs[0].count == replacementGlyphs[0].count else {
            throw OT2AATError.invalidRule(
                "Line \(lineNumber): Target and replacement class sizes must match"
            )
        }
        
        var rules: [ExpandedContextualRule] = []
        
        let firstCombinations = cartesianProduct(firstGlyphs)
        let secondCombinations = cartesianProduct(secondGlyphs)
        
        for firstPattern in firstCombinations {
            for secondPattern in secondCombinations {
                for targetIdx in 0..<targetGlyphs[0].count {
                    rules.append(ExpandedContextualRule(
                        context: .between(
                            first: firstPattern,
                            second: secondPattern
                        ),
                        substitutions: [(target: targetGlyphs[0][targetIdx], replacement: replacementGlyphs[0][targetIdx])],
                        lineNumber: lineNumber,
                        ruleGroupID: nil
                    ))
                }
            }
        }
        
        return rules
    }
	
	// MARK: - When Context (with decomposition)
	
	private func expandWhen(pattern: [RuleElement], using registry: GlyphClassRegistry) throws -> [ExpandedContextualRule] {
		let patternGlyphs = try resolveElements(pattern, using: registry)
		
		// Verify all classes have same size
		let firstSize = patternGlyphs[0].count
		for (idx, list) in patternGlyphs.enumerated() {
			guard list.count == firstSize else {
				throw OT2AATError.invalidRule(
					"Line \(lineNumber): All classes in 'when' pattern must have same size (position \(idx): \(list.count) vs \(firstSize))"
				)
			}
		}
		
		// Expand substitutions
		var expandedSubs: [[(String, String)]] = []
		for sub in substitutions {
			let targets = try resolveElements([sub.target], using: registry)[0]
			let replacements = try resolveElements([sub.replacement], using: registry)[0]
			
			guard targets.count == replacements.count else {
				throw OT2AATError.invalidRule(
					"Line \(lineNumber): Substitution target/replacement size mismatch"
				)
			}
			
			guard targets.count == firstSize else {
				throw OT2AATError.invalidRule(
					"Line \(lineNumber): Substitution classes must match pattern size (\(targets.count) vs \(firstSize))"
				)
			}
			
			expandedSubs.append(zip(targets, replacements).map { ($0, $1) })
		}
		
		// DECISION POINT: Decompose or multi-pass?
		if substitutions.count == 1 {
			// Single substitution - decompose into simpler contexts for full verification!
			return try decomposeSingleSubstitution(
				patternGlyphs: patternGlyphs,
				expandedSubs: expandedSubs
			)
		} else {
			// Multiple substitutions - use multi-pass
			return try expandMultiSubstitutionWhen(
				patternGlyphs: patternGlyphs,
				expandedSubs: expandedSubs
			)
		}
	}
	
	// MARK: - Decomposition for Single Substitution
	
// MARK: - Decomposition for Single Substitution
	
	private func decomposeSingleSubstitution(
		patternGlyphs: [[String]],
		expandedSubs: [[(String, String)]]
	) throws -> [ExpandedContextualRule] {
		
		let firstSize = patternGlyphs[0].count
		var allRules: [ExpandedContextualRule] = []
		
		// Generate unique group ID for this decomposed rule set
		let groupID = "decomposed_\(lineNumber)"
		
		// Find which position in pattern contains the target
		let targets = Set(expandedSubs[0].map { $0.0 })
		var targetPosition: Int = -1
		
		for (idx, positionGlyphs) in patternGlyphs.enumerated() {
			if Set(positionGlyphs).intersection(targets).count > 0 {
				targetPosition = idx
				break
			}
		}
		
		guard targetPosition >= 0 else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Substitution target not found in 'when' pattern"
			)
		}
		
		// Decompose for each combination
		for i in 0..<firstSize {
			let contextPattern = patternGlyphs.map { $0[i] }
			let (target, replacement) = expandedSubs[0][i]
			
			let tempGlyph = "\(65000 + (lineNumber * 100) + i)"
			
			if targetPosition == 0 {
				// Target at start: use before context
				let afterContext = Array(contextPattern[1...])
				allRules.append(ExpandedContextualRule(
					context: .before(afterContext),
					substitutions: [(target, replacement)],
					lineNumber: lineNumber,
					ruleGroupID: groupID
				))
				
			} else if targetPosition == patternGlyphs.count - 1 {
				// Target at end: use after context
				let beforeContext = Array(contextPattern[0..<targetPosition])
				allRules.append(ExpandedContextualRule(
					context: .after(beforeContext),
					substitutions: [(target, replacement)],
					lineNumber: lineNumber,
					ruleGroupID: groupID
				))
				
			} else {
				// Target in middle: two-step process
				let beforeContext = Array(contextPattern[0..<targetPosition])
				let afterContext = Array(contextPattern[(targetPosition + 1)...])
				
				// Step 1: Mark with temp after seeing before-context
				allRules.append(ExpandedContextualRule(
					context: .after(beforeContext),
					substitutions: [(target, tempGlyph)],
					lineNumber: lineNumber,
					ruleGroupID: groupID
				))
				
				// Step 2: Replace temp before seeing after-context
				// FIX: Use "before" context, NOT "between"
				allRules.append(ExpandedContextualRule(
					context: .before(afterContext),
					substitutions: [(tempGlyph, replacement)],
					lineNumber: lineNumber,
					ruleGroupID: groupID
				))
				
				// Step 3: Cleanup temp if pattern incomplete
				allRules.append(ExpandedContextualRule(
					context: .cleanup(tempGlyph),
					substitutions: [(tempGlyph, target)],
					lineNumber: lineNumber,
					ruleGroupID: groupID
				))
			}
		}
		
		return allRules
	}
	
	// MARK: - Multi-substitution (existing logic)
	
	private func expandMultiSubstitutionWhen(
		patternGlyphs: [[String]],
		expandedSubs: [[(String, String)]]
	) throws -> [ExpandedContextualRule] {
		
		let firstSize = patternGlyphs[0].count
		var rules: [ExpandedContextualRule] = []
		
		for i in 0..<firstSize {
			let contextPattern = patternGlyphs.map { $0[i] }
			let subs = expandedSubs.map { $0[i] }
			
			rules.append(ExpandedContextualRule(
				context: .when(contextPattern),
				substitutions: subs,
				lineNumber: lineNumber,
				ruleGroupID: nil
			))
		}
		
		return rules
	}
	
	// MARK: - Helper
	
	private func resolveElements(_ elements: [RuleElement], using registry: GlyphClassRegistry) throws -> [[String]] {
		return try elements.map { element in
			switch element {
			case .glyph(let name):
				return [name]
			case .classRef(let name):
				guard let glyphClass = registry.lookup(name) else {
					throw OT2AATError.invalidRule("Line \(lineNumber): Undefined class '@\(name)'")
				}
				return glyphClass.glyphs
			}
		}
	}
}

/// Expanded contextual rule (all explicit glyphs)
struct ExpandedContextualRule {
	enum ExpandedContext {
		case after([String])
		case before([String])
		case between(first: [String], second: [String])
		case when([String])
		case cleanup(String)
	}
	
	let context: ExpandedContext
	let substitutions: [(target: String, replacement: String)]
	let lineNumber: Int
	let ruleGroupID: String?  // NEW: tracks which original rule this came from
	
	var needsMultiPass: Bool {
		return substitutions.count > 1
	}
	
	var isCleanup: Bool {
		if case .cleanup = context {
			return true
		}
		return false
	}
}

// MARK: - Helper: Cartesian Product

/// Generate cartesian product of arrays
/// Input: [[a, b], [1, 2, 3]] → Output: [[a, 1], [a, 2], [a, 3], [b, 1], [b, 2], [b, 3]]
private func cartesianProduct(_ arrays: [[String]]) -> [[String]] {
    guard !arrays.isEmpty else { return [[]] }
    guard arrays.count > 1 else { return arrays[0].map { [$0] } }
    
    let first = arrays[0]
    let rest = Array(arrays.dropFirst())
    let restProduct = cartesianProduct(rest)
    
    var result: [[String]] = []
    for item in first {
        for combination in restProduct {
            result.append([item] + combination)
        }
    }
    
    return result
}
