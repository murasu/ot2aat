import Foundation

extension RuleParser {
	/// Parse unified GSUB rules from file
	/// Format supports: @simple, @ligature, @one2many, @contextual, @reorder sections
	static func parseGsubRules(from path: String) throws -> GsubRules {
		guard FileManager.default.fileExists(atPath: path) else {
			throw OT2AATError.fileNotFound(path)
		}
		
		let content = try String(contentsOfFile: path, encoding: .utf8)
		var rules = GsubRules()
		var registry = GlyphClassRegistry()
		
		enum Section {
			case none
			case simple
			case ligature
			case one2many
			case contextual
			case reorder
		}
		
		var currentSection: Section = .none
		
		for (lineNumber, line) in content.components(separatedBy: .newlines).enumerated() {
			let lineNum = lineNumber + 1
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			
			// Skip empty lines and comments
			if trimmed.isEmpty || trimmed.hasPrefix("#") {
				continue
			}
			
			// Remove end-of-line comments
			let withoutComment = trimmed.components(separatedBy: "#")[0]
				.trimmingCharacters(in: .whitespaces)
			
			// Check for section markers
			if withoutComment == "@simple {" {
				currentSection = .simple
				continue
			} else if withoutComment == "@ligature {" {
				currentSection = .ligature
				continue
			} else if withoutComment == "@one2many {" {
				currentSection = .one2many
				continue
			} else if withoutComment == "@contextual {" {
				currentSection = .contextual
				continue
			} else if withoutComment == "@reorder {" {
				currentSection = .reorder
				continue
			} else if withoutComment == "}" {
				currentSection = .none
				continue
			}
			
			// Global class definition
			if withoutComment.hasPrefix("@class ") {
				let glyphClass = try parseClassDefinition(withoutComment, lineNumber: lineNum)
				try registry.register(glyphClass)
				rules.classes.append(glyphClass)
				continue
			}
			
			// Parse based on current section
			switch currentSection {
			case .none:
				// Outside any section - ignore or warn
				break
				
			case .simple:
				let sub = try parseSimpleSubstitution(withoutComment, lineNumber: lineNum)
				rules.simpleSubstitutions.append(sub)
				
			case .ligature:
				let lig = try parseLigature(withoutComment, lineNumber: lineNum)
				rules.ligatures.append(lig)
				
			case .one2many:
				let sub = try parseOne2ManyLine(withoutComment, lineNumber: lineNum)
				rules.one2many.append(sub)
				
			case .contextual:
				let ctx = try parseContextualRule(withoutComment, 
												  lineNumber: lineNum, 
												  registry: registry)
				rules.contextual.append(ctx)
				
			case .reorder:
				let reorder = try parseReorderRule(withoutComment, 
												   lineNumber: lineNum, 
												   registry: registry)
				rules.reorder.append(reorder)
			}
		}
		
		if !rules.hasRules {
			throw OT2AATError.invalidRule("No valid rules found in file")
		}
		
		return rules
	}
	
	// MARK: - Section Parsers
	
	/// Parse simple substitution: source -> target
	private static func parseSimpleSubstitution(
		_ line: String,
		lineNumber: Int
	) throws -> SimpleSubstitution {
		let parts = line.components(separatedBy: "->")
		guard parts.count == 2 else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Expected format 'source -> target'"
			)
		}
		
		let source = parts[0].trimmingCharacters(in: .whitespaces)
		let target = parts[1].trimmingCharacters(in: .whitespaces)
		
		guard !source.isEmpty && !target.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Source and target cannot be empty"
			)
		}
		
		return SimpleSubstitution(source: source, target: target)
	}
	
	/// Parse ligature: target := comp1 + comp2 + comp3
	private static func parseLigature(
		_ line: String,
		lineNumber: Int
	) throws -> LigatureRule {
		let parts = line.components(separatedBy: ":=")
		guard parts.count == 2 else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Expected format 'target := comp1 + comp2'"
			)
		}
		
		let target = parts[0].trimmingCharacters(in: .whitespaces)
		let componentsStr = parts[1].trimmingCharacters(in: .whitespaces)
		
		let components = componentsStr
			.components(separatedBy: "+")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		
		guard !target.isEmpty && components.count >= 2 else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Ligature must have target and at least 2 components"
			)
		}
		
		return LigatureRule(target: target, components: components)
	}
	
	/// Parse one-to-many: source > target1 target2 target3
	private static func parseOne2ManyLine(
		_ line: String,
		lineNumber: Int
	) throws -> SubstitutionRule {
		let parts = line.components(separatedBy: ">")
		guard parts.count == 2 else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Expected format 'source > target1 target2 ...'"
			)
		}
		
		let source = parts[0].trimmingCharacters(in: .whitespaces)
		let targets = parts[1]
			.trimmingCharacters(in: .whitespaces)
			.components(separatedBy: .whitespaces)
			.filter { !$0.isEmpty }
		
		guard !source.isEmpty && !targets.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Source and targets cannot be empty"
			)
		}
		
		return SubstitutionRule(source: source, targets: targets)
	}
}
