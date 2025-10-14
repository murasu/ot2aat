import Foundation
import ArgumentParser

struct ReorderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reorder",
        abstract: "TODO: Implement Reorder conversion"
    )
    
    func run() throws {
        print("⚠️  Reorder command not yet implemented")
        throw ExitCode.failure
    }
}
