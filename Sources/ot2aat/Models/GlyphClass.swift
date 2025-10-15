import Foundation

/// Represents a glyph class definition
/// Example: @class vowels = uni0E38 uni0E39 uni0E3A
struct GlyphClass {
	let name: String
	let glyphs: [String]
	
	init(name: String, glyphs: [String]) {
		self.name = name
		self.glyphs = glyphs
	}
	
	var count: Int {
		return glyphs.count
	}
	
	/// Check if class is empty (invalid)
	var isEmpty: Bool {
		return glyphs.isEmpty
	}
}

/// Registry for storing and looking up glyph classes
struct GlyphClassRegistry {
	private var classes: [String: GlyphClass] = [:]
	
	/// Register a new class
	mutating func register(_ glyphClass: GlyphClass) throws {
		if classes[glyphClass.name] != nil {
			throw OT2AATError.invalidRule("Duplicate class definition: '@\(glyphClass.name)'")
		}
		classes[glyphClass.name] = glyphClass
	}
	
	/// Look up a class by name
	func lookup(_ name: String) -> GlyphClass? {
		return classes[name]
	}
	
	/// Check if a class exists
	func contains(_ name: String) -> Bool {
		return classes[name] != nil
	}
	
	/// Get all registered classes
	var all: [GlyphClass] {
		return Array(classes.values)
	}
}

extension GlyphClassRegistry {
	func allClasses() -> [GlyphClass] {
		return Array(classes.values)
	}
}
