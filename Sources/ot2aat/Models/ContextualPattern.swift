import Foundation

/// Context type for contextual substitution
enum ContextType {
	case after([RuleElement])
	case before([RuleElement])
	case between(first: [RuleElement], second: [RuleElement])
	case when([RuleElement])
	
	var description: String {
		switch self {
		case .after(let pattern):
			return "after \(pattern.map(\.description).joined(separator: " "))"
		case .before(let pattern):
			return "before \(pattern.map(\.description).joined(separator: " "))"
		case .between(let first, let second):
			return "between \(first.map(\.description).joined(separator: " ")) and \(second.map(\.description).joined(separator: " "))"
		case .when(let pattern):
			return "when \(pattern.map(\.description).joined(separator: " "))"
		}
	}
}
