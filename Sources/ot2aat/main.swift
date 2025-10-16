import ArgumentParser

struct OT2AAT: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ot2aat",
        abstract: "Convert OpenType layout rules to Apple Advanced Typography format",
        version: "1.0.0",
        subcommands: [
            GsubCommand.self,          // NEW: Unified GSUB command
            MarkPosCommand.self,        // Unified GPOS command
            // Legacy commands (can deprecate later):
            One2ManyCommand.self,
            ReorderCommand.self,
            ContextSubCommand.self
        ]
    )
}

OT2AAT.main()
