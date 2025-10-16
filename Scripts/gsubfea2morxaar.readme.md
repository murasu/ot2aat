# GSUB to AAR Converter - Project Documentation

## Project Overview

This project converts OpenType GSUB (Glyph Substitution) features to an intermediate `.aar` format, which is then processed by the `ot2aat` tool to generate Apple Advanced Typography (AAT) tables in MIF or ATIF format.

### Conversion Pipeline

```
Font (OTF/TTF)
    ↓
TTX (XML extraction)
    ↓
FEA (Feature file)
    ↓
AAR (Intermediate format) ← THIS PROJECT
    ↓
MIF/ATIF (AAT tables) ← ot2aat tool
```

## The Problem

OpenType and AAT use fundamentally different approaches to glyph substitution:

- **OpenType GSUB**: Uses lookup tables with contextual chaining
- **AAT**: Uses state machines with exact sequential matching

Key differences:
1. **Lookup inlining**: OpenType references lookups; AAT needs inline substitutions
2. **Mark filtering**: OpenType can skip marks during matching; AAT matches exact sequences
3. **Context representation**: Different syntax for before/after/between/when patterns

## Input Format

### Source: TTX-Converted FEA Files

We use FEA files generated from TTX (FontTools XML format):

```bash
# Extract GSUB table from font
ttx -t GSUB font.otf

# Convert TTX to FEA (separate tool needed)
# Output format example:
```

```ruby
lookup lookup_0 {
  sub uni0E38 by uni0331;
  sub uni0E39 by uni0331;
} lookup_0;

feature ccmp {
  script thai;
  
  lookup lookup_5;
  lookup lookup_7;
} ccmp;
```

### Key Characteristics

1. **Lookup definitions first**, then feature blocks
2. **Script information** in feature blocks: `script thai;`
3. **Contextual syntax**: `sub [class1]' [class2] by lookup_X;`
4. **Inline classes**: `[glyph1 glyph2 glyph3]` instead of `@class`
5. **Marks**: Apostrophe `'` indicates positions to substitute

## Output Format: AAR (Intermediate)

The `.aar` format is our custom intermediate representation with these sections:

### 1. Global Classes

```ruby
@class class_name = glyph1 glyph2 glyph3
```

### 2. Simple Substitutions (Type 1)

```ruby
@simple {
    source -> target
}
```

### 3. Ligatures (Type 4)

```ruby
@ligature {
    ligature_name := component1 + component2 + component3
}
```

### 4. Multiple Substitutions (Type 2)

```ruby
@one2many {
    source > target1 target2 target3
}
```

### 5. Contextual Substitutions (Type 6)

Four context types:

```ruby
@contextual {
    # After context (last position marked)
    after context_pattern: target => replacement
    
    # Before context (first position marked)
    before context_pattern: target => replacement
    
    # Between context (middle position marked)
    between pattern1 and pattern2: target => replacement
    
    # When context (full pattern match)
    when full_pattern: target => replacement
    when pattern: target1 => repl1, target2 => repl2
}
```

## Key Design Decisions

### Decision 1: No OTM Support

**Initial approach**: Parse OTM (OpenType Master) exported FEA files with metadata comments

**Problem**: OTM export was incomplete/unreliable - missing feature references

**Final decision**: Use TTX-converted FEA files exclusively
- More reliable
- Cleaner structure
- We control the conversion

### Decision 2: Script Filtering

**Requirement**: Filter by script (e.g., only Thai features)

**Implementation**:
```bash
python3 gsubfea2aar.py input.fea output.aar --script thai
```

**Logic**:
- Parse script declarations in feature blocks
- Only output lookups used in filtered scripts
- Prefix lookups (helper lookups) are never output directly - they're inlined

### Decision 3: Lookup Inlining

**Problem**: OpenType uses lookup references; AAT needs actual substitutions

**Example**:
```ruby
# OpenType FEA:
sub uni0E38' lookup SUB_2 uni0331' lookup SUB_3;

# Where SUB_2 = {uni0E38 → uni0331}
#       SUB_3 = {uni0331 → uni0E38}

# AAR output:
when uni0E38 uni0331: uni0E38 => uni0331, uni0331 => uni0E38
```

**Rules**:
- Inline all lookup references
- Filter substitutions by pattern elements
- Last substitution wins if same source appears multiple times

