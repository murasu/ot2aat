import Foundation

struct KIFGenerator {
	
	// MARK: - Main Entry Point
	
	/// Generate complete KIF output for all mark positioning types
	static func generateMarkPositioning(
		rules: MarkPositioningRules,
		featureName: String,
		selectorNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "//\n"
		output += "//  Generated KIF for mark positioning\n"
		output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
		output += "//  Generated: \(Date())\n"
		output += "//\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		var tableNumber = 0
		
		// Table 0: Distance positioning (Type 0 - simple pairs)
		if !rules.distanceRules.isEmpty {
			//if tableNumber > 0 { output += "\n" }
			output += try generateDistancePairs(
				rules: rules.distanceRules,
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 1: Distance positioning (Type 2 - class matrix)
		for matrix in rules.distanceMatrices {
			if tableNumber > 0 { output += "\n" }
			output += try generateDistanceMatrix(
				matrix: matrix,
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 2+: Mark-to-base (one per mark class set)
		if !rules.bases.isEmpty {
			if tableNumber > 0 { output += "\n" }
			output += try generateMark2Base(
				markClasses: rules.markClasses,
				bases: rules.bases,
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 3+: Mark-to-mark (one per stacking relationship)
		if !rules.baseMarks.isEmpty {
			if tableNumber > 0 { output += "\n" }
			output += try generateMark2Mark(
				markClasses: rules.markClasses,
				baseMarks: rules.baseMarks,
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 4+: Mark-to-ligature (grouped by mark classes)
		let ligatureGroups = groupLigaturesByMarkClasses(rules.ligatures)
		for group in ligatureGroups {
			if tableNumber > 0 { output += "\n" }
			output += try generateMark2Ligature(
				markClasses: rules.markClasses,
				ligatures: group.ligatures,
				markClassNames: group.markClassNames,
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		return output
	}
	
	// MARK: - Distance Positioning (Type 0)
	
	/// Generate Type 0 distance kerning (simple pairs)
	private static func generateDistancePairs(
		rules: [DistanceRule],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Distance kerning (simple pairs)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		// Expand all rules to glyph pairs
		let registry = GlyphClassRegistry()
		var allPairs: [(String, String, Int)] = []
		
		for rule in rules {
			let pairs = try rule.expand(using: registry)
			allPairs.append(contentsOf: pairs)
		}
		
		// Determine orientation (use first rule's direction)
		let orientation = rules.first?.direction == .vertical ? "V" : "H"
		
		// Header
		output += "Type\t\t\t\tDistance\n"
		output += "Orientation\t\t\t\(orientation)\n"
		output += "Cross-stream\t\tno\n\n"
		
		// List of pairs
		output += "List\n"
		for (context, target, value) in allPairs {
			output += "\t\(context)\t\(target)\t\(value)\n"
		}
		
		return output
	}
	
	// MARK: - Distance Positioning (Type 2)
	
	/// Generate Type 2 class-based distance matrix
	private static func generateDistanceMatrix(
		matrix: DistanceMatrix,
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Distance kerning (class matrix)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		// Header
		output += "Type\t\t\t\tClassKerning\n"
		output += "Orientation\t\t\tH\n\n"
		
		// Left classes
		for leftClass in matrix.leftClasses {
			output += "left\(leftClass)\t\t...\n"  // Placeholder - needs glyph list
		}
		output += "\n"
		
		// Right classes
		for rightClass in matrix.rightClasses {
			output += "right\(rightClass)\t\t...\n"  // Placeholder
		}
		output += "\n"
		
		// Matrix header
		output += "Matrix\n"
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL"
		for rightClass in matrix.rightClasses {
			output += "\t\(rightClass)"
		}
		output += "\n"
		
		// Matrix rows
		for leftClass in matrix.leftClasses {
			output += "\(leftClass)\t\t0\t0\t0\t0"
			
			for rightClass in matrix.rightClasses {
				// Find adjustment for this pair
				var value = 0
				for (adjRight, adjLeft, adjValue) in matrix.adjustments {
					if adjRight == rightClass && adjLeft == leftClass {
						value = adjValue
						break
					}
				}
				output += "\t\(value)"
			}
			output += "\n"
		}
		
		return output
	}
	
	// MARK: - Mark-to-Base (Type 4)
	
	/// Generate Type 4 attachment for mark-to-base
	private static func generateMark2Base(
		markClasses: [MarkClass],
		bases: [BaseGlyph],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Mark-to-base positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		// Header
		output += "Type\t\t\t\tAttachment\n"
		output += "Orientation\t\t\tH\n"
		output += "PointType\t\t\tAnchorPoints\n"
		output += "Forward\t\t\t\tno\n\n"
		
		// Anchor definitions
		output += "// Mark anchors\n"
		for (index, markClass) in markClasses.enumerated() {
			for mark in markClass.marks {
				output += "Anchor \(mark)\t\t\(index)\t\(markClass.anchor.x)\t\(markClass.anchor.y)\n"
			}
		}
		
		output += "\n// Base anchors\n"
		for base in bases {
			for (markClassName, anchor) in base.attachments.sorted(by: { $0.key < $1.key }) {
				// Find mark class index
				guard let index = markClasses.firstIndex(where: { $0.name == markClassName }) else {
					throw OT2AATError.generationFailed("Mark class '\(markClassName)' not found")
				}
				output += "Anchor \(base.glyph)\t\t\(index)\t\(anchor.x)\t\(anchor.y)\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseGlyphs = bases.map { $0.glyph }.sorted()
		output += "class bases\t\t" + baseGlyphs.joined(separator: " ") + "\n"
		
		for (index, markClass) in markClasses.enumerated() {
			let className = "marks\(index)"
			output += "class \(className)\t\t" + markClass.marks.joined(separator: " ") + "\n"
		}
		output += "\n"
		
		// State array
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tbases"
		for i in 0..<markClasses.count {
			output += "\tmarks\(i)"
		}
		output += "\n"
		
		output += "Start\t\t\t1\t1\t1\t1\t2"
		for _ in 0..<markClasses.count {
			output += "\t1"
		}
		output += "\n"
		
		output += "withBase\t\t1\t1\t2\t1\t2"
		for i in 0..<markClasses.count {
			output += "\t\(3 + i)"
		}
		output += "\n\n"
		
		// Entry table
		output += "\tGoTo\t\t\tMark?\tAdvance?\tMatchAnchors\n"
		output += "1\tStart\t\t\tno\t\tyes\t\t\tnone\n"
		output += "2\twithBase\t\tyes\t\tyes\t\t\tnone\n"
		
		for i in 0..<markClasses.count {
			output += "\(3 + i)\twithBase\t\tno\t\tyes\t\t\tsnapMark\(i)\n"
		}
		output += "\n"
		
		// Anchor actions
		for i in 0..<markClasses.count {
			output += "snapMark\(i)\n"
			output += "\tMarked\t\t\(i)\n"
			output += "\tCurrent\t\t\(i)\n"
			if i < markClasses.count - 1 {
				output += "\n"
			}
		}
		
		return output
	}
	
	// MARK: - Mark-to-Mark (Type 4)
	
	/// Generate Type 4 attachment for mark-to-mark
	private static func generateMark2Mark(
		markClasses: [MarkClass],
		baseMarks: [BaseMarkGlyph],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Mark-to-mark positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		// Header
		output += "Type\t\t\t\tAttachment\n"
		output += "Orientation\t\t\tH\n"
		output += "PointType\t\t\tAnchorPoints\n"
		output += "Forward\t\t\t\tno\n\n"
		
		// Determine which mark classes are used as attaching marks
		var usedMarkClasses = Set<String>()
		for baseMark in baseMarks {
			for markClassName in baseMark.attachments.keys {
				usedMarkClasses.insert(markClassName)
			}
		}
		
		// Anchor definitions for attaching marks
		output += "// Attaching mark anchors\n"
		let nextIndex = markClasses.count  // Base mark anchors start after mark class indices
		
		for (index, markClass) in markClasses.enumerated() {
			if usedMarkClasses.contains(markClass.name) {
				for mark in markClass.marks {
					output += "Anchor \(mark)\t\t\(index)\t\(markClass.anchor.x)\t\(markClass.anchor.y)\n"
				}
			}
		}
		
		output += "\n// Base mark anchors\n"
		for baseMark in baseMarks {
			for (_, anchor) in baseMark.attachments.sorted(by: { $0.key < $1.key }) {
				output += "Anchor \(baseMark.mark)\t\t\(nextIndex)\t\(anchor.x)\t\(anchor.y)\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseMarkGlyphs = baseMarks.map { $0.mark }.sorted()
		output += "class bases\t\t" + baseMarkGlyphs.joined(separator: " ") + "\n"
		
		var markClassIndex = 0
		for markClass in markClasses {
			if usedMarkClasses.contains(markClass.name) {
				output += "class marks\(markClassIndex)\t\t" + markClass.marks.joined(separator: " ") + "\n"
				markClassIndex += 1
			}
		}
		output += "\n"
		
		// State array
		let markClassCount = usedMarkClasses.count
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tbases"
		for i in 0..<markClassCount {
			output += "\tmarks\(i)"
		}
		output += "\n"
		
		output += "Start\t\t\t1\t1\t1\t1\t2"
		for _ in 0..<markClassCount {
			output += "\t1"
		}
		output += "\n"
		
		output += "withBase\t\t1\t1\t2\t1\t2"
		for i in 0..<markClassCount {
			output += "\t\(3 + i)"
		}
		output += "\n\n"
		
		// Entry table
		output += "\tGoTo\t\t\tMark?\tAdvance?\tMatchAnchors\n"
		output += "1\tStart\t\t\tno\t\tyes\t\t\tnone\n"
		output += "2\twithBase\t\tyes\t\tyes\t\t\tnone\n"
		
		for i in 0..<markClassCount {
			output += "\(3 + i)\tStart\t\t\tno\t\tyes\t\t\tsnapMark\(i)\n"
		}
		output += "\n"
		
		// Anchor actions
		for i in 0..<markClassCount {
			output += "snapMark\(i)\n"
			output += "\tMarked\t\t\(nextIndex)\n"
			output += "\tCurrent\t\t\(i)\n"
			if i < markClassCount - 1 {
				output += "\n"
			}
		}
		
		return output
	}
	
	// MARK: - Mark-to-Ligature (Type 4)
	
	/// Generate Type 4 attachment for mark-to-ligature
	private static func generateMark2Ligature(
		markClasses: [MarkClass],
		ligatures: [LigatureGlyph],
		markClassNames: [String],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Mark-to-ligature positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		// Header
		output += "Type\t\t\t\tAttachment\n"
		output += "Orientation\t\t\tH\n"
		output += "PointType\t\t\tAnchorPoints\n"
		output += "Forward\t\t\t\tno\n\n"
		
		// Determine max component count
		guard let firstLig = ligatures.first,
			  let componentCount = firstLig.componentCount else {
			throw OT2AATError.generationFailed("No ligatures or components")
		}
		
		// Anchor definitions for marks
		output += "// Mark anchors\n"
		var markClassIndices: [String: Int] = [:]
		for (index, markClass) in markClasses.enumerated() {
			if markClassNames.contains(markClass.name) {
				markClassIndices[markClass.name] = index
				for mark in markClass.marks {
					output += "Anchor \(mark)\t\t\(index)\t\(markClass.anchor.x)\t\(markClass.anchor.y)\n"
				}
			}
		}
		
		output += "\n// Ligature component anchors\n"
		for ligature in ligatures {
			for markClassName in markClassNames.sorted() {
				guard let anchors = ligature.componentAnchors[markClassName],
					  let baseIndex = markClassIndices[markClassName] else {
					continue
				}
				
				for (compIndex, anchor) in anchors.enumerated() {
					let anchorIndex = baseIndex + (compIndex * markClassNames.count)
					output += "Anchor \(ligature.ligature)\t\t\(anchorIndex)\t\(anchor.x)\t\(anchor.y)\n"
				}
			}
		}
		output += "\n"
		
		// Class definitions
		let ligGlyphs = ligatures.map { $0.ligature }.sorted()
		output += "class ligs\t\t" + ligGlyphs.joined(separator: " ") + "\n"
		
		for markClassName in markClassNames {
			if let markClass = markClasses.first(where: { $0.name == markClassName }) {
				output += "class marks_\(markClassName)\t\t" + markClass.marks.joined(separator: " ") + "\n"
			}
		}
		output += "\n"
		
		// State machine with DEL detection for components
		output += "// State array\n"
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tligs"
		for markClassName in markClassNames {
			output += "\tmarks_\(markClassName)"
		}
		output += "\n"
		
		output += "Start\t\t\t1\t1\t1\t1\t2"
		for _ in markClassNames {
			output += "\t1"
		}
		output += "\n"
		
		// Generate states for each component
		for comp in 0..<componentCount {
			let stateName = comp == 0 ? "SLig" : "SLig\(comp)"
			//let nextState = comp < componentCount - 1 ? "SLig\(comp + 1)" : "Start"
			let delTransition = comp < componentCount - 1 ? "\(3 + comp * (markClassNames.count + 1))" : "1"
			
			output += "\(stateName)\t\t\t1\t1\t\(delTransition)\t1\t2"
			
			for i in 0..<markClassNames.count {
				let markTransition = 4 + comp * (markClassNames.count + 1) + i
				output += "\t\(markTransition)"
			}
			output += "\n"
		}
		output += "\n"
		
		// Entry table
		output += "\tGoTo\t\t\tMark?\tAdvance?\tMatchAnchors\n"
		output += "1\tStart\t\t\tno\t\tyes\t\t\tnone\n"
		output += "2\tSLig\t\t\tyes\t\tyes\t\t\tnone\n"
		
		var entryNum = 3
		for comp in 0..<componentCount {
			let nextState = comp < componentCount - 1 ? "SLig\(comp + 1)" : "Start"
			
			// DEL transition
			output += "\(entryNum)\t\(nextState)\t\tno\t\tyes\t\t\tnone\n"
			entryNum += 1
			
			// Mark transitions
			for i in 0..<markClassNames.count {
				let currentState = comp == 0 ? "SLig" : "SLig\(comp)"
				output += "\(entryNum)\t\(currentState)\t\tno\t\tyes\t\t\tsnapComp\(comp)Mark\(i)\n"
				entryNum += 1
			}
		}
		output += "\n"
		
		// Anchor actions
		for comp in 0..<componentCount {
			for (i, markClassName) in markClassNames.enumerated() {
				guard let markClassIndex = markClassIndices[markClassName] else { continue }
				
				let ligAnchorIndex = markClassIndex + (comp * markClassNames.count)
				
				output += "snapComp\(comp)Mark\(i)\n"
				output += "\tMarked\t\t\(ligAnchorIndex)\n"
				output += "\tCurrent\t\t\(markClassIndex)\n"
				if !(comp == componentCount - 1 && i == markClassNames.count - 1) {
					output += "\n"
				}
			}
		}
		
		return output
	}
	
	// MARK: - Helper Functions
	
	/// Group ligatures by which mark classes they use
	private static func groupLigaturesByMarkClasses(_ ligatures: [LigatureGlyph]) -> [(markClassNames: [String], ligatures: [LigatureGlyph])] {
		var groups: [Set<String>: [LigatureGlyph]] = [:]
		
		for ligature in ligatures {
			let markClassSet = Set(ligature.componentAnchors.keys)
			if groups[markClassSet] != nil {
				groups[markClassSet]?.append(ligature)
			} else {
				groups[markClassSet] = [ligature]
			}
		}
		
		return groups.map { (markClassNames: Array($0.key).sorted(), ligatures: $0.value) }
	}
}
