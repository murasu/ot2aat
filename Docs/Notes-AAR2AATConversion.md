# OT2AAT Conversion Tool - Development Context & Decisions

## Project Overview
This tool converts OpenType GSUB (Glyph Substitution) rules to Apple Advanced Typography (AAT) format. Specifically, it converts `.fea` (Feature) files to `.mif` (Mac Font Format) and `.atif` (Apple Type Interchange Format).

## Current Status
Working on Thai script contextual substitution rules conversion with proper handling of:
- Multi-element context patterns
- Glyph class expansion
- Context overlap detection
- Glyph reordering for complex scripts

## Key Architecture Decisions

### 1. Rule Expansion Strategy (Cartesian Product)
**Problem:** When a rule like `after @CLASS_004 @CLASS_001: uni0E48 => uni0E48.narrow` exists where:
- CLASS_004 = `uni0E1D uni0E1F uni0E1B` (3 glyphs)
- CLASS_001 = `uni0E3A uni0E38 uni0E39` (3 glyphs)

**Decision:** Generate the full Cartesian product (3 × 3 = 9 rules):
```
after uni0E1D uni0E3A: uni0E48 => uni0E48.narrow
after uni0E1D uni0E38: uni0E48 => uni0E48.narrow
after uni0E1D uni0E39: uni0E48 => uni0E48.narrow
... (and so on)
```

**Implementation:** Added `cartesianProduct()` helper function in `ContextualRule.swift` to generate all combinations.

### 2. Context Grouping Strategy
**Problem:** AAT state machines can't encode "substitute X to Y only if the specific context was Z". Merging all rules with different contexts into one table caused incorrect substitutions (e.g., `uni0E0D` triggering substitutions meant for `uni0E35`).

**Decision:** Group rules by context glyph for single-element patterns. Each unique context glyph gets its own state table.

**Example:**
- Rules with context `uni0E0D` → Table 11
- Rules with context `uni0E35` → Table 25
- Rules with context `uni0E48` → Table 33

**Files Modified:**
- `MIFGeneratorContextual.swift`
- `ATIFGeneratorContextual.swift`

### 3. Pattern Length Separation
**Problem:** Multi-element patterns (e.g., `after X Y: T => R`) were being mixed with single-element patterns in the same state table, causing glyphs from multi-element contexts to be treated as standalone contexts.

**Decision:** Separate rules by pattern length before grouping by context:
- Length 1 patterns: Group by context glyph, generate simple state machines
- Length 2+ patterns: Keep together, generate multi-state tracking machines

**Implementation:**
```swift
let afterByLength = Dictionary(grouping: allAfterRules) { rule -> Int in
    guard case .after(let context) = rule.context else { return 0 }
    return context.count
}
```

### 4. Overlap Detection for State Machines
**Problem:** When a glyph appears in both context and target sets (e.g., `uni0E35` is both a context in one rule and a target in another), AAT needs special handling.

**Decision:** Analyze overlap and generate three classes:
- **Context**: Glyphs only in context
- **Target**: Glyphs only as targets
- **TrgtAndCntx**: Glyphs in both sets

**Implementation:** `analyzeGlyphSets()` function in both MIF and ATIF generators.

### 5. Glyph Reordering Support
**Problem:** Thai script requires reordering tone marks after Sara Am decomposition:
- Input: `uni0E19 uni0E49 uni0E33`
- After decomposition: `uni0E19 uni0E49 uni0E4D uni0E32`
- Desired: `uni0E19 uni0E4D uni0E49 uni0E32` (tone mark moves after nikhahit)

**Decision:** Add `@reorder` section support to AAR syntax:
```
@reorder {
    uni0E48 uni0E4D > uni0E4D uni0E48
    uni0E49 uni0E4D > uni0E4D uni0E49
    uni0E4A uni0E4D > uni0E4D uni0E4A
    uni0E4B uni0E4D > uni0E4D uni0E4B
    uni0E4C uni0E4D > uni0E4D uni0E4C
}
```

**Syntax:** `source_pattern > target_pattern` (uses `>`, not `=>`)

**Status:** Parser implemented, generator implementation pending.

## File Structure

### Core Model Files
- **GsubRules.swift**: Defines all rule types (SimpleSubstitution, LigatureRule, ReorderRule, etc.)
- **ContextualRule.swift**: Handles contextual rule expansion
- **ContextualPattern.swift**: Defines context types (after, before, between, when)
- **ExpandedContextualRule.swift**: Post-expansion rule representation

### Parser Files
- **RuleParser+Gsub.swift**: Main parser for AAR syntax
  - `parseGsubRules()`: Entry point
  - `parseSimpleSubstitution()`: Handles `source -> target`
  - `parseLigature()`: Handles `target := comp1 + comp2`
  - `parseOne2ManyLine()`: Handles `source > target1 target2`
  - `parseContextualRule()`: Handles contextual patterns
  - `parseReorderRule()`: Handles reorder patterns (uses `>` separator)