### Decision 4: UseMarkFilteringSet Handling

**OpenType behavior**: Marks can be "transparent" during matching
```ruby
lookupflag UseMarkFilteringSet [uni0331.alt];
sub uni0E0D' lookup SUB_11 uni0331.alt;
```

**AAT behavior**: Exact sequential matching only - no mark skipping

**Decision**: 
- Add informational comment: `# NOTE: Original lookup has lookupflag - AAT uses exact sequential matching`
- Don't attempt to preserve the filtering semantics (different model)
- Let font designer test and adjust manually if needed

### Decision 5: Context Type Detection

**For single marked position**:
- First position → `before`
- Last position → `after`  
- Middle position → `between`

**For multiple marked positions**:
- Use `when` context with comma-separated substitutions

**For multi-element patterns** (Current Issue):
- Pattern like `[class1] [class2] [target]'` has 3 elements
- Should use `when` context to preserve full pattern
- Issue: Current code may flatten classes incorrectly

### Decision 6: Empty Lookups

**Problem**: Some lookups have no substitutions (e.g., `lookup_6` with just TODO comment)

**Decision**: Skip empty lookups entirely - don't output empty sections

### Decision 7: Duplicate Entries

**Problem**: Same substitution rule appearing multiple times

**Approach**: 
- Last one wins during inlining (Python dict naturally handles this)
- But we should avoid generating duplicate output rules

### Decision 8: Glyph Name Semantics

**Important**: Glyph names like `.short`, `.alt`, `.narrow` are **opaque**
- Don't try to parse suffixes
- Don't make assumptions about glyph relationships
- Treat each glyph name as a unique identifier

## AAR Syntax Reference

Based on the contextual substitution spec:

### Pattern Elements
- **Explicit glyphs**: `uni0E38`, `A`, `space`
- **Class references**: `@consonants` (must be defined)
- **Inline classes**: We convert `[a b c]` to expanded form
- **Maximum pattern length**: 10 elements

### Substitution Syntax
```ruby
# Single
after @consonants: vowel => vowel.alt

# Multiple (comma-separated, single line)
when pattern: target1 => repl1, target2 => repl2, target3 => repl3
```

### Class Expansion Rules

**Position-wise matching** (like reorder rules):
```ruby
@class vowels = a e i        # 3 glyphs
@class vowels_alt = a.alt e.alt i.alt    # 3 glyphs (same size!)

after @consonants: @vowels => @vowels_alt
# Expands to 3 matched pairs:
#   after @consonants: a => a.alt
#   after @consonants: e => e.alt
#   after @consonants: i => i.alt
```

Classes at corresponding positions must have **same size**.

## Known Issues (To Fix)

### Issue 1: Multi-Element Pattern Flattening

**Problem**:
```ruby
# Input pattern:
sub [uni0E1D uni0E1F uni0E1B] [uni0E3A uni0E38 uni0E39] [uni0E4B ...]' by lookup_9;

# Current buggy output:
after uni0E1D uni0E1F uni0E1B uni0E3A uni0E38 uni0E39: uni0E4B => uni0E4B.narrow

# Should be (when context):
when (class1) (class2) (target): target => replacement
```

The classes are being flattened into a single sequence instead of preserving the 3-element structure.

### Issue 2: Redundant/Duplicate Entries

Some rules appear multiple times in output - need deduplication.

### Issue 3: Long Context Patterns

Patterns like `after uni0E4B uni0E48 uni0E31 uni0E31.narrow...` (very long) might need better formatting or class creation.

## Reference Documents

### Included Specifications

1. **Specs-contextual-subst-rules-format.md**
   - Defines AAR contextual substitution syntax
   - Four context types: after, before, between, when
   - Pattern matching rules
   - Multi-pass generation for complex rules

2. **Specs-rearrangement-format.md**
   - Defines reorder rules syntax
   - Class expansion rules (position-wise matching)
   - AAT rearrangement verbs

3. **contextual-test.txt**
   - Test cases for contextual rules
   - ASCII to Thai glyph examples

4. **rearrangement-tests.txt**
   - Test cases for reorder rules
   - Example MIF and ATIF outputs

### Example Files

