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

// MARK: - Mark Class

/// Mark class with shared anchor point
/// Example: @markclass TOP_MARKS <0, 148> uni0E48 uni0E49
struct MarkClass {
	let name: String           // e.g., "TOP_MARKS"
	let marks: [String]        // Glyph names
	let anchor: AnchorPoint    // Shared anchor for all marks
	let lineNumber: Int
	
	init(name: String, marks: [String], anchor: AnchorPoint, lineNumber: Int) {
		self.name = name
		self.marks = marks
		self.anchor = anchor
		self.lineNumber = lineNumber
	}
	
	var count: Int {
		return marks.count
	}
	
	var isEmpty: Bool {
		return marks.isEmpty
	}
}

// MARK: - Base Glyph

/// Base glyph with attachment points for mark classes
struct BaseGlyph {
	let glyph: String                           // Base glyph name
	let attachments: [String: AnchorPoint]      // markClassName -> anchor
	let lineNumber: Int
	
	init(glyph: String, attachments: [String: AnchorPoint], lineNumber: Int) {
		self.glyph = glyph
		self.attachments = attachments
		self.lineNumber = lineNumber
	}
}

// MARK: - Base Mark Glyph (Mark-to-Mark)

/// Mark glyph that acts as base for other marks (mark stacking)
struct BaseMarkGlyph {
	let mark: String                            // Mark glyph name
	let attachments: [String: AnchorPoint]      // markClassName -> anchor
	let lineNumber: Int
	
	init(mark: String, attachments: [String: AnchorPoint], lineNumber: Int) {
		self.mark = mark
		self.attachments = attachments
		self.lineNumber = lineNumber
	}
}

// MARK: - Ligature Glyph

/// Ligature with multiple component anchors
struct LigatureGlyph {
	let ligature: String                        // Ligature glyph name
	let componentAnchors: [String: [AnchorPoint]]  // markClassName -> [component anchors]
	let lineNumber: Int
	
	init(ligature: String, componentAnchors: [String: [AnchorPoint]], lineNumber: Int) {
		self.ligature = ligature
		self.componentAnchors = componentAnchors
		self.lineNumber = lineNumber
	}
	
	/// Number of components (should be same for all mark classes)
	var componentCount: Int? {
		guard let first = componentAnchors.values.first else { return nil }
		return first.count
	}
	
	/// Validate that all mark classes have same component count
	func validate() throws {
		guard let expectedCount = componentCount else {
			throw OT2AATError.invalidRule("Line \(lineNumber): Ligature '\(ligature)' has no components")
		}
		
		for (markClass, anchors) in componentAnchors {
			if anchors.count != expectedCount {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Component count mismatch in ligature '\(ligature)'
					Mark class '\(markClass)' has \(anchors.count) components
					Expected \(expectedCount) components
					"""
				)
			}
		}
	}
}

// MARK: - Distance Rule (Simple Pairs)

/// Distance adjustment (contextual kerning)
/// Example: @distance uni0331 uni0E38 -50
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
/// Example:
/// @matrix
///     left @LEFT1 @LEFT2
///     right @RIGHT1 @RIGHT2
///     @RIGHT1 @LEFT1 => -28
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
	let markClasses: [MarkClass]
	let bases: [BaseGlyph]
	let baseMarks: [BaseMarkGlyph]
	let ligatures: [LigatureGlyph]
	let distanceRules: [DistanceRule]
	let distanceMatrices: [DistanceMatrix]
	
	init(markClasses: [MarkClass] = [],
		 bases: [BaseGlyph] = [],
		 baseMarks: [BaseMarkGlyph] = [],
		 ligatures: [LigatureGlyph] = [],
		 distanceRules: [DistanceRule] = [],
		 distanceMatrices: [DistanceMatrix] = []) {
		self.markClasses = markClasses
		self.bases = bases
		self.baseMarks = baseMarks
		self.ligatures = ligatures
		self.distanceRules = distanceRules
		self.distanceMatrices = distanceMatrices
	}
	
	/// Validate all rules
	func validate(using registry: GlyphClassRegistry) throws {
		// Validate mark classes are non-empty
		for markClass in markClasses {
			if markClass.isEmpty {
				throw OT2AATError.invalidRule(
					"Line \(markClass.lineNumber): Mark class '@\(markClass.name)' is empty"
				)
			}
		}
		
		// Validate base attachments reference valid mark classes
		let markClassNames = Set(markClasses.map { $0.name })
		
		for base in bases {
			for (markClassName, _) in base.attachments {
				guard markClassNames.contains(markClassName) else {
					throw OT2AATError.invalidRule(
						"""
						Line \(base.lineNumber): Base '\(base.glyph)' references undefined mark class '\(markClassName)'
						Define mark class with: @markclass \(markClassName) <x, y> ...
						"""
					)
				}
			}
		}
		
		// Validate base marks reference valid mark classes
		for baseMark in baseMarks {
			for (markClassName, _) in baseMark.attachments {
				guard markClassNames.contains(markClassName) else {
					throw OT2AATError.invalidRule(
						"""
						Line \(baseMark.lineNumber): Mark '\(baseMark.mark)' references undefined mark class '\(markClassName)'
						Define mark class with: @markclass \(markClassName) <x, y> ...
						"""
					)
				}
			}
		}
		
		// Validate ligatures reference valid mark classes and have valid components
		for ligature in ligatures {
			try ligature.validate()
			
			for (markClassName, _) in ligature.componentAnchors {
				guard markClassNames.contains(markClassName) else {
					throw OT2AATError.invalidRule(
						"""
						Line \(ligature.lineNumber): Ligature '\(ligature.ligature)' references undefined mark class '\(markClassName)'
						Define mark class with: @markclass \(markClassName) <x, y> ...
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
	
	/// Get mark class by name
	func markClass(named name: String) -> MarkClass? {
		return markClasses.first { $0.name == name }
	}
	
	/// Get index of mark class (for anchor point indexing)
	func markClassIndex(named name: String) -> Int? {
		return markClasses.firstIndex { $0.name == name }
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