### Generator Files
- **MIFGeneratorContextual.swift**: Generates MIF format
  - `generateContextual()`: Main entry, handles grouping logic
  - `generateAfterSubtable()`: Single-element after patterns
  - `generateBeforeSubtable()`: Single-element before patterns
  - `generateMultiElementAfterSubtable()`: Multi-element after patterns
  - `generateMultiElementBeforeSubtable()`: Multi-element before patterns
  - `analyzeGlyphSets()`: Overlap detection

- **ATIFGeneratorContextual.swift**: Generates ATIF format (mirrors MIF structure)

## AAR Syntax Reference

### Class Definitions
```
@class CLASS_NAME = glyph1 glyph2 glyph3
```

### Simple Substitution
```
@simple {
    source -> target
}
```

### Ligature
```
@ligature {
    target := component1 + component2
}
```

### One-to-Many
```
@one2many {
    source > target1 target2
}
```

### Contextual Substitution
```
@contextual {
    after @CLASS: target => replacement
    before @CLASS: target => replacement
    between @CLASS1 @CLASS2: target => replacement
    after @CLASS1 @CLASS2: target => replacement  # Multi-element
}
```

### Reorder (NEW)
```
@reorder {
    glyph1 glyph2 > glyph2 glyph1
}
```

## Known Issues & Solutions

### Issue 1: "uni0E48.small when it should not"
**Sequence:** `0E17 → 0E35 → 0E48`

**Root Cause:** `uni0E35` was only in Target class, not Context class.

**Solution:** Implemented Cartesian product expansion to ensure all context glyphs are properly identified.

### Issue 2: "uni0E49.small incorrectly after uni0E39"
**Sequence:** `0E1C, 0E39, 0E49`

**Root Cause:** Multi-element pattern `after @CLASS_004 @CLASS_001` made `uni0E39` appear as a standalone context.

**Solution:** Separated multi-element patterns into dedicated tables.

### Issue 3: "uni0E48.small after uni0E0D when it shouldn't"
**Sequence:** `0E43, 0E2B, 0E0D, 0E48`

**Root Cause:** Rules with different contexts merged into one table, causing cross-contamination.

**Solution:** Group single-element patterns by context glyph, generating separate tables per context.

### Issue 4: "Tone mark not reordering after Sara Am"
**Sequence:** `0E19, 0E49, 0E33` should become `0E19, 0E4D, 0E49.small, 0E32`

**Root Cause:** No reordering mechanism implemented.

**Solution:** Added `@reorder` syntax and parser support. Generator implementation pending.

## Critical Code Patterns

### Cartesian Product Helper
```swift
private func cartesianProduct(_ arrays: [[String]]) -> [[String]] {
    guard !arrays.isEmpty else { return [[]] }
    guard arrays.count > 1 else { return arrays[0].map { [$0] } }
    
    let first = arrays[0]
    let rest = Array(arrays.dropFirst())
    let restProduct = cartesianProduct(rest)
    
    var result: [[String]] = []
    for item in first {
        for combination in restProduct {
            result.append([item] + combination)
        }
    }
    return result
}
```

### Overlap Detection
```swift
private static func analyzeGlyphSets(
    targets: Set<String>,
    contexts: Set<String>
) -> (targetOnly: Set<String>, contextOnly: Set<String>, both: Set<String>, hasOverlap: Bool) {
    let both = targets.intersection(contexts)
    let targetOnly = targets.subtracting(contexts)
    let contextOnly = contexts.subtracting(targets)
    return (targetOnly, contextOnly, both, !both.isEmpty)
}
```

### Context Grouping Logic
```swift
// Group by pattern length first
let afterByLength = Dictionary(grouping: allAfterRules) { rule -> Int in
    guard case .after(let context) = rule.context else { return 0 }
    return context.count
}

// For single-element patterns, further group by context glyph
for (length, rulesForLength) in afterByLength {
    if length == 1 {
        let grouped = Dictionary(grouping: rulesForLength) { rule -> String in
            guard case .after(let context) = rule.context else { return "" }
            return context[0]
        }
        // Generate separate table for each context glyph
    }
}
```

## Next Steps (Pending)
1. **Implement Reorder Generator**: Create state machines for glyph reordering in both MIF and ATIF formats
2. **Test Thai Script**: Verify all Thai contextual rules work correctly
3. **Handle Cleanup Rules**: Ensure decomposed pattern cleanup rules are properly generated
4. **Multi-pass Rules**: Verify multi-substitution patterns work correctly

## Testing Sequences
Key test sequences for Thai script:
- `0E17, 0E35, 0E48` → Should apply `.small` (after expansion fix)
- `0E1C, 0E39, 0E49` → Should NOT apply `.small` (multi-element separation)
- `0E43, 0E2B, 0E0D, 0E48` → Should NOT apply `.small` (context grouping)
- `0E19, 0E49, 0E33` → Should reorder to `0E19, 0E4D, 0E49.small, 0E32` (reorder support)

## Compiler Warnings Fixed
- Removed unnecessary `if subtableNumber > 0` checks at the start of generation (always false on first iteration)
- Ensured all functions return proper values
- Fixed unused variable warnings by using `_` for intentionally ignored values

