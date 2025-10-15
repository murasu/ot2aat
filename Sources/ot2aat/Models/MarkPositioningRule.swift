import Foundation

// MARK: - Anchor Point

/// Anchor point with x, y coordinates in font units
struct AnchorPoint: Equatable {
	let x: Int
	let y: Int
	
	init(x: Int, y: Int) {
		self.x = x
		self.y = y
	}
	
	/// Parse from string like "<100, 150>" or "< 100 , 150 >"
	static func parse(_ string: String) throws -> AnchorPoint {
		let trimmed = string.trimmingCharacters(in: .whitespaces)
		
		// Must start with < and end with >
		guard trimmed.hasPrefix("<") && trimmed.hasSuffix(">") else {
			throw OT2AATError.invalidRule("Invalid anchor syntax: '\(string)'. Expected format: <x, y>")
		}
		
		// Remove < and >
		let coords = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
		
		// Split by comma
		let parts = coords.components(separatedBy: ",")
		guard parts.count == 2 else {
			throw OT2AATError.invalidRule("Invalid anchor syntax: '\(string)'. Expected format: <x, y>")
		}
		
		// Parse integers
		guard let x = Int(parts[0].trimmingCharacters(in: .whitespaces)),
			  let y = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
			throw OT2AATError.invalidRule("Invalid anchor coordinates: '\(string)'. Coordinates must be integers")
		}
		
		return AnchorPoint(x: x, y: y)
	}
	
	/// Format for output
	var formatted: String {
		return "(\(x), \(y))"
	}
}

// MARK: - Mark Group (NEW - replaces MarkClass)

/// Semantic mark group where each mark has its own anchor
/// Example from .aar:
/// @mark_group BOTTOM
///     uni0E38 <-23, 0>
///     uni0E39 <-23, 0>
struct MarkGroup {
	let semantic: String                    // BOTTOM, TOP, MIDDLE, ATTACHMENT_0, etc.
	let marks: [String: AnchorPoint]        // glyph -> its anchor
	let lineNumber: Int
	
	init(semantic: String, marks: [String: AnchorPoint], lineNumber: Int) {
		self.semantic = semantic
		self.marks = marks
		self.lineNumber = lineNumber
	}
	
	var glyphNames: [String] {
		return Array(marks.keys).sorted()
	}
	
	var count: Int {
		return marks.count
	}
	
	var isEmpty: Bool {
		return marks.isEmpty
	}
	
	/// Get anchor for a specific mark
	func anchor(for mark: String) -> AnchorPoint? {
		return marks[mark]
	}
}

// MARK: - Base Glyph

/// Base glyph with attachment points for semantic groups
/// Example from .aar:
/// @base uni0E01
///     BOTTOM <133, 0>
///     TOP <130, 137>
struct BaseGlyph {
	let glyph: String                           // Base glyph name
	let attachments: [String: AnchorPoint]      // semantic -> anchor (BOTTOM, TOP, etc.)
	let lineNumber: Int
	
	init(glyph: String, attachments: [String: AnchorPoint], lineNumber: Int) {
		self.glyph = glyph
		self.attachments = attachments
		self.lineNumber = lineNumber
	}
	
	/// Get ordered semantic groups (for anchor index assignment)
	var orderedSemantics: [String] {
		return attachments.keys.sorted()
	}
}

// MARK: - Base Mark Glyph (Mark-to-Mark)

/// Mark glyph that acts as base for other marks (mark stacking)
/// Example from .aar:
/// @mark2mark uni0E38
///     BOTTOM <-23, -70>
struct BaseMarkGlyph {
	let mark: String                            // Mark glyph name
	let attachments: [String: AnchorPoint]      // semantic -> anchor
	let lineNumber: Int
	
	init(mark: String, attachments: [String: AnchorPoint], lineNumber: Int) {
		self.mark = mark
		self.attachments = attachments
		self.lineNumber = lineNumber
	}
	
	var orderedSemantics: [String] {
		return attachments.keys.sorted()
	}
}

// MARK: - Ligature Glyph

/// Ligature with multiple component anchors per semantic group
/// Example from .aar:
/// @ligature uniFEFB.ar
///     BOTTOM <149, 7> <85, 7>
///     TOP <150, 176> <85, 111>
struct LigatureGlyph {
	let ligature: String                        // Ligature glyph name
	let componentAnchors: [String: [AnchorPoint]]  // semantic -> [component anchors]
	let lineNumber: Int
	
