import Foundation
import ArgumentParser

struct Mark2BaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark2base",
        abstract: "TODO: Implement Mark2Base conversion"
    )
    
    func run() throws {
        print("⚠️  Mark2Base command not yet implemented")
        throw ExitCode.failure
    }
}
