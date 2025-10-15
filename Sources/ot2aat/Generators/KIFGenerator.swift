import Foundation

struct KIFGenerator {
	
	// MARK: - Main Entry Point
	
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
		
		// Table 0: Distance positioning (Type 0)
		if !rules.distanceRules.isEmpty {
			output += try generateDistancePairs(
				rules: rules.distanceRules,
				glyphClasses: rules.glyphClasses, 
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 1: Distance matrices (Type 2)
		for matrix in rules.distanceMatrices {
			if tableNumber > 0 { output += "\n" }
			output += try generateDistanceMatrix(
				matrix: matrix,
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 2+: Mark-to-base
		if !rules.bases.isEmpty {
			if tableNumber > 0 { output += "\n" }
			output += try generateMark2Base(
				markGroups: rules.markGroups,
				bases: rules.bases,
				orderedSemantics: rules.orderedSemantics(),
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 3+: Mark-to-mark
		if !rules.baseMarks.isEmpty {
			if tableNumber > 0 { output += "\n" }
			output += try generateMark2Mark(
				markGroups: rules.markGroups,
				baseMarks: rules.baseMarks,
				orderedSemantics: rules.orderedSemantics(),
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		// Table 4+: Mark-to-ligature
		if !rules.ligatures.isEmpty {
			if tableNumber > 0 { output += "\n" }
			output += try generateMark2Ligature(
				markGroups: rules.markGroups,
				ligatures: rules.ligatures,
				orderedSemantics: rules.orderedSemantics(),
				tableNumber: tableNumber
			)
			tableNumber += 1
		}
		
		return output
	}
	
	// MARK: - Distance Positioning (Type 0) - UNCHANGED
	
	private static func generateDistancePairs(
		rules: [DistanceRule],
		glyphClasses: [GlyphClass],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Distance kerning (simple pairs)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		var registry = GlyphClassRegistry()
		for glyphClass in glyphClasses {
			try registry.register(glyphClass)
		}
		
		var allPairs: [(String, String, Int)] = []
		for rule in rules {
			let pairs = try rule.expand(using: registry)
			allPairs.append(contentsOf: pairs)
		}
		
		let orientation = rules.first?.direction == .vertical ? "V" : "H"
		
		output += "Type\t\t\t\tDistance\n"
		output += "Orientation\t\t\t\(orientation)\n"
		output += "Cross-stream\t\tno\n\n"
		
		output += "List\n"
		for (context, target, value) in allPairs {
			output += "\t\(context)\t\(target)\t\(value)\n"
		}
		
		return output
	}
	
	// MARK: - Distance Positioning (Type 2) - UNCHANGED
	
	private static func generateDistanceMatrix(
		matrix: DistanceMatrix,
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Distance kerning (class matrix)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "Type\t\t\t\tClassKerning\n"
		output += "Orientation\t\t\tH\n\n"
		
		for leftClass in matrix.leftClasses {
			output += "left\(leftClass)\t\t...\n"
		}
		output += "\n"
		
		for rightClass in matrix.rightClasses {
			output += "right\(rightClass)\t\t...\n"
		}
		output += "\n"
		
		output += "Matrix\n"
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL"
		for rightClass in matrix.rightClasses {
			output += "\t\(rightClass)"
		}
		output += "\n"
		
		for leftClass in matrix.leftClasses {
			output += "\(leftClass)\t\t0\t0\t0\t0"
			
			for rightClass in matrix.rightClasses {
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
	
	// MARK: - Mark-to-Base (Type 4) - REDESIGNED
	
	private static func generateMark2Base(
		markGroups: [MarkGroup],
		bases: [BaseGlyph],
		orderedSemantics: [String],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Mark-to-base positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "Type\t\t\t\tAttachment\n"
		output += "Orientation\t\t\tH\n"
		output += "PointType\t\t\tAnchorPoints\n"
		output += "Forward\t\t\t\tno\n\n"
		
		// Anchor definitions
		output += "// Mark anchors (all at index [0])\n"
		for markGroup in markGroups {
			for (glyph, anchor) in markGroup.marks.sorted(by: { $0.key < $1.key }) {
				output += "Anchor \(glyph)\t\t0\t\(anchor.x)\t\(anchor.y)\n"
			}
		}
		
		output += "\n// Base anchors (sequential indices)\n"
		for base in bases.sorted(by: { $0.glyph < $1.glyph }) {
			for semantic in orderedSemantics {
				guard let anchor = base.attachments[semantic],
					  let semanticIndex = orderedSemantics.firstIndex(of: semantic) else {
					continue
				}
				output += "Anchor \(base.glyph)\t\t\(semanticIndex)\t\(anchor.x)\t\(anchor.y)\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseGlyphs = bases.map { $0.glyph }.sorted()
		output += "bases\t\t\t\t" + baseGlyphs.joined(separator: " ") + "\n"
		
		for markGroup in markGroups {
			output += "marks_\(markGroup.semantic)\t\t" + markGroup.glyphNames.joined(separator: " ") + "\n"
		}
		output += "\n"
		
		// State array
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tbases"
		for markGroup in markGroups {
			output += "\tmarks_\(markGroup.semantic)"
		}
		output += "\n"
		
		output += "Start\t\t\t1\t1\t1\t1\t2"
		for _ in markGroups {
			output += "\t1"
		}
		output += "\n"
		
		output += "withBase\t\t1\t1\t2\t1\t2"
		for i in 0..<markGroups.count {
			output += "\t\(3 + i)"
		}
		output += "\n\n"
		
		// Entry table
		output += "\tGoTo\t\t\tMark?\tAdvance?\tMatchAnchors\n"
		output += "1\tStart\t\t\tno\t\tyes\t\t\tnone\n"
		output += "2\twithBase\t\tyes\t\tyes\t\t\tnone\n"
		
		for (i, markGroup) in markGroups.enumerated() {
			output += "\(3 + i)\twithBase\t\tno\t\tyes\t\t\tsnap_\(markGroup.semantic)\n"
		}
		output += "\n"
		
		// Anchor actions
		for (i, markGroup) in markGroups.enumerated() {
			guard let semanticIndex = orderedSemantics.firstIndex(of: markGroup.semantic) else {
				continue
			}
			
			output += "snap_\(markGroup.semantic)\n"
			output += "\tMarked\t\t\(semanticIndex)\n"
			output += "\tCurrent\t\t0\n"
			
			if i < markGroups.count - 1 {
				output += "\n"
			}
		}
		
		return output
	}
	
	// MARK: - Mark-to-Mark (Type 4) - REDESIGNED
	
	private static func generateMark2Mark(
		markGroups: [MarkGroup],
		baseMarks: [BaseMarkGlyph],
		orderedSemantics: [String],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Mark-to-mark positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "Type\t\t\t\tAttachment\n"
		output += "Orientation\t\t\tH\n"
		output += "PointType\t\t\tAnchorPoints\n"
		output += "Forward\t\t\t\tno\n\n"
		
		// Determine used semantics
		var usedSemantics = Set<String>()
		for baseMark in baseMarks {
			for semantic in baseMark.attachments.keys {
				usedSemantics.insert(semantic)
			}
		}
		
		// Anchor definitions
		output += "// Attaching mark anchors (at index [0])\n"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			for (glyph, anchor) in markGroup.marks.sorted(by: { $0.key < $1.key }) {
				output += "Anchor \(glyph)\t\t0\t\(anchor.x)\t\(anchor.y)\n"
			}
		}
		
		let baseMarkIndex = markGroups.count
		output += "\n// Base mark anchors (at index [\(baseMarkIndex)])\n"
		for baseMark in baseMarks.sorted(by: { $0.mark < $1.mark }) {
			if let firstAnchor = baseMark.attachments.values.first {
				output += "Anchor \(baseMark.mark)\t\t\(baseMarkIndex)\t\(firstAnchor.x)\t\(firstAnchor.y)\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseMarkGlyphs = baseMarks.map { $0.mark }.sorted()
		output += "bases\t\t\t\t" + baseMarkGlyphs.joined(separator: " ") + "\n"
		
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "marks_\(markGroup.semantic)\t\t" + markGroup.glyphNames.joined(separator: " ") + "\n"
		}
		output += "\n"
		
		// State array
		let usedMarkGroupsCount = markGroups.filter { usedSemantics.contains($0.semantic) }.count
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tbases"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "\tmarks_\(markGroup.semantic)"
		}
		output += "\n"
		
		output += "Start\t\t\t1\t1\t1\t1\t2"
		for _ in 0..<usedMarkGroupsCount {
			output += "\t1"
		}
		output += "\n"
		
		output += "withBase\t\t1\t1\t2\t1\t2"
		for i in 0..<usedMarkGroupsCount {
			output += "\t\(3 + i)"
		}
		output += "\n\n"
		
		// Entry table
		output += "\tGoTo\t\t\tMark?\tAdvance?\tMatchAnchors\n"
		output += "1\tStart\t\t\tno\t\tyes\t\t\tnone\n"
		output += "2\twithBase\t\tyes\t\tyes\t\t\tnone\n"
		
		for i in 0..<usedMarkGroupsCount {
			output += "\(3 + i)\tStart\t\t\tno\t\tyes\t\t\tsnapMark\n"
		}
		output += "\n"
		
		// Anchor action (single action for all)
		output += "snapMark\n"
		output += "\tMarked\t\t\(baseMarkIndex)\n"
		output += "\tCurrent\t\t0\n"
		
		return output
	}
	
	// MARK: - Mark-to-Ligature (Type 4) - REDESIGNED
	
	private static func generateMark2Ligature(
		markGroups: [MarkGroup],
		ligatures: [LigatureGlyph],
		orderedSemantics: [String],
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// TABLE \(tableNumber): Mark-to-ligature positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "Type\t\t\t\tAttachment\n"
		output += "Orientation\t\t\tH\n"
		output += "PointType\t\t\tAnchorPoints\n"
		output += "Forward\t\t\t\tno\n\n"
		
		guard let firstLig = ligatures.first,
			  let componentCount = firstLig.componentCount else {
			throw OT2AATError.generationFailed("No ligatures or components")
		}
		
		let usedSemantics = Set(ligatures.flatMap { $0.componentAnchors.keys })
		let usedOrderedSemantics = orderedSemantics.filter { usedSemantics.contains($0) }
		
		// Anchor definitions
		output += "// Mark anchors (at index [0])\n"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			for (glyph, anchor) in markGroup.marks.sorted(by: { $0.key < $1.key }) {
				output += "Anchor \(glyph)\t\t0\t\(anchor.x)\t\(anchor.y)\n"
			}
		}
		
		output += "\n// Ligature component anchors\n"
		for ligature in ligatures.sorted(by: { $0.ligature < $1.ligature }) {
			for semantic in usedOrderedSemantics {
				guard let anchors = ligature.componentAnchors[semantic],
					  let semanticIndex = orderedSemantics.firstIndex(of: semantic) else {
					continue
				}
				
				for (compIndex, anchor) in anchors.enumerated() {
					let anchorIndex = semanticIndex + (compIndex * usedOrderedSemantics.count)
					output += "Anchor \(ligature.ligature)\t\t\(anchorIndex)\t\(anchor.x)\t\(anchor.y)\n"
				}
			}
		}
		output += "\n"
		
		// Class definitions
		let ligGlyphs = ligatures.map { $0.ligature }.sorted()
		output += "ligs\t\t\t\t" + ligGlyphs.joined(separator: " ") + "\n"
		
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "marks_\(markGroup.semantic)\t\t" + markGroup.glyphNames.joined(separator: " ") + "\n"
		}
		output += "\n"
		
		// State array
		output += "// State array\n"
		output += "\t\t\t\tEOT\tOOB\tDEL\tEOL\tligs"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "\tmarks_\(markGroup.semantic)"
		}
		output += "\n"
		
		output += "Start\t\t\t1\t1\t1\t1\t2"
		for _ in markGroups.filter({ usedSemantics.contains($0.semantic) }) {
			output += "\t1"
		}
		output += "\n"
		
		// Component states
		for comp in 0..<componentCount {
			let stateName = comp == 0 ? "SLig" : "SLig\(comp)"
			let delTransition = comp < componentCount - 1 ? "\(3 + comp * (usedOrderedSemantics.count + 1))" : "1"
			
			output += "\(stateName)\t\t\t1\t1\t\(delTransition)\t1\t2"
			
			for i in 0..<usedOrderedSemantics.count {
				let markTransition = 4 + comp * (usedOrderedSemantics.count + 1) + i
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
			for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
				let currentState = comp == 0 ? "SLig" : "SLig\(comp)"
				output += "\(entryNum)\t\(currentState)\t\tno\t\tyes\t\t\tsnap\(comp)_\(markGroup.semantic)\n"
				entryNum += 1
			}
		}
		output += "\n"
		
		// Anchor actions
		for comp in 0..<componentCount {
			for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
				guard let semanticIndex = orderedSemantics.firstIndex(of: markGroup.semantic) else {
					continue
				}
				
				let ligAnchorIndex = semanticIndex + (comp * usedOrderedSemantics.count)
				
				output += "snap\(comp)_\(markGroup.semantic)\n"
				output += "\tMarked\t\t\(ligAnchorIndex)\n"
				output += "\tCurrent\t\t0\n"
				
				if !(comp == componentCount - 1 && markGroup.semantic == usedOrderedSemantics.last) {
					output += "\n"
				}
			}
		}
		
		return output
	}
}
