// MARK: - Mark Positioning Parser

import Foundation

extension RuleParser {
	
	/// Parse mark positioning rules from file (.aar format)
	/// Returns all four types: mark groups, distances, bases, basemarks, ligatures
	static func parseMarkPositioningRules(from path: String) throws -> MarkPositioningRules {
		guard FileManager.default.fileExists(atPath: path) else {
			throw OT2AATError.fileNotFound(path)
		}
		
		let content = try String(contentsOfFile: path, encoding: .utf8)
		let lines = content.components(separatedBy: .newlines)
		
		var registry = GlyphClassRegistry()
		var markGroups: [MarkGroup] = []
		var bases: [BaseGlyph] = []
		var baseMarks: [BaseMarkGlyph] = []
		var ligatures: [LigatureGlyph] = []
		var distanceRules: [DistanceRule] = []
		var distanceMatrices: [DistanceMatrix] = []
		
		var lineIndex = 0
		while lineIndex < lines.count {
			let lineNum = lineIndex + 1
			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
			
			// Skip empty lines and comments
			if line.isEmpty || line.hasPrefix("#") {
				lineIndex += 1
				continue
			}
			
			// Remove end-of-line comments
			let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
			
			// Parse based on keyword
			if withoutComment.hasPrefix("@class ") {
				// Regular glyph class definition
				let glyphClass = try parseClassDefinition(withoutComment, lineNumber: lineNum)
				try registry.register(glyphClass)
				lineIndex += 1
				
			} else if withoutComment.hasPrefix("@mark_group ") {
				// NEW: Mark group definition (semantic grouping)
				let (markGroup, linesConsumed) = try parseMarkGroup(lines, startIndex: lineIndex)
				
				// Check for duplicate semantic names
				if markGroups.contains(where: { $0.semantic == markGroup.semantic }) {
					throw OT2AATError.invalidRule(
						"Line \(lineNum): Duplicate mark group '\(markGroup.semantic)'"
					)
				}
				
				markGroups.append(markGroup)
				lineIndex += linesConsumed
				
			} else if withoutComment.hasPrefix("@distance ") {
				// Distance rule (single line)
				let rule = try parseDistanceRule(withoutComment, lineNumber: lineNum, registry: registry)
				distanceRules.append(rule)
				lineIndex += 1
				
			} else if withoutComment.hasPrefix("@matrix") {
				// Distance matrix (multi-line)
				let (matrix, linesConsumed) = try parseDistanceMatrix(lines, startIndex: lineIndex, registry: registry)
				distanceMatrices.append(matrix)
				lineIndex += linesConsumed
				
			} else if withoutComment.hasPrefix("@base ") {
				// Base definition (multi-line)
				let (newBases, linesConsumed) = try parseBaseDefinition(lines, startIndex: lineIndex, registry: registry)
				bases.append(contentsOf: newBases)
				lineIndex += linesConsumed
				
			} else if withoutComment.hasPrefix("@mark2mark ") {
				// Mark-to-mark definition (multi-line)
				let (newBaseMarks, linesConsumed) = try parseMark2MarkDefinition(lines, startIndex: lineIndex, registry: registry)
				baseMarks.append(contentsOf: newBaseMarks)
				lineIndex += linesConsumed
				
			} else if withoutComment.hasPrefix("@ligature ") {
				// Ligature definition (multi-line)
				let (ligature, linesConsumed) = try parseLigatureDefinition(lines, startIndex: lineIndex)
				ligatures.append(ligature)
				lineIndex += linesConsumed
				
			} else {
				throw OT2AATError.invalidRule(
					"Line \(lineNum): Unrecognized syntax: '\(withoutComment)'"
				)
			}
		}
		
		let rules = MarkPositioningRules(
			markGroups: markGroups,
			bases: bases,
			baseMarks: baseMarks,
			ligatures: ligatures,
			distanceRules: distanceRules,
			distanceMatrices: distanceMatrices,
			glyphClasses: registry.allClasses() 
		)
		
		// Validate all rules
		try rules.validate(using: registry)
		
		return rules
	}
	
