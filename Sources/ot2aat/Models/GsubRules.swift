import Foundation

/// Unified GSUB rules structure (all substitution types)
struct GsubRules {
	var classes: [GlyphClass]
	var simpleSubstitutions: [SimpleSubstitution]
	var ligatures: [LigatureRule]
	var one2many: [SubstitutionRule]
	var contextual: [ContextualRule]
	var reorder: [ReorderRule]
	
	/// Check if any rules exist
	var hasRules: Bool {
		!simpleSubstitutions.isEmpty ||
		!ligatures.isEmpty ||
		!one2many.isEmpty ||
		!contextual.isEmpty ||
		!reorder.isEmpty
	}
	
	/// Initialize with empty arrays
	init() {
		self.classes = []
		self.simpleSubstitutions = []
		self.ligatures = []
		self.one2many = []
		self.contextual = []
		self.reorder = []
	}
}

/// Simple 1:1 substitution (Type 1)
struct SimpleSubstitution {
	let source: String
	let target: String
}

/// Ligature substitution (Type 4)
struct LigatureRule {
	let target: String
	let components: [String]
}
