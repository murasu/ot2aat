import Foundation

/// AAT Rearrangement Patterns (15 verbs + no-op)
enum ReorderPattern: String {
	// No operation
	case noChange = "none"
	
	// 2-element patterns
	case Ax_xA = "Ax->xA"      // Move A to end: AB -> BA
	case xD_Dx = "xD->Dx"      // Move D to start: AB -> BA
	
	// 3-element patterns
	case AxD_DxA = "AxD->DxA"  // Swap A and D: ABC -> CBA
	
	// 4-element patterns
	case ABx_xAB = "ABx->xAB"  // Move AB to end: ABCD -> CDAB
	case ABx_xBA = "ABx->xBA"  // Move AB to end, reverse: ABCD -> CDBA
	case xCD_CDx = "xCD->CDx"  // Move CD to start: ABCD -> CDAB
	case xCD_DCx = "xCD->DCx"  // Move CD to start, reverse: ABCD -> DCAB
	
	case AxCD_CDxA = "AxCD->CDxA"    // Move CD before, A after: ABCD -> CDAB
	case AxCD_DCxA = "AxCD->DCxA"    // Move CD (reversed) before, A after: ABCD -> DCAB
	
	case ABxD_DxAB = "ABxD->DxAB"    // Move D before, AB after: ABCD -> DABC
	case ABxD_DxBA = "ABxD->DxBA"    // Move D before, AB (reversed) after: ABCD -> DBAC
	
	case ABxCD_CDxAB = "ABxCD->CDxAB"    // ABCD -> CDAB
	case ABxCD_CDxBA = "ABxCD->CDxBA"    // ABCD -> CDBA
	case ABxCD_DCxAB = "ABxCD->DCxAB"    // ABCD -> DCAB
	case ABxCD_DCxBA = "ABxCD->DCxBA"    // ABCD -> DCBA
	
	/// Detect pattern from before/after arrays
	static func detect(before: [String], after: [String]) throws -> ReorderPattern {
		guard before.count == after.count else {
			throw OT2AATError.invalidRule("Element count mismatch: before has \(before.count), after has \(after.count)")
		}
		
		let count = before.count
		
		// Check if pattern is supported (max 4 elements)
		guard count >= 2 && count <= 4 else {
			throw OT2AATError.invalidRule("Pattern must have 2-4 elements, got \(count)")
		}
		
		// Generate pattern string for comparison
		let pattern = makePatternString(before: before, after: after)
		
		switch count {
		case 2:
			return try detect2Element(pattern)
		case 3:
			return try detect3Element(pattern)
		case 4:
			return try detect4Element(pattern)
		default:
			throw OT2AATError.invalidRule("Unsupported pattern length: \(count)")
		}
	}
	
	private static func makePatternString(before: [String], after: [String]) -> String {
		// Create a mapping from before to after positions
		var mapping: [Int: Int] = [:]
		for (afterIdx, glyph) in after.enumerated() {
			if let beforeIdx = before.firstIndex(of: glyph) {
				mapping[beforeIdx] = afterIdx
			}
		}
		return mapping.sorted(by: { $0.key < $1.key }).map { String($0.value) }.joined()
	}
	
	private static func detect2Element(_ pattern: String) throws -> ReorderPattern {
		// AB -> BA: pattern = "10"
		switch pattern {
		case "10": return .Ax_xA
		case "01": 
			throw OT2AATError.invalidRule(
				"""
				Pattern represents no change (elements already in desired order)
				This is not a valid rearrangement pattern.
				"""
			)
		default:
			throw OT2AATError.invalidRule(
				"""
				Unsupported 2-element pattern: \(pattern)
				Only swap patterns are supported for 2 elements.
				Expected: AB => BA (pattern: 10)
				"""
			)
		}
	}
	
	private static func detect3Element(_ pattern: String) throws -> ReorderPattern {
		// ABC patterns
		switch pattern {
		case "120": return .Ax_xA      // ABC -> BCA
		case "201": return .xD_Dx      // ABC -> CAB
		case "210": return .AxD_DxA    // ABC -> CBA
		default:
			throw OT2AATError.invalidRule("Unsupported 3-element pattern")
		}
	}
	
	private static func detect4Element(_ pattern: String) throws -> ReorderPattern {
		// ABCD patterns
		switch pattern {
		case "2301": return .ABx_xAB      // ABCD -> CDAB
		case "3201": return .ABx_xBA      // ABCD -> CDBA
		case "0123": return .xCD_CDx      // ABCD -> ABCD (no change)
		case "0132": return .xCD_DCx      // ABCD -> ABDC
		case "2310": return .AxCD_CDxA    // ABCD -> CDAB (different interpretation)
		case "3210": return .AxCD_DCxA    // ABCD -> DCBA
		case "3012": return .ABxD_DxAB    // ABCD -> DABC
		case "3021": return .ABxD_DxBA    // ABCD -> DBAC
		// Note: Some AAT verbs map to same pattern strings
		// These are already covered by cases above:
		// ABxCD_CDxAB, ABxCD_CDxBA, ABxCD_DCxAB, ABxCD_DCxBA
		default:
			throw OT2AATError.invalidRule(
				"""
				Unsupported 4-element pattern
				Pattern code: \(pattern)
				
				This pattern doesn't map to any of the 15 AAT rearrangement verbs.
				Supported 4-element transformations include:
				  - ABCD -> CDAB (swap halves)
				  - ABCD -> DCBA (reverse all)
				  - ABCD -> DABC (move last to first)
				
				See documentation for complete list of supported patterns.
				"""
			)
		}
	}
	
	/// Debug: Show what the pattern represents
	static func debugPattern(before: [String], after: [String]) -> String {
		var output = "Before: \(before.joined(separator: " "))\n"
		output += "After:  \(after.joined(separator: " "))\n"
		
		for (i, glyph) in before.enumerated() {
			if let afterIndex = after.firstIndex(of: glyph) {
				output += "  \(glyph): position \(i) -> \(afterIndex)\n"
			}
		}
		
		return output
	}
}