	init(ligature: String, componentAnchors: [String: [AnchorPoint]], lineNumber: Int) {
		self.ligature = ligature
		self.componentAnchors = componentAnchors
		self.lineNumber = lineNumber
	}
	
	/// Number of components (should be same for all semantics)
	var componentCount: Int? {
		guard let first = componentAnchors.values.first else { return nil }
		return first.count
	}
	
	/// Get ordered semantic groups
	var orderedSemantics: [String] {
		return componentAnchors.keys.sorted()
	}
	
	/// Validate that all semantics have same component count
	func validate() throws {
		guard let expectedCount = componentCount else {
			throw OT2AATError.invalidRule("Line \(lineNumber): Ligature '\(ligature)' has no components")
		}
		
		for (semantic, anchors) in componentAnchors {
			if anchors.count != expectedCount {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Component count mismatch in ligature '\(ligature)'
					Semantic '\(semantic)' has \(anchors.count) components
					Expected \(expectedCount) components
					"""
				)
			}
		}
	}
}

// MARK: - Distance Rule (Simple Pairs)

/// Distance adjustment (contextual kerning)
/// Example: @distance uni0331 uni0E38 -50 vertical
struct DistanceRule {
	let context: RuleElement        // Glyph or class that triggers adjustment
	let target: RuleElement         // Glyph or class to adjust
	let adjustment: Int             // Value in font units
	let direction: Direction        // Horizontal or vertical
	let lineNumber: Int
	
	enum Direction: String {
		case horizontal = "horizontal"
		case vertical = "vertical"
		case both = "both"  // Default
	}
	
	init(context: RuleElement, target: RuleElement, adjustment: Int, 
		 direction: Direction = .horizontal, lineNumber: Int) {
		self.context = context
		self.target = target
		self.adjustment = adjustment
		self.direction = direction
		self.lineNumber = lineNumber
	}
	
	/// Expand class references to individual glyph pairs
	func expand(using registry: GlyphClassRegistry) throws -> [(String, String, Int)] {
		var pairs: [(String, String, Int)] = []
		
		let contextGlyphs = try context.resolve(using: registry)
		let targetGlyphs = try target.resolve(using: registry)
		
		for contextGlyph in contextGlyphs {
			for targetGlyph in targetGlyphs {
				pairs.append((contextGlyph, targetGlyph, adjustment))
			}
		}
		
		return pairs
	}
}

// MARK: - Distance Matrix (Class-Based)

/// Class-based distance matrix
struct DistanceMatrix {
	let leftClasses: [String]       // Class names (without @)
	let rightClasses: [String]      // Class names (without @)
	let adjustments: [(String, String, Int)]  // (rightClass, leftClass, value)
	let lineNumber: Int
	
	init(leftClasses: [String], rightClasses: [String], 
		 adjustments: [(String, String, Int)], lineNumber: Int) {
		self.leftClasses = leftClasses
		self.rightClasses = rightClasses
		self.adjustments = adjustments
		self.lineNumber = lineNumber
	}
	
	/// Validate that all referenced classes exist
	func validate(using registry: GlyphClassRegistry) throws {
		// Check left classes
		for className in leftClasses {
			guard registry.contains(className) else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Undefined class '@\(className)' in left classes
					Define class with: @class \(className) = ...
					"""
				)
			}
		}
		
