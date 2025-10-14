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
            Mark2BaseCommand.self,
            Mark2MarkCommand.self,
            Mark2LigaCommand.self
        ]
    )
}

OT2AAT.main()
