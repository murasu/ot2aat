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
		output += "// Table \(tableNumber): Distance kerning (simple pairs)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		// Expand all rules to glyph pairs
		let registry = GlyphClassRegistry()
		var allPairs: [(String, String, Int)] = []
		
		for rule in rules {
			let pairs = try rule.expand(using: registry)
			allPairs.append(contentsOf: pairs)
		}
		
		// Determine orientation
		let isVertical = rules.first?.direction == .vertical
		
		output += "kerning list {\n"
		output += "    layout is \(isVertical ? "vertical" : "horizontal");\n"
		output += "    kerning is \(isVertical ? "vertical" : "horizontal");\n\n"
		
		// List of pairs
		for (context, target, value) in allPairs {
			output += "    \(context) + \(target) => \(value);\n"
		}
		
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Distance kerning (class matrix)\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "kerning matrix {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n\n"
		
		// Class definitions (need to get actual glyphs - for now placeholder)
		for leftClass in matrix.leftClasses {
			output += "    class \(leftClass) { /* glyphs */ };\n"
		}
		output += "\n"
		
		for rightClass in matrix.rightClasses {
			output += "    class \(rightClass) { /* glyphs */ };\n"
		}
		output += "\n"
		
		// Declare which classes are used
		output += "    left classes { " + matrix.leftClasses.joined(separator: ", ") + " };\n"
		output += "    right classes { " + matrix.rightClasses.joined(separator: ", ") + " };\n\n"
		
		// Adjustments
		for (rightClass, leftClass, value) in matrix.adjustments {
			output += "    \(rightClass) + \(leftClass) => \(value);\n"
		}
		
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Mark-to-base positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "control point kerning subtable {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n"
		output += "    uses anchor points;\n"
		output += "    scan glyphs backward;\n\n"
		
		// Mark anchors
		output += "    // Mark anchors\n"
		for (index, markClass) in markClasses.enumerated() {
			for mark in markClass.marks {
				output += "    anchor \(mark)[\(index)] := \(markClass.anchor.formatted);\n"
			}
		}
		
		output += "\n    // Base anchors\n"
		for base in bases {
			for (markClassName, anchor) in base.attachments.sorted(by: { $0.key < $1.key }) {
				guard let index = markClasses.firstIndex(where: { $0.name == markClassName }) else {
					throw OT2AATError.generationFailed("Mark class '\(markClassName)' not found")
				}
				output += "    anchor \(base.glyph)[\(index)] := \(anchor.formatted);\n"
			}
		}
		output += "\n"
		
		// Class definitions
		let baseGlyphs = bases.map { $0.glyph }.sorted()
		output += "    class bases { " + baseGlyphs.joined(separator: ", ") + " };\n\n"
		
		for (index, markClass) in markClasses.enumerated() {
			let className = index == 0 ? "marksTop" : (index == 1 ? "marksBot" : "marks\(index)")
			output += "    class \(className) { " + markClass.marks.joined(separator: ", ") + " };\n"
		}
		output += "\n"
		
		// State definitions
		output += "    state Start {\n"
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		output += "    state withBase {\n"
		for (index, _) in markClasses.enumerated() {
			let className = index == 0 ? "marksTop" : (index == 1 ? "marksBot" : "marks\(index)")
			let transitionName = index == 0 ? "sawMarkTop" : (index == 1 ? "sawMarkBot" : "sawMark\(index)")
			output += "        \(className): \(transitionName);\n"
		}
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		// Transitions
		output += "    transition sawBase {\n"
		output += "        change state to withBase;\n"
		output += "        mark glyph;\n"
		output += "    };\n\n"
		
		for (index, _) in markClasses.enumerated() {
			let transitionName = index == 0 ? "sawMarkTop" : (index == 1 ? "sawMarkBot" : "sawMark\(index)")
			let actionName = index == 0 ? "snapMarkTop" : (index == 1 ? "snapMarkBot" : "snapMark\(index)")
			
			output += "    transition \(transitionName) {\n"
			output += "        change state to withBase;\n"
			output += "        kerning action: \(actionName);\n"
			output += "    };\n"
			
			if index < markClasses.count - 1 {
				output += "\n"
			}
		}
		output += "\n"
		
		// Anchor actions
		for (index, _) in markClasses.enumerated() {
			let actionName = index == 0 ? "snapMarkTop" : (index == 1 ? "snapMarkBot" : "snapMark\(index)")
			
			output += "    anchor point action \(actionName) {\n"
			output += "        marked glyph point: \(index);\n"
			output += "        current glyph point: \(index);\n"
			output += "    };\n"
			
			if index < markClasses.count - 1 {
				output += "\n"
			}
		}
		
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Mark-to-mark positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "control point kerning subtable {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n"
		output += "    uses anchor points;\n"
		output += "    scan glyphs backward;\n\n"
		
		// Determine which mark classes are used
		var usedMarkClasses = Set<String>()
		for baseMark in baseMarks {
			for markClassName in baseMark.attachments.keys {
				usedMarkClasses.insert(markClassName)
			}
		}
		
		// Mark anchors (attaching marks)
		output += "    // Attaching mark anchors\n"
		let baseMarkIndex = markClasses.count  // Base mark anchors start after all mark class indices
		
		for (index, markClass) in markClasses.enumerated() {
			if usedMarkClasses.contains(markClass.name) {
				for mark in markClass.marks {
					output += "    anchor \(mark)[\(index)] := \(markClass.anchor.formatted);\n"
				}
			}
		}
		
		output += "\n    // Base mark anchors\n"
		for baseMark in baseMarks {
			for (_, anchor) in baseMark.attachments.sorted(by: { $0.key < $1.key }) {
				output += "    anchor \(baseMark.mark)[\(baseMarkIndex)] := \(anchor.formatted);\n"
				break  // Only one attachment point per base mark (they can have multiple mark classes but same index)
			}
		}
		output += "\n"
		
		// Class definitions
		let baseMarkGlyphs = baseMarks.map { $0.mark }.sorted()
		output += "    class bases { " + baseMarkGlyphs.joined(separator: ", ") + " };\n\n"
		
		var classIndex = 0
		for markClass in markClasses {
			if usedMarkClasses.contains(markClass.name) {
				let className = classIndex == 0 ? "marks" : "marks\(classIndex)"
				output += "    class \(className) { " + markClass.marks.joined(separator: ", ") + " };\n"
				classIndex += 1
			}
		}
		output += "\n"
		
		// State definitions
		output += "    state Start {\n"
		output += "        bases: sawBase;\n"
		output += "    };\n\n"
		
		output += "    state withBase {\n"
		let markCount = usedMarkClasses.count
		for i in 0..<markCount {
			let className = i == 0 ? "marks" : "marks\(i)"
			output += "        \(className): sawMark;\n"
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
		
		// Anchor action
		output += "    anchor point action snapMark {\n"
		output += "        marked glyph point: \(baseMarkIndex);\n"
		
		// Use first mark class index (they all stack the same way)
		if let firstUsedMarkClass = markClasses.first(where: { usedMarkClasses.contains($0.name) }),
		   let firstIndex = markClasses.firstIndex(where: { $0.name == firstUsedMarkClass.name }) {
			output += "        current glyph point: \(firstIndex);\n"
		}
		
		output += "    };\n"
		output += "};\n"
		
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
		output += "// Table \(tableNumber): Mark-to-ligature positioning\n"
		output += "// " + String(repeating: "-", count: 79) + "\n\n"
		
		output += "control point kerning subtable {\n"
		output += "    layout is horizontal;\n"
		output += "    kerning is horizontal;\n"
		output += "    uses anchor points;\n"
		output += "    scan glyphs backward;\n\n"
		
		// Determine max component count
		guard let firstLig = ligatures.first,
			  let componentCount = firstLig.componentCount else {
			throw OT2AATError.generationFailed("No ligatures or components")
		}
		
		// Mark anchors
		output += "    // Mark anchors\n"
		var markClassIndices: [String: Int] = [:]
		
		for markClass in markClasses {
			if markClassNames.contains(markClass.name) {
				let index = markClasses.firstIndex(where: { $0.name == markClass.name })!
				markClassIndices[markClass.name] = index
				
				for mark in markClass.marks {
					output += "    anchor \(mark)[\(index)] := \(markClass.anchor.formatted);\n"
				}
			}
		}
		
		output += "\n    // Ligature component anchors\n"
		for ligature in ligatures {
			for markClassName in markClassNames.sorted() {
				guard let anchors = ligature.componentAnchors[markClassName],
					  let baseIndex = markClassIndices[markClassName] else {
					continue
				}
				
				for (compIndex, anchor) in anchors.enumerated() {
					// Calculate anchor index for this component
					// Component 1 uses base indices (0, 1, ...)
					// Component 2 uses next set (2, 3, ...)
					let anchorIndex = baseIndex + (compIndex * markClassNames.count)
					output += "    anchor \(ligature.ligature)[\(anchorIndex)] := \(anchor.formatted);\n"
				}
			}
		}
		output += "\n"
		
		// Class definitions
		let ligGlyphs = ligatures.map { $0.ligature }.sorted()
		output += "    class ligs { " + ligGlyphs.joined(separator: ", ") + " };\n\n"
		
		for markClassName in markClassNames {
			if let markClass = markClasses.first(where: { $0.name == markClassName }) {
				output += "    class marks_\(markClassName) { " + markClass.marks.joined(separator: ", ") + " };\n"
			}
		}
		output += "\n"
		
		// State machine with DEL detection
		output += "    // States\n"
		output += "    state Start {\n"
		output += "        ligs: sawLig;\n"
		output += "    };\n\n"
		
		// Generate states for each component
		for comp in 0..<componentCount {
			let stateName = comp == 0 ? "SLig" : "SLig\(comp)"
			
			output += "    state \(stateName) {\n"
			
			if comp < componentCount - 1 {
				output += "        DEL: sawLigDel\(comp);\n"
			}
			
			output += "        ligs: sawLig;\n"
			
			for (i, markClassName) in markClassNames.enumerated() {
				output += "        marks_\(markClassName): sawMarkComp\(comp)_\(i);\n"
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
			let nextState = "SLig\(comp + 1)"
			output += "    transition sawLigDel\(comp) {\n"
			output += "        change state to \(nextState);\n"
			output += "    };\n\n"
		}
		
		// Mark transitions
		for comp in 0..<componentCount {
			let currentState = comp == 0 ? "SLig" : "SLig\(comp)"
			
			for (i, _) in markClassNames.enumerated() {
				output += "    transition sawMarkComp\(comp)_\(i) {\n"
				output += "        change state to \(currentState);\n"
				output += "        kerning action: snapComp\(comp)Mark\(i);\n"
				output += "    };\n"
				
				if !(comp == componentCount - 1 && i == markClassNames.count - 1) {
					output += "\n"
				}
			}
			
			if comp < componentCount - 1 {
				output += "\n"
			}
		}
		output += "\n"
		
		// Anchor actions
		output += "    // Anchor actions\n"
		for comp in 0..<componentCount {
			for (i, markClassName) in markClassNames.enumerated() {
				guard let markClassIndex = markClassIndices[markClassName] else { continue }
				
				let ligAnchorIndex = markClassIndex + (comp * markClassNames.count)
				
				output += "    anchor point action snapComp\(comp)Mark\(i) {\n"
				output += "        marked glyph point: \(ligAnchorIndex);\n"
				output += "        current glyph point: \(markClassIndex);\n"
				output += "    };\n"
				
				if !(comp == componentCount - 1 && i == markClassNames.count - 1) {
					output += "\n"
				}
			}
			
			if comp < componentCount - 1 {
				output += "\n"
			}
		}
		
		output += "};\n"
		
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