		// Check right classes
		for className in rightClasses {
			guard registry.contains(className) else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Undefined class '@\(className)' in right classes
					Define class with: @class \(className) = ...
					"""
				)
			}
		}
		
		// Check adjustment classes
		for (rightClass, leftClass, _) in adjustments {
			guard rightClasses.contains(rightClass) else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Class '@\(rightClass)' not in right classes
					Add to right classes: right ... @\(rightClass) ...
					"""
				)
			}
			
			guard leftClasses.contains(leftClass) else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Class '@\(leftClass)' not in left classes
					Add to left classes: left ... @\(leftClass) ...
					"""
				)
			}
		}
	}
}

// MARK: - Mark Positioning Rules Container

/// Complete mark positioning rules (all four types)
struct MarkPositioningRules {
	let markGroups: [MarkGroup]  // Changed from markClasses
	let bases: [BaseGlyph]
	let baseMarks: [BaseMarkGlyph]
	let ligatures: [LigatureGlyph]
	let distanceRules: [DistanceRule]
	let distanceMatrices: [DistanceMatrix]
	let glyphClasses: [GlyphClass] 
	
	init(markGroups: [MarkGroup] = [],
		 bases: [BaseGlyph] = [],
		 baseMarks: [BaseMarkGlyph] = [],
		 ligatures: [LigatureGlyph] = [],
		 distanceRules: [DistanceRule] = [],
		 distanceMatrices: [DistanceMatrix] = [],
		 glyphClasses: [GlyphClass] = []) {
		self.markGroups = markGroups
		self.bases = bases
		self.baseMarks = baseMarks
		self.ligatures = ligatures
		self.distanceRules = distanceRules
		self.distanceMatrices = distanceMatrices
		self.glyphClasses = glyphClasses
	}
	
	/// Validate all rules
	func validate(using registry: GlyphClassRegistry) throws {
		// Validate mark groups are non-empty
		for markGroup in markGroups {
			if markGroup.isEmpty {
				throw OT2AATError.invalidRule(
					"Line \(markGroup.lineNumber): Mark group '\(markGroup.semantic)' is empty"
				)
			}
		}
		
		// Validate base attachments reference valid semantic groups
		let semanticNames = Set(markGroups.map { $0.semantic })
		
		for base in bases {
			for (semantic, _) in base.attachments {
				guard semanticNames.contains(semantic) else {
					throw OT2AATError.invalidRule(
						"""
						Line \(base.lineNumber): Base '\(base.glyph)' references undefined semantic group '\(semantic)'
						Define mark group with: @mark_group \(semantic) ...
						"""
					)
				}
			}
		}
		
		// Validate base marks reference valid semantic groups
		for baseMark in baseMarks {
			for (semantic, _) in baseMark.attachments {
				guard semanticNames.contains(semantic) else {
					throw OT2AATError.invalidRule(
						"""
						Line \(baseMark.lineNumber): Mark '\(baseMark.mark)' references undefined semantic group '\(semantic)'
						Define mark group with: @mark_group \(semantic) ...
						"""
					)
				}
			}
		}
		
		// Validate ligatures reference valid semantic groups and have valid components
		for ligature in ligatures {
			try ligature.validate()
			
			for (semantic, _) in ligature.componentAnchors {
				guard semanticNames.contains(semantic) else {
					throw OT2AATError.invalidRule(
						"""
						Line \(ligature.lineNumber): Ligature '\(ligature.ligature)' references undefined semantic group '\(semantic)'
						Define mark group with: @mark_group \(semantic) ...
						"""
					)
				}
			}
		}
		
		// Validate distance matrices
		for matrix in distanceMatrices {
			try matrix.validate(using: registry)
		}
	}
	
	/// Check if any positioning rules are defined
	var hasPositioning: Bool {
		return !bases.isEmpty || !baseMarks.isEmpty || !ligatures.isEmpty
	}
	
	/// Check if distance rules are defined
	var hasDistance: Bool {
		return !distanceRules.isEmpty || !distanceMatrices.isEmpty
	}
	
	/// Get mark group by semantic name
	func markGroup(named semantic: String) -> MarkGroup? {
		return markGroups.first { $0.semantic == semantic }
	}
	
	/// Get semantic group index for anchor assignment
	/// Ordered: BOTTOM < MIDDLE < TOP, or ATTACHMENT_0 < ATTACHMENT_1 < ...
	func semanticIndex(_ semantic: String) -> Int? {
		let ordered = orderedSemantics()
		return ordered.firstIndex(of: semantic)
	}
	
	/// Get ordered semantic groups (for consistent anchor indexing)
	func orderedSemantics() -> [String] {
		return markGroups.map { $0.semantic }.sorted { lhs, rhs in
			// Custom sort: BOTTOM < MIDDLE < TOP < ATTACHMENT_*
			let order = ["BOTTOM", "MIDDLE", "TOP"]
			if let lhsIdx = order.firstIndex(of: lhs), let rhsIdx = order.firstIndex(of: rhs) {
				return lhsIdx < rhsIdx
			}
			if order.contains(lhs) && !order.contains(rhs) {
				return true
			}
			if !order.contains(lhs) && order.contains(rhs) {
				return false
			}
			return lhs < rhs  // Lexicographic for ATTACHMENT_*
		}
	}
}

// MARK: - RuleElement Extension

extension RuleElement {
	/// Resolve to list of glyph names
	func resolve(using registry: GlyphClassRegistry) throws -> [String] {
		switch self {
		case .glyph(let name):
			return [name]
		case .classRef(let className):
			guard let glyphClass = registry.lookup(className) else {
				throw OT2AATError.invalidRule("Undefined class '@\(className)'")
			}
			return glyphClass.glyphs
		}
	}
}
