import Foundation
import ArgumentParser

struct ContextSubCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contextsub",
        abstract: "TODO: Implement ContextSub conversion"
    )
    
    func run() throws {
        print("⚠️  ContextSub command not yet implemented")
        throw ExitCode.failure
    }
}