- **thai_subs.fea**: Original OpenType feature file
- **thai_subs.aar**: Intermediate AAR format
- **thai_subs.mif**: Final AAT MIF format
- **NotoSansThai-Regular_256-OT.fea**: Full font features from OTM
- **thai_fromttx.fea**: Clean FEA from TTX conversion
- **thai_fromttx.aar**: Current output (has issues)

## Tools and Workflow

### Required Tools

1. **FontTools (ttx)**
   ```bash
   pip install fonttools
   ttx -t GSUB font.otf  # Extracts GSUB table to XML
   ```

2. **TTX to FEA Converter** (separate tool needed)
   - Converts TTX XML to clean FEA format
   - Adds script declarations to features

3. **gsubfea2aar.py** (this project)
   ```bash
   python3 gsubfea2aar.py input.fea output.aar --script thai
   ```

4. **ot2aat** (final conversion)
   ```bash
   # Convert AAR to MIF
   ot2aat contextsub --mif -i rules.aar -f "Contextual" --selector 0 -o output.mif
   
   # Convert AAR to ATIF
   ot2aat contextsub --atif -i rules.aar -f "Contextual" --selector 0 -o output.atif
   ```

### Workflow

```bash
# Step 1: Extract GSUB from font
ttx -t GSUB NotoSansThai-Regular.otf

# Step 2: Convert TTX to FEA (tool needed)
ttx2fea NotoSansThai-Regular.ttx thai.fea

# Step 3: Convert FEA to AAR (this project)
python3 gsubfea2aar.py thai.fea thai.aar --script thai

# Step 4: Convert AAR to MIF/ATIF (ot2aat tool)
ot2aat contextsub --mif -i thai.aar -f "Contextual" --selector 0 -o thai.mif
```

## Script Structure

### Main Classes

1. **LookupInfo**: Metadata (name, scripts, features, is_prefix)
2. **SingleSubstitution**: 1:1 glyph substitution
3. **LigatureSubstitution**: Multiple glyphs → ligature
4. **MultipleSubstitution**: 1 glyph → multiple glyphs
5. **ContextualSubstitution**: Context-based substitution
6. **ParsedLookup**: Container for all lookup content
7. **GSUBToAAR**: Main converter class

### Key Methods

- `parse_file()`: Main parsing entry point
- `parse_lookup_body()`: Parse lookup contents
- `parse_feature_block()`: Track feature order
- `parse_contextual_substitution()`: Handle contextual rules
- `inline_lookup_substitutions()`: Resolve lookup references
- `generate_contextual_rules()`: Generate AAR contextual syntax
- `should_include_lookup()`: Apply script filter

## Testing Strategy

### Test Files

1. **Simple substitutions**: Verify 1:1 mappings
2. **Ligatures**: Test component combinations
3. **Multiple substitutions**: Test 1:many decomposition
4. **Contextual**: Test all four context types
5. **Script filtering**: Verify only Thai features included
6. **Empty lookups**: Ensure they're skipped
7. **Lookup inlining**: Verify prefix lookups resolved

### Validation

1. Parse the generated AAR file
2. Compare with expected patterns
3. Check for duplicate entries
4. Verify context patterns are correct
5. Test with actual font in ot2aat

## Future Improvements

1. **Better multi-element pattern handling**: Preserve structure instead of flattening
2. **Class creation**: Auto-generate classes for long patterns
3. **Deduplication**: Remove redundant rules
4. **TTX to FEA converter**: Build integrated tool
5. **Validation**: Add AAR syntax validator
6. **Error recovery**: Better handling of malformed input
7. **Unicode properties**: Support ranges and properties in classes (planned in spec v2.0)

## References

- OpenType Specification: https://docs.microsoft.com/en-typography/opentype/spec/
- AAT Reference: https://developer.apple.com/fonts/TrueType-Reference-Manual/
- FontTools: https://github.com/fonttools/fonttools
- ot2aat tool: (internal tool documentation)

## Notes for Next Session

1. Fix multi-element pattern issue (use when context properly)
2. Add deduplication for output rules
3. Consider class creation for very long patterns
4. Test with complete Thai font conversion
5. Validate AAR output format against spec

---

**Last Updated**: 2025-10-16  
**Version**: 0.1.0 (In Development)  
**Status**: Has known issues - see "Known Issues" section
