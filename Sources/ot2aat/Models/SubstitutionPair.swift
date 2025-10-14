import Foundation

/// Represents a target => replacement pair
struct SubstitutionPair {
	let target: RuleElement
	let replacement: RuleElement
	let wildcardType: WildcardType?
	
	init(target: RuleElement, replacement: RuleElement, wildcardType: WildcardType? = nil) {
		self.target = target
		self.replacement = replacement
		self.wildcardType = wildcardType
	}
}

/// Wildcard substitution patterns (kept as-is for ftxenhancer)
enum WildcardType {
	case addSuffix(String)           // * => * ".alt"
	case removeSuffix(String)        // * ".alt" => *
	case replaceSuffix(String, String) // * ".old" => * ".new"
}
