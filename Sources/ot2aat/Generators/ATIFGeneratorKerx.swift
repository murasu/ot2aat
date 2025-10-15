import Foundation

struct ATIFGeneratorKerx {
	
	// MARK: - Main Entry Point
	
	/// Generate complete ATIF output for all mark positioning types
	static func generateMarkPositioning(
		rules: MarkPositioningRules,
		featureName: String,
		selectorNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "//\n"
		output += "//  Generated ATIF for mark positioning\n"
		output += "//  Feature: \(featureName), Selector: \(selectorNumber)\n"
		output += "//  Generated: \(Date())\n"
		output += "//\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		var tableNumber = 0
		
		// Table 0: Distance positioning (Type 0 - simple pairs)
		if !rules.distanceRules.isEmpty {
			output += try generateDistancePairs(
				rules: rules.distanceRules,
				glyphClasses: rules.glyphClasses,
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
		
		// Table 2+: Mark-to-base (one per mark group set)
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
		
		// Table 3+: Mark-to-mark (one per stacking relationship)
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
		
		// Table 4+: Mark-to-ligature (grouped by semantics)
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
		output += "// Table \(tableNumber): Distance kerning (simple pairs)\n"
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
		
		let isVertical = rules.first?.direction == .vertical
		
		output += "kerning list {\n"
		output += "    layout is \(isVertical ? "vertical" : "horizontal");\n"
		output += "    kerning is \(isVertical ? "vertical" : "horizontal");\n\n"
		
		for (context, target, value) in allPairs {
			output += "    \(context) + \(target) => \(value);\n"
		}
		
		output += "};\n"
		
		return output
	}
	
	// MARK: - Distance Positioning (Type 2) - UNCHANGED
	
	private static func generateDistanceMatrix(
		matrix: DistanceMatrix,
		tableNumber: Int
	) throws -> String {
		var output = ""
		
		output += "// " + String(repeating: "-", count: 79) + "\n"
		output += "// Table \(tableNumber): Distance kerning (class matrix)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "kerning matrix {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n\n"
		
		for leftClass in matrix.leftClasses {
			output += "    class \(leftClass) { /* glyphs */ };\n"
		}
		output += "\n"
		
		for rightClass in matrix.rightClasses {
			output += "    class \(rightClass) { /* glyphs */ };\n"
		}
		output += "\n"
		
		output += "    left classes { " + matrix.leftClasses.joined(separator: ", ") + " };\n"
		output += "    right classes { " + matrix.rightClasses.joined(separator: ", ") + " };\n\n"
		
		for (rightClass, leftClass, value) in matrix.adjustments {
			output += "    \(rightClass) + \(leftClass) => \(value);\n"
		}
		
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Mark-to-base positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "control point kerning subtable {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n"
		output += "    uses anchor points;\n"
		output += "    scan glyphs backward;\n\n"
		
		// Anchor definitions
		output += "    // Mark anchors (all use index [0])\n"
		for markGroup in markGroups {
			for (glyph, anchor) in markGroup.marks.sorted(by: { $0.key < $1.key }) {
				output += "    anchor \(glyph)[0] := \(anchor.formatted);\n"
			}
		}
		
		output += "\n    // Base anchors (sequential indices per semantic)\n"
		for base in bases {
			for semantic in orderedSemantics {
				guard let anchor = base.attachments[semantic],
					  let semanticIndex = orderedSemantics.firstIndex(of: semantic) else {
					continue
				}
				output += "    anchor \(base.glyph)[\(semanticIndex)] := \(anchor.formatted);\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseGlyphs = bases.map { $0.glyph }.sorted()
		output += "    class bases { " + baseGlyphs.joined(separator: ", ") + " };\n\n"
		
		for markGroup in markGroups {
			let className = "marks_\(markGroup.semantic)"
			output += "    class \(className) { " + markGroup.glyphNames.joined(separator: ", ") + " };\n"
		}
		output += "\n"
		
		// State machine
		output += "    state Start {\n"
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		output += "    state withBase {\n"
		for markGroup in markGroups {
			output += "        marks_\(markGroup.semantic): sawMark_\(markGroup.semantic);\n"
		}
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		// Transitions
		output += "    transition sawBase {\n"
		output += "        change state to withBase;\n"
		output += "        mark glyph;\n"
		output += "    };\n\n"
		
		for (index, markGroup) in markGroups.enumerated() {
			output += "    transition sawMark_\(markGroup.semantic) {\n"
			output += "        change state to withBase;\n"
			output += "        kerning action: snapMark_\(markGroup.semantic);\n"
			output += "    };\n"
			if index < markGroups.count - 1 {
				output += "\n"
			}
		}
		output += "\n"
		
		// Anchor actions
		for (index, markGroup) in markGroups.enumerated() {
			guard let semanticIndex = orderedSemantics.firstIndex(of: markGroup.semantic) else {
				continue
			}
			
			output += "    anchor point action snapMark_\(markGroup.semantic) {\n"
			output += "        marked glyph point: \(semanticIndex);\n"
			output += "        current glyph point: 0;\n"
			output += "    };\n"
			
			if index < markGroups.count - 1 {
				output += "\n"
			}
		}
		
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Mark-to-mark positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "control point kerning subtable {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n"
		output += "    uses anchor points;\n"
		output += "    scan glyphs backward;\n\n"
		
		// Determine which semantics are used
		var usedSemantics = Set<String>()
		for baseMark in baseMarks {
			for semantic in baseMark.attachments.keys {
				usedSemantics.insert(semantic)
			}
		}
		
		// Anchor definitions
		output += "    // Attaching mark anchors (use index [0])\n"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			for (glyph, anchor) in markGroup.marks.sorted(by: { $0.key < $1.key }) {
				output += "    anchor \(glyph)[0] := \(anchor.formatted);\n"
			}
		}
		
		// Base mark anchors use index after all mark groups
		let baseMarkIndex = markGroups.count
		output += "\n    // Base mark anchors (index [\(baseMarkIndex)])\n"
		for baseMark in baseMarks.sorted(by: { $0.mark < $1.mark }) {
			// Use first semantic's anchor (they should all have same attachment point)
			if let firstAnchor = baseMark.attachments.values.first {
				output += "    anchor \(baseMark.mark)[\(baseMarkIndex)] := \(firstAnchor.formatted);\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseMarkGlyphs = baseMarks.map { $0.mark }.sorted()
		output += "    class bases { " + baseMarkGlyphs.joined(separator: ", ") + " };\n\n"
		
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "    class marks_\(markGroup.semantic) { " + markGroup.glyphNames.joined(separator: ", ") + " };\n"
		}
		output += "\n"
		
		// State machine
		output += "    state Start {\n"
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		output += "    state withBase {\n"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "        marks_\(markGroup.semantic): sawMark;\n"
		}
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		// Transitions
		output += "    transition sawBase {\n"
		output += "        change state to withBase;\n"
		output += "        mark glyph;\n"
		output += "    };\n\n"
		
		output += "    transition sawMark {\n"
		output += "        change state to Start;\n"
		output += "        kerning action: snapMark;\n"
		output += "    };\n\n"
		
		// Anchor action (single action for all mark types)
		output += "    anchor point action snapMark {\n"
		output += "        marked glyph point: \(baseMarkIndex);\n"
		output += "        current glyph point: 0;\n"
		output += "    };\n"
		
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Mark-to-ligature positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "control point kerning subtable {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n"
		output += "    uses anchor points;\n"
		output += "    scan glyphs backward;\n\n"
		
		// Determine component count
		let componentCount = ligatures.compactMap { $0.componentCount }.max() ?? 0
		guard componentCount > 0 else {
			throw OT2AATError.generationFailed("No ligatures or components")
		}
		/*
		guard let firstLig = ligatures.first,
			  let componentCount = firstLig.componentCount else {
			throw OT2AATError.generationFailed("No ligatures or components")
		} */
		
		// Determine which semantics are used
		let usedSemantics = Set(ligatures.flatMap { $0.componentAnchors.keys })
		let usedOrderedSemantics = orderedSemantics.filter { usedSemantics.contains($0) }
		
		// Anchor definitions
		output += "    // Mark anchors (all use index [0])\n"
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			for (glyph, anchor) in markGroup.marks.sorted(by: { $0.key < $1.key }) {
				output += "    anchor \(glyph)[0] := \(anchor.formatted);\n"
			}
		}
		
		output += "\n    // Ligature component anchors\n"
		for ligature in ligatures.sorted(by: { $0.ligature < $1.ligature }) {
			for semantic in usedOrderedSemantics {
				guard let anchors = ligature.componentAnchors[semantic],
					  let semanticIndex = orderedSemantics.firstIndex(of: semantic) else {
					continue
				}
				
				for (compIndex, anchor) in anchors.enumerated() {
					// Anchor index = semanticIndex + (component * semanticCount)
					let anchorIndex = semanticIndex + (compIndex * usedOrderedSemantics.count)
					output += "    anchor \(ligature.ligature)[\(anchorIndex)] := \(anchor.formatted);\n"
				}
			}
		}
		output += "\n"
		
		// Class definitions
		let ligGlyphs = ligatures.map { $0.ligature }.sorted()
		output += "    class ligs { " + ligGlyphs.joined(separator: ", ") + " };\n\n"
		
		for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
			output += "    class marks_\(markGroup.semantic) { " + markGroup.glyphNames.joined(separator: ", ") + " };\n"
		}
		output += "\n"
		
		// State machine with DEL detection
		output += "    // States\n"
		output += "    state Start {\n"
		output += "        ligs: sawLig;\n"
		output += "    };\n\n"
		
		for comp in 0..<componentCount {
			let stateName = comp == 0 ? "SLig" : "SLig\(comp)"
			output += "    state \(stateName) {\n"
			
			if comp < componentCount - 1 {
				output += "        DEL: sawDel\(comp);\n"
			}
			output += "        ligs: sawLig;\n"
			
			for markGroup in markGroups where usedSemantics.contains(markGroup.semantic) {
				output += "        marks_\(markGroup.semantic): sawMark_\(markGroup.semantic)_comp\(comp);\n"
			}
			output += "    };\n\n"
		}
		
		// Transitions
		output += "    // Transitions\n"
		output += "    transition sawLig {\n"
		output += "        change state to SLig;\n"
		output += "        mark glyph;\n"
		output += "    };\n\n"
		
		// DEL transitions
		for comp in 0..<(componentCount - 1) {
			output += "    transition sawDel\(comp) {\n"
			output += "        change state to SLig\(comp + 1);\n"
			output += "    };\n\n"
		}
		
		// Mark transitions
		for comp in 0..<componentCount {
			let stateName = comp == 0 ? "SLig" : "SLig\(comp)"
			
			for (index, markGroup) in markGroups.enumerated() where usedSemantics.contains(markGroup.semantic) {
				output += "    transition sawMark_\(markGroup.semantic)_comp\(comp) {\n"
				output += "        change state to \(stateName);\n"
				output += "        kerning action: snapComp\(comp)_\(markGroup.semantic);\n"
				output += "    };\n"
				
				if !(comp == componentCount - 1 && index == markGroups.count - 1) {
					output += "\n"
				}
			}
		}
		output += "\n"
		
		// Anchor actions
		output += "    // Anchor actions\n"
		for comp in 0..<componentCount {
			for (index, markGroup) in markGroups.enumerated() where usedSemantics.contains(markGroup.semantic) {
				guard let semanticIndex = orderedSemantics.firstIndex(of: markGroup.semantic) else {
					continue
				}
				
				let ligAnchorIndex = semanticIndex + (comp * usedOrderedSemantics.count)
				
				output += "    anchor point action snapComp\(comp)_\(markGroup.semantic) {\n"
				output += "        marked glyph point: \(ligAnchorIndex);\n"
				output += "        current glyph point: 0;\n"
				output += "    };\n"
				
				if !(comp == componentCount - 1 && index == markGroups.count - 1) {
					output += "\n"
				}
			}
		}
		
		output += "};\n"
		
		return output
	}
}
