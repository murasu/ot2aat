# OT2AAT - OpenType to Apple Advanced Typography Converter

A command-line tool to convert OpenType layout rules to Apple Advanced Typography (AAT) format, supporting both MIF (Morph Input File) and ATIF (Advanced Typography Input File) output formats.

## Features

- **One-to-Many Substitution**: Split glyphs (e.g., Thai Sara AM → Nikhahit + Sara AA)
- **Reordering**: Change glyph order (e.g., Devanagari vowel reordering)
- **Contextual Substitution**: Context-dependent glyph changes
- **Mark-to-Base**: Position marks relative to base glyphs
- **Mark-to-Mark**: Position marks relative to other marks
- **Mark-to-Ligature**: Position marks on ligatures

## Installation

### Prerequisites

- macOS 13.0 or later
- Xcode 14.0 or later
- Swift 5.9 or later

### Build from source

```bash
swift build -c release
```

The executable will be at `.build/release/ot2aat`

### Install system-wide (optional)

```bash
sudo cp .build/release/ot2aat /usr/local/bin/
```

## Usage

### One-to-Many Substitution

Split a single glyph into multiple glyphs:

**Single rule from command line:**
```bash
ot2aat one2many -mif -s uni0E33 -t uni0E4D uni0E32 -f "Default" --selector 0
```

**Multiple rules from file:**
```bash
ot2aat one2many -mif -i rules.txt -f "Default" --selector 0 -o output.mif
```

**Rules file format** (`rules.txt`):
```
# Comments start with #
uni0E33 > uni0E4D uni0E32
uni0E4D > uni0E19 uni0E4A

# Blank lines are ignored
```

### Output Formats

- **MIF** (`-mif`): Legacy Morph Input File format
- **ATIF** (`-atif`): Modern Advanced Typography Input File format

### Command Options

- `-s, --source <glyph>`: Source glyph (for single rule)
- `-t, --target <glyph>...`: Target glyphs (space-separated)
- `-i, --input <file>`: Input rules file
- `-o, --output <file>`: Output file (default: stdout)
- `-f, --feature <name>`: Feature name (required)
- `--selector <number>`: Selector number (required)
- `-h, --help`: Show help

## Examples

### Thai Sara AM Splitting

Split Thai Sara AM (◌ำ) into Nikhahit (◌ํ) + Sara AA (◌า):

```bash
ot2aat one2many -mif \
    -s uni0E33 \
    -t uni0E4D uni0E32 \
    -f "Default" \
    --selector 0 \
    -o thai_split.mif
```

### Multiple Rules from File

Create `tamil_splits.txt`:
```
# Tamil vowel splits
uni0BCA > uni0BC6 uni0BBE
uni0BCB > uni0BC7 uni0BBE
uni0BCC > uni0BC6 uni0BD7
```

Generate MIF:
```bash
ot2aat one2many -mif \
    -i tamil_splits.txt \
    -f "Default" \
    --selector 0 \
    -o tamil_splits.mif
```

### Generate ATIF Instead

```bash
ot2aat one2many -atif \
    -i rules.txt \
    -f "Default" \
    --selector 0 \
    -o output.atif
```

## Project Structure

```
ot2aat/
├── Package.swift
├── Sources/
│   └── ot2aat/
│       ├── main.swift
│       ├── Commands/
│       │   ├── Command.swift
│       │   ├── One2ManyCommand.swift
│       │   └── ... (other commands)
│       ├── Generators/
│       │   ├── MIFGenerator.swift
│       │   └── ATIFGenerator.swift
│       ├── Models/
│       │   ├── GlyphRule.swift
│       │   └── SubstitutionRule.swift
│       └── Utilities/
│           ├── ArgumentParser.swift
│           └── RuleParser.swift
├── Tests/
│   └── ot2aatTests/
└── README.md
```

## Development

### Running Tests

```bash
swift test
```

### Opening in Xcode

```bash
open Package.swift
```

This will open the project in Xcode where you can edit, build, and debug.

## Supported Commands

| Command | Status | Description |
|---------|--------|-------------|
| `one2many` | ✅ Implemented | One-to-many glyph substitution |
| `reorder` | 🚧 Coming soon | Glyph reordering |
| `contextsub` | 🚧 Coming soon | Contextual substitution |
| `mark2base` | 🚧 Coming soon | Mark-to-base positioning |
| `mark2mark` | 🚧 Coming soon | Mark-to-mark positioning |
| `mark2liga` | 🚧 Coming soon | Mark-to-ligature positioning |

## References

- [Apple Advanced Typography Documentation](https://developer.apple.com/fonts/)
- [AAT Font Feature Registry](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM09/AppendixF.html)

## License

Proprietory. (C) 2025 Muthu Nedumaran. All rights reserved

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Author

Muthu Nedumaran

---

**Note**: This tool generates AAT tables for use with `ftxenhancer` or similar tools. The generated files need to be compiled into a font using appropriate font tools.