	// MARK: - Mark Group Parser (NEW)
	
	/// Parse @mark_group definition (NEW FORMAT)
	/// Format:
	/// @mark_group SEMANTIC
	///     glyph1 <x1, y1>
	///     glyph2 <x2, y2>
	///     glyph3 <x3, y3>
	private static func parseMarkGroup(_ lines: [String], startIndex: Int) throws -> (MarkGroup, Int) {
		let lineNum = startIndex + 1
		let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
		
		// Remove @mark_group prefix
		let semantic = firstLine.dropFirst(12).trimmingCharacters(in: .whitespaces)
		
		guard !semantic.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @mark_group requires semantic name (BOTTOM, TOP, MIDDLE, etc.)"
			)
		}
		
		// Parse mark definitions (each mark has its own anchor)
		var marks: [String: AnchorPoint] = [:]
		var currentLine = startIndex + 1
		var linesConsumed = 1
		
		while currentLine < lines.count {
			let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
			
			// Skip empty lines and comments
			if line.isEmpty || line.hasPrefix("#") {
				currentLine += 1
				linesConsumed += 1
				continue
			}
			
			// Remove end-of-line comments
			let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
			
			// Stop at next keyword
			if withoutComment.hasPrefix("@") {
				break
			}
			
			// Parse: glyph <x, y>
			let parts = withoutComment.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
			
			guard parts.count >= 2 else {
				throw OT2AATError.invalidRule(
					"""
					Line \(currentLine + 1): Invalid mark definition
					Expected: glyph <x, y>
					Got: \(withoutComment)
					"""
				)
			}
			
			let glyphName = parts[0]
			
			// Reconstruct anchor (may be split across multiple parts)
			var anchorStr = ""
			for i in 1..<parts.count {
				anchorStr += parts[i]
				if parts[i].contains(">") {
					break
				}
				anchorStr += " "
			}
			
			let anchor = try AnchorPoint.parse(anchorStr)
			
			// Check for duplicate marks
			if marks[glyphName] != nil {
				throw OT2AATError.invalidRule(
					"""
					Line \(currentLine + 1): Duplicate mark '\(glyphName)' in group '\(semantic)'
					Each mark should appear only once per semantic group
					"""
				)
			}
			
			marks[glyphName] = anchor
			
			currentLine += 1
			linesConsumed += 1
		}
		
		guard !marks.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): Mark group '\(semantic)' has no marks"
			)
		}
		
		let markGroup = MarkGroup(semantic: semantic, marks: marks, lineNumber: lineNum)
		return (markGroup, linesConsumed)
	}
	
	// MARK: - Distance Rule Parser (keep existing)
	
	/// Parse @distance rule
	/// Format: @distance context target value [direction]
	private static func parseDistanceRule(_ line: String, lineNumber: Int, registry: GlyphClassRegistry) throws -> DistanceRule {
		// (Keep existing implementation - no changes needed)
		let withoutPrefix = line.dropFirst(10).trimmingCharacters(in: .whitespaces)
		let parts = withoutPrefix.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
		
		guard parts.count >= 3 else {
			throw OT2AATError.invalidRule(
				"""
				Line \(lineNumber): Invalid @distance syntax
				Expected: @distance context target value [direction]
				Got: \(line)
				"""
			)
		}
		
		let contextStr = parts[0]
		let targetStr = parts[1]
		let valueStr = parts[2]
		
		let context = try parseRuleElement(contextStr, lineNumber: lineNumber)
		let target = try parseRuleElement(targetStr, lineNumber: lineNumber)
		
		guard let value = Int(valueStr) else {
			throw OT2AATError.invalidRule(
				"Line \(lineNumber): Invalid adjustment value '\(valueStr)'. Must be an integer"
			)
		}
		
		var direction = DistanceRule.Direction.horizontal
		if parts.count >= 4 {
			let dirStr = parts[3].lowercased()
			if let dir = DistanceRule.Direction(rawValue: dirStr) {
				direction = dir
			} else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNumber): Invalid direction '\(parts[3])'
					Valid directions: horizontal, vertical, both
					"""
				)
			}
		}
		
		return DistanceRule(
			context: context,
			target: target,
			adjustment: value,
			direction: direction,
			lineNumber: lineNumber
		)
	}
	
	// MARK: - Distance Matrix Parser (keep existing - unchanged)
	
	/// Parse @matrix definition
	private static func parseDistanceMatrix(_ lines: [String], startIndex: Int, registry: GlyphClassRegistry) throws -> (DistanceMatrix, Int) {
		// (Keep entire existing implementation)
		let lineNum = startIndex + 1
		
		var leftClasses: [String] = []
		var rightClasses: [String] = []
		var adjustments: [(String, String, Int)] = []
		
		var currentLine = startIndex + 1
		var linesConsumed = 1
		
		while currentLine < lines.count {
			let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
			
			if line.isEmpty || line.hasPrefix("#") {
				currentLine += 1
				linesConsumed += 1
				continue
			}
			
			let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
			
			if withoutComment.hasPrefix("@") && !withoutComment.contains("=>") {
				if withoutComment.hasPrefix("left ") {
					let classesStr = withoutComment.dropFirst(5).trimmingCharacters(in: .whitespaces)
					let classes = classesStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
					
					for className in classes {
						guard className.hasPrefix("@") else {
							throw OT2AATError.invalidRule(
								"Line \(currentLine + 1): Class name must start with @: '\(className)'"
							)
						}
						leftClasses.append(String(className.dropFirst()))
					}
					
				} else if withoutComment.hasPrefix("right ") {
					let classesStr = withoutComment.dropFirst(6).trimmingCharacters(in: .whitespaces)
					let classes = classesStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
					
					for className in classes {
						guard className.hasPrefix("@") else {
							throw OT2AATError.invalidRule(
								"Line \(currentLine + 1): Class name must start with @: '\(className)'"
							)
						}
						rightClasses.append(String(className.dropFirst()))
					}
					
				} else {
					break
				}
				
			} else if withoutComment.contains("=>") {
				let parts = withoutComment.components(separatedBy: "=>")
				guard parts.count == 2 else {
					throw OT2AATError.invalidRule(
						"""
						Line \(currentLine + 1): Invalid adjustment syntax
						Expected: @RIGHT_CLASS @LEFT_CLASS => value
						Got: \(withoutComment)
						"""
					)
				}
				
				let classNames = parts[0].trimmingCharacters(in: .whitespaces)
					.components(separatedBy: .whitespaces)
					.filter { !$0.isEmpty }
				
				guard classNames.count == 2 else {
					throw OT2AATError.invalidRule(
						"""
						Line \(currentLine + 1): Expected two class names
						Format: @RIGHT_CLASS @LEFT_CLASS => value
						Got: \(parts[0])
						"""
					)
				}
				
				guard classNames[0].hasPrefix("@") && classNames[1].hasPrefix("@") else {
					throw OT2AATError.invalidRule(
						"Line \(currentLine + 1): Class names must start with @"
					)
				}
				
				let rightClass = String(classNames[0].dropFirst())
				let leftClass = String(classNames[1].dropFirst())
				
				let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
				guard let value = Int(valueStr) else {
					throw OT2AATError.invalidRule(
						"Line \(currentLine + 1): Invalid adjustment value '\(valueStr)'. Must be an integer"
					)
				}
				
				adjustments.append((rightClass, leftClass, value))
				
			} else {
				throw OT2AATError.invalidRule(
					"Line \(currentLine + 1): Unexpected content in @matrix block: '\(withoutComment)'"
				)
			}
			
			currentLine += 1
			linesConsumed += 1
		}
		
		guard !leftClasses.isEmpty && !rightClasses.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @matrix must have both 'left' and 'right' class definitions"
			)
		}
		
		let matrix = DistanceMatrix(
			leftClasses: leftClasses,
			rightClasses: rightClasses,
			adjustments: adjustments,
			lineNumber: lineNum
		)
		
		return (matrix, linesConsumed)
	}
	
	// MARK: - Base Definition Parser (UPDATED for semantic references)
	
	/// Parse @base definition (UPDATED)
	/// Format:
	/// @base glyph
	///     SEMANTIC1 <x, y>
	///     SEMANTIC2 <x, y>
	private static func parseBaseDefinition(_ lines: [String], startIndex: Int, registry: GlyphClassRegistry) throws -> ([BaseGlyph], Int) {
		let lineNum = startIndex + 1
		let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
		
		// Remove @base prefix
		let glyphOrClass = firstLine.dropFirst(6).trimmingCharacters(in: .whitespaces)
		
		guard !glyphOrClass.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @base requires glyph name or @CLASS"
			)
		}
		
		let isClass = glyphOrClass.hasPrefix("@")
		
		// Parse attachment lines
		var currentLine = startIndex + 1
		var linesConsumed = 1
		var attachmentLines: [String] = []
		
		while currentLine < lines.count {
			let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
			
			if line.isEmpty || line.hasPrefix("#") {
				currentLine += 1
				linesConsumed += 1
				continue
			}
			
			let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
			
			if withoutComment.hasPrefix("@") {
				break
			}
			
			attachmentLines.append(withoutComment)
			currentLine += 1
			linesConsumed += 1
		}
		
		guard !attachmentLines.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @base '\(glyphOrClass)' has no attachment points"
			)
		}
		
		var bases: [BaseGlyph] = []
		
		if isClass {
			let className = String(glyphOrClass.dropFirst())
			guard let glyphClass = registry.lookup(className) else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNum): Undefined class '@\(className)'
					Define class with: @class \(className) = ...
					"""
				)
			}
			
			// Check format: uniform or per-glyph
			let firstAttachmentLine = attachmentLines[0]
			if firstAttachmentLine.contains(":") {
				// Per-glyph format
				for attachmentLine in attachmentLines {
					let parts = attachmentLine.components(separatedBy: ":")
					guard parts.count == 2 else {
						throw OT2AATError.invalidRule(
							"Line \(lineNum): Invalid per-glyph syntax. Expected: glyph: SEMANTIC <x, y>, ..."
						)
					}
					
					let glyphName = parts[0].trimmingCharacters(in: .whitespaces)
					guard glyphClass.glyphs.contains(glyphName) else {
						throw OT2AATError.invalidRule(
							"Line \(lineNum): Glyph '\(glyphName)' not in class '@\(className)'"
						)
					}
					
					let attachments = try parseSemanticAttachments(parts[1], lineNumber: lineNum)
					bases.append(BaseGlyph(glyph: glyphName, attachments: attachments, lineNumber: lineNum))
				}
				
			} else {
				// Uniform format - same attachments for all glyphs
				var attachments: [String: AnchorPoint] = [:]
				for attachmentLine in attachmentLines {
					let (semantic, anchor) = try parseSemanticAttachment(attachmentLine, lineNumber: lineNum)
					attachments[semantic] = anchor
				}
				
				for glyph in glyphClass.glyphs {
					bases.append(BaseGlyph(glyph: glyph, attachments: attachments, lineNumber: lineNum))
				}
			}
			
		} else {
			// Individual glyph
			var attachments: [String: AnchorPoint] = [:]
			for attachmentLine in attachmentLines {
				let (semantic, anchor) = try parseSemanticAttachment(attachmentLine, lineNumber: lineNum)
				attachments[semantic] = anchor
			}
			
			bases.append(BaseGlyph(glyph: glyphOrClass, attachments: attachments, lineNumber: lineNum))
		}
		
		return (bases, linesConsumed)
	}
	
	// MARK: - Mark2Mark Parser (UPDATED for semantic references)
	
	/// Parse @mark2mark definition (UPDATED)
	/// Same format as @base but with semantic references
	private static func parseMark2MarkDefinition(_ lines: [String], startIndex: Int, registry: GlyphClassRegistry) throws -> ([BaseMarkGlyph], Int) {
		let lineNum = startIndex + 1
		let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
		
		// Remove @mark2mark prefix
		let glyphOrClass = firstLine.dropFirst(11).trimmingCharacters(in: .whitespaces)
		
		guard !glyphOrClass.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @mark2mark requires glyph name or @CLASS"
			)
		}
		
		let isClass = glyphOrClass.hasPrefix("@")
		
		// Parse attachment lines
		var currentLine = startIndex + 1
		var linesConsumed = 1
		var attachmentLines: [String] = []
		
		while currentLine < lines.count {
			let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
			
			if line.isEmpty || line.hasPrefix("#") {
				currentLine += 1
				linesConsumed += 1
				continue
			}
			
			let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
			
			if withoutComment.hasPrefix("@") {
				break
			}
			
			attachmentLines.append(withoutComment)
			currentLine += 1
			linesConsumed += 1
		}
		
		guard !attachmentLines.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @mark2mark '\(glyphOrClass)' has no attachment points"
			)
		}
		
		var baseMarks: [BaseMarkGlyph] = []
		
		if isClass {
			let className = String(glyphOrClass.dropFirst())
			guard let glyphClass = registry.lookup(className) else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNum): Undefined class '@\(className)'
					Define class with: @class \(className) = ...
					"""
				)
			}
			
			// Check format
			let firstAttachmentLine = attachmentLines[0]
			if firstAttachmentLine.contains(":") {
				// Per-glyph format
				for attachmentLine in attachmentLines {
					let parts = attachmentLine.components(separatedBy: ":")
					guard parts.count == 2 else {
						throw OT2AATError.invalidRule(
							"Line \(lineNum): Invalid per-glyph syntax"
						)
					}
					
					let glyphName = parts[0].trimmingCharacters(in: .whitespaces)
					guard glyphClass.glyphs.contains(glyphName) else {
						throw OT2AATError.invalidRule(
							"Line \(lineNum): Glyph '\(glyphName)' not in class '@\(className)'"
						)
					}
					
					let attachments = try parseSemanticAttachments(parts[1], lineNumber: lineNum)
					baseMarks.append(BaseMarkGlyph(mark: glyphName, attachments: attachments, lineNumber: lineNum))
				}
				
			} else {
				// Uniform format
				var attachments: [String: AnchorPoint] = [:]
				for attachmentLine in attachmentLines {
					let (semantic, anchor) = try parseSemanticAttachment(attachmentLine, lineNumber: lineNum)
					attachments[semantic] = anchor
				}
				
				for glyph in glyphClass.glyphs {
					baseMarks.append(BaseMarkGlyph(mark: glyph, attachments: attachments, lineNumber: lineNum))
				}
			}
			
		} else {
			// Individual mark glyph
			var attachments: [String: AnchorPoint] = [:]
			for attachmentLine in attachmentLines {
				let (semantic, anchor) = try parseSemanticAttachment(attachmentLine, lineNumber: lineNum)
				attachments[semantic] = anchor
			}
			
			baseMarks.append(BaseMarkGlyph(mark: glyphOrClass, attachments: attachments, lineNumber: lineNum))
		}
		
		return (baseMarks, linesConsumed)
	}
	
	// MARK: - Ligature Parser (UPDATED for semantic references)
	
	/// Parse @ligature definition (UPDATED)
	/// Format:
	/// @ligature glyph
	///     SEMANTIC1 <x1, y1> <x2, y2> <x3, y3>
	///     SEMANTIC2 <x1, y1> <x2, y2> <x3, y3>
	private static func parseLigatureDefinition(_ lines: [String], startIndex: Int) throws -> (LigatureGlyph, Int) {
		let lineNum = startIndex + 1
		let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
		
		// Remove @ligature prefix
		let ligatureName = firstLine.dropFirst(10).trimmingCharacters(in: .whitespaces)
		
		guard !ligatureName.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @ligature requires glyph name"
			)
		}
		
		// Parse component anchor lines
		var currentLine = startIndex + 1
		var linesConsumed = 1
		var componentAnchorLines: [String] = []
		
		while currentLine < lines.count {
			let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
			
			if line.isEmpty || line.hasPrefix("#") {
				currentLine += 1
				linesConsumed += 1
				continue
			}
			
			let withoutComment = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
			
			if withoutComment.hasPrefix("@") {
				break
			}
			
			componentAnchorLines.append(withoutComment)
			currentLine += 1
			linesConsumed += 1
		}
		
		guard !componentAnchorLines.isEmpty else {
			throw OT2AATError.invalidRule(
				"Line \(lineNum): @ligature '\(ligatureName)' has no component anchors"
			)
		}
		
		// Parse each line: SEMANTIC <x1, y1> <x2, y2> ...
		var componentAnchors: [String: [AnchorPoint]] = [:]
		
		for anchorLine in componentAnchorLines {
			let parts = anchorLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
			
			guard parts.count >= 2 else {
				throw OT2AATError.invalidRule(
					"""
					Line \(lineNum): Invalid ligature component syntax
					Expected: SEMANTIC <x1, y1> <x2, y2> ...
					Got: \(anchorLine)
					"""
				)
			}
			
			let semantic = parts[0]
			
			// Parse anchor points (rest of the parts)
			var anchors: [AnchorPoint] = []
			var i = 1
			var currentAnchor = ""
			
			while i < parts.count {
				currentAnchor += parts[i]
				
				if parts[i].contains(">") {
					// Complete anchor
					let anchor = try AnchorPoint.parse(currentAnchor)
					anchors.append(anchor)
					currentAnchor = ""
				} else {
					currentAnchor += " "
				}
				
				i += 1
			}
			
			guard !anchors.isEmpty else {
				throw OT2AATError.invalidRule(
					"Line \(lineNum): No valid anchor points for semantic '\(semantic)'"
				)
			}
			
			componentAnchors[semantic] = anchors
		}
		
		let ligature = LigatureGlyph(
			ligature: ligatureName,
			componentAnchors: componentAnchors,
			lineNumber: lineNum
		)
		
		return (ligature, linesConsumed)
	}
	
	// MARK: - Helper Parsers (UPDATED)
	
	/// Parse single semantic attachment: SEMANTIC <x, y>
	private static func parseSemanticAttachment(_ line: String, lineNumber: Int) throws -> (String, AnchorPoint) {
		let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
		
		guard parts.count >= 2 else {
			throw OT2AATError.invalidRule(
				"""
				Line \(lineNumber): Invalid attachment syntax
				Expected: SEMANTIC <x, y>
				Got: \(line)
				"""
			)
		}
		
		let semantic = parts[0]
		
		// Reconstruct anchor (may be split across parts)
		var anchorStr = ""
		for i in 1..<parts.count {
			anchorStr += parts[i]
			if parts[i].contains(">") {
				break
			}
			anchorStr += " "
		}
		
		let anchor = try AnchorPoint.parse(anchorStr)
		return (semantic, anchor)
	}
	
	/// Parse multiple semantic attachments: SEMANTIC1 <x, y>, SEMANTIC2 <x, y>
	private static func parseSemanticAttachments(_ line: String, lineNumber: Int) throws -> [String: AnchorPoint] {
		var attachments: [String: AnchorPoint] = [:]
		
		// Split by comma
		let parts = line.components(separatedBy: ",")
		
		for part in parts {
			let (semantic, anchor) = try parseSemanticAttachment(part.trimmingCharacters(in: .whitespaces), lineNumber: lineNumber)
			attachments[semantic] = anchor
		}
		
		return attachments
	}
	
	/// Parse rule element (glyph or @class)
	private static func parseRuleElement(_ string: String, lineNumber: Int) throws -> RuleElement {
		if string.hasPrefix("@") {
			let className = String(string.dropFirst())
			return .classRef(className)
		} else {
			return .glyph(string)
		}
	}
}
