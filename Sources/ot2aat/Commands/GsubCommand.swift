import Foundation
import ArgumentParser

struct GsubCommand: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "gsub",
		abstract: "Generate substitution rules (simple, ligatures, contextual, one-to-many, reorder)"
	)
	
	@Flag(name: .long, help: "Generate ATIF format output")
	var atif: Bool = false
	
	@Flag(name: .long, help: "Generate MIF format output")
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
		// Parse GSUB rules
		let rules: GsubRules
		do {
			rules = try RuleParser.parseGsubRules(from: input)
		} catch let error as OT2AATError {
			print("Error parsing rules file:", error)
			throw ExitCode.failure
		}
		
		// Validate that we have at least some rules
		guard rules.hasRules else {
			print("Warning: No substitution rules found in '\(input)'")
			print("Expected at least one of:")
			print("  - @simple { } section")
			print("  - @ligature { } section")
			print("  - @one2many { } section")
			print("  - @contextual { } section")
			print("  - @reorder { } section")
			throw ExitCode.failure
		}
		
		// Generate output
		let generatedOutput: String
		do {
			if atif {
				generatedOutput = try ATIFGenerator.generateGsub(
					rules: rules,
					featureName: feature,
					selectorNumber: selector
				)
			} else {
				generatedOutput = try MIFGenerator.generateGsub(
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
				print("Successfully generated \(atif ? "ATIF" : "MIF") output to '\(outputPath)'")
				
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
	private func printSummary(rules: GsubRules) {
		print("")
		print("Summary:")
		print("--------")
		
		if !rules.classes.isEmpty {
			print("Classes: \(rules.classes.count)")
		}
		
		if !rules.simpleSubstitutions.isEmpty {
			print("Simple substitutions: \(rules.simpleSubstitutions.count)")
		}
		
		if !rules.ligatures.isEmpty {
			print("Ligatures: \(rules.ligatures.count)")
			if let maxComponents = rules.ligatures.map({ $0.components.count }).max() {
				print("  (up to \(maxComponents) components)")
			}
		}
		
		if !rules.one2many.isEmpty {
			print("One-to-many: \(rules.one2many.count)")
		}
		
		if !rules.contextual.isEmpty {
			print("Contextual rules: \(rules.contextual.count)")
		}
		
		if !rules.reorder.isEmpty {
			print("Reorder rules: \(rules.reorder.count)")
		}
	}
}
