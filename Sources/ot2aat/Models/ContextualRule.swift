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
		
		// Check sizes match
		guard targetGlyphs[0].count == replacementGlyphs[0].count else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Target and replacement class sizes must match (\(targetGlyphs[0].count) vs \(replacementGlyphs[0].count))"
			)
		}
		
		var rules: [ExpandedContextualRule] = []
		for i in 0..<targetGlyphs[0].count {
			rules.append(ExpandedContextualRule(
				context: .after(contextGlyphs.map { $0[i % $0.count] }),
				substitutions: [(target: targetGlyphs[0][i], replacement: replacementGlyphs[0][i])],
				lineNumber: lineNumber
			))
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
		for i in 0..<targetGlyphs[0].count {
			rules.append(ExpandedContextualRule(
				context: .before(contextGlyphs.map { $0[i % $0.count] }),
				substitutions: [(target: targetGlyphs[0][i], replacement: replacementGlyphs[0][i])],
				lineNumber: lineNumber
			))
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
		for i in 0..<targetGlyphs[0].count {
			rules.append(ExpandedContextualRule(
				context: .between(
					first: firstGlyphs.map { $0[i % $0.count] },
					second: secondGlyphs.map { $0[i % $0.count] }
				),
				substitutions: [(target: targetGlyphs[0][i], replacement: replacementGlyphs[0][i])],
				lineNumber: lineNumber
			))
		}
		return rules
	}
	
	// MARK: - When Context
	
	private func expandWhen(pattern: [RuleElement], using registry: GlyphClassRegistry) throws -> [ExpandedContextualRule] {
		let patternGlyphs = try resolveElements(pattern, using: registry)
		
		// For when context, all classes must have same size
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
		
		// Generate rules
		var rules: [ExpandedContextualRule] = []
		for i in 0..<firstSize {
			let contextPattern = patternGlyphs.map { $0[i] }
			let subs = expandedSubs.map { $0[i] }
			
			rules.append(ExpandedContextualRule(
				context: .when(contextPattern),
				substitutions: subs,
				lineNumber: lineNumber
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
	}
	
	let context: ExpandedContext
	let substitutions: [(target: String, replacement: String)]
	let lineNumber: Int
	
	var needsMultiPass: Bool {
		return substitutions.count > 1
	}
}
