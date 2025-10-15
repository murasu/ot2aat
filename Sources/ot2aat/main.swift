import ArgumentParser

struct OT2AAT: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ot2aat",
        abstract: "Convert OpenType layout rules to Apple Advanced Typography format",
        version: "1.0.0",
        subcommands: [
            One2ManyCommand.self,
            ReorderCommand.self,
            ContextSubCommand.self,
            MarkPosCommand.self  // Unified mark positioning command
        ]
    )
}

OT2AAT.main()
