import Foundation

/// Represents a single reordering rule element (explicit glyph or class reference)
enum RuleElement {
	case glyph(String)
	case classRef(String)
	
	var description: String {
		switch self {
		case .glyph(let name):
			return name
		case .classRef(let name):
			return "@\(name)"
		}
	}
}

/// Represents a reordering rule before expansion
struct ReorderRule {
	let before: [RuleElement]
	let after: [RuleElement]
	let lineNumber: Int
	
/// Expand rule using class registry
	/// Returns array of expanded rules (explicit glyphs only)
	func expand(using registry: GlyphClassRegistry) throws -> [ExpandedReorderRule] {
		// Resolve all elements to glyph lists
		let beforeGlyphLists = try before.map { try resolveElement($0, using: registry) }
		let afterGlyphLists = try after.map { try resolveElement($0, using: registry) }
		
		// Verify both sides have same structure (same number of classes with same sizes)
		guard beforeGlyphLists.count == afterGlyphLists.count else {
			throw OT2AATError.invalidRule(
				"""
				Line \(lineNumber): Element count mismatch
				Left has \(beforeGlyphLists.count) elements, right has \(afterGlyphLists.count)
				"""
			)
		}
		
		// Each position must have the same number of glyphs for proper pairing
		for (index, (beforeList, afterList)) in zip(beforeGlyphLists, afterGlyphLists).enumerated() {
			guard beforeList.count == afterList.count else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Class size mismatch at position \(index + 1)
					Left element has \(beforeList.count) glyph(s)
					Right element has \(afterList.count) glyph(s)
					
					Both sides must use classes of same size or explicit glyphs.
					Example: @vowels @consonants => @consonants @vowels
							 (both classes must have same number of glyphs)
					"""
				)
			}
		}
		
		// Calculate total combinations
		let combinationCount = beforeGlyphLists[0].count
		
		// Check expansion limit
		guard combinationCount <= 100 else {
			throw OT2AATError.invalidRule(
				"""
				Line \(lineNumber): Class expansion exceeds limit
				This rule expands to \(combinationCount) combinations (limit: 100)
				
				Help: Split into smaller classes or write explicit rules
				"""
			)
		}
		
		// Generate matched combinations
		// For each index in the first class, use same index across all positions
		var expandedRules: [ExpandedReorderRule] = []
		
		for i in 0..<combinationCount {
			let beforeGlyphs = beforeGlyphLists.map { $0[i] }
			let afterGlyphs = afterGlyphLists.map { $0[i] }
			
			let expandedRule = try ExpandedReorderRule(
				before: beforeGlyphs,
				after: afterGlyphs,
				lineNumber: lineNumber
			)
			expandedRules.append(expandedRule)
		}
		
		return expandedRules
	}
	
	private func resolveElement(_ element: RuleElement, using registry: GlyphClassRegistry) throws -> [String] {
		switch element {
		case .glyph(let name):
			return [name]
		case .classRef(let name):
			guard let glyphClass = registry.lookup(name) else {
				throw OT2AATError.invalidRule("Undefined class '@\(name)' (line \(lineNumber))")
			}
			return glyphClass.glyphs
		}
	}
	
	/// Cartesian product of arrays
	private func cartesianProduct(_ arrays: [[String]]) -> [[String]] {
		guard !arrays.isEmpty else { return [[]] }
		
		var result: [[String]] = [[]]
		
		for array in arrays {
			var newResult: [[String]] = []
			for existing in result {
				for element in array {
					newResult.append(existing + [element])
				}
			}
			result = newResult
		}
		
		return result
	}
}

/// Represents a reordering rule after expansion (all explicit glyphs)
struct ExpandedReorderRule {
	let before: [String]
	let after: [String]
	let pattern: ReorderPattern
	let lineNumber: Int
	
	init(before: [String], after: [String], lineNumber: Int) throws {
		self.before = before
		self.after = after
		self.lineNumber = lineNumber
		
		// Detect and validate pattern
		do {
			self.pattern = try ReorderPattern.detect(before: before, after: after)
		} catch {
			// Add line number to pattern detection errors
			throw OT2AATError.invalidRule(
				"""
				Line \(lineNumber): \(error.localizedDescription)
				Pattern: \(before.joined(separator: " ")) => \(after.joined(separator: " "))
				"""
			)
		}
	}
}
