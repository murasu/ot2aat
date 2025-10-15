import Foundation
import ArgumentParser

struct MarkPosCommand: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "markpos",
		abstract: "Generate mark positioning rules (mark-to-base, mark-to-mark, mark-to-ligature, distance adjustments)"
	)
	
	@Flag(name: .long, help: "Generate ATIF format output")
	var atif: Bool = false
	
	@Flag(name: .long, help: "Generate KIF/MIF format output")
	var mif: Bool = false
	
	@Option(name: [.short, .long], help: "Input rules file")
	var input: String
	
	@Option(name: [.short, .long], help: "Output file (default: stdout)")
	var output: String?
	
	@Option(name: [.short, .long], help: "Feature name")
	var feature: String
	
	@Option(name: .long, help: "Selector number")
	var selector: Int
	
	mutating func validate() throws {
		// Must specify exactly one output format
		guard atif != mif else {
			if !atif && !mif {
				throw ValidationError("Must specify either --atif or --mif")
			} else {
				throw ValidationError("Cannot specify both --atif and --mif")
			}
		}
		
		// Check input file exists
		guard FileManager.default.fileExists(atPath: input) else {
			throw ValidationError("Input file not found: \(input)")
		}
	}
	
	func run() throws {
		// Parse mark positioning rules
		let rules: MarkPositioningRules
		do {
			rules = try RuleParser.parseMarkPositioningRules(from: input)
		} catch let error as OT2AATError {
			print("Error parsing rules file:", error)
			throw ExitCode.failure
		}
		
		// Validate that we have at least some rules
		guard rules.hasPositioning || rules.hasDistance else {
			print("Warning: No positioning rules found in '\(input)'")
			print("Expected at least one of:")
			print("  - @markclass definitions with @base")
			print("  - @mark2mark definitions")
			print("  - @ligature definitions")
			print("  - @distance rules or @matrix")
			throw ExitCode.failure
		}
		
		// Generate output
		let generatedOutput: String
		do {
			if atif {
				generatedOutput = try ATIFGeneratorKerx.generateMarkPositioning(
					rules: rules,
					featureName: feature,
					selectorNumber: selector
				)
			} else {
				generatedOutput = try KIFGenerator.generateMarkPositioning(
					rules: rules,
					featureName: feature,
					selectorNumber: selector
				)
			}
		} catch let error as OT2AATError {
			print("Error generating output:", error)
			throw ExitCode.failure
		}
		
		// Write output
		if let outputPath = output {
			do {
				try generatedOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
				print("Successfully generated \(atif ? "ATIF" : "KIF") output to '\(outputPath)'")
				
				// Print summary
				printSummary(rules: rules)
				
			} catch {
				print("Error writing output file: \(error.localizedDescription)")
				throw ExitCode.failure
			}
		} else {
			// Write to stdout
			print(generatedOutput)
		}
	}
	
	// MARK: - Helper Methods
	
	/// Print summary of what was generated
	private func printSummary(rules: MarkPositioningRules) {
		print("")
		print("Summary:")
		print("--------")
		
		if !rules.markGroups.isEmpty {
			print("Mark groups: \(rules.markGroups.count)")
			for markGroup in rules.markGroups {
				print("  - \(markGroup.semantic): \(markGroup.count) marks")
			}
		}
		
		if !rules.bases.isEmpty {
			let uniqueBases = Set(rules.bases.map { $0.glyph })
			print("Mark-to-base: \(uniqueBases.count) base glyphs")
		}
		
		if !rules.baseMarks.isEmpty {
			let uniqueBaseMarks = Set(rules.baseMarks.map { $0.mark })
			print("Mark-to-mark: \(uniqueBaseMarks.count) base marks")
		}
		
		if !rules.ligatures.isEmpty {
			print("Mark-to-ligature: \(rules.ligatures.count) ligatures")
			if let componentCount = rules.ligatures.first?.componentCount {
				print("  (up to \(componentCount) components)")
			}
		}
		
		if !rules.distanceRules.isEmpty {
			print("Distance rules: \(rules.distanceRules.count) simple pairs")
		}
		
		if !rules.distanceMatrices.isEmpty {
			print("Distance matrices: \(rules.distanceMatrices.count)")
			for matrix in rules.distanceMatrices {
				print("  - \(matrix.leftClasses.count) left × \(matrix.rightClasses.count) right classes")
				print("    (\(matrix.adjustments.count) adjustments)")
			}
		}
	}
}
