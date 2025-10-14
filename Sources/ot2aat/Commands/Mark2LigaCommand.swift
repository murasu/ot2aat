import Foundation
import ArgumentParser

struct Mark2LigaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark2liga",
        abstract: "TODO: Implement Mark2Liga conversion"
    )
    
    func run() throws {
        print("⚠️  Mark2Liga command not yet implemented")
        throw ExitCode.failure
    }
}
