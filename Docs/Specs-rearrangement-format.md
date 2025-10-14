# Reorder Rules Format Specification v1.0

## Overview

This document specifies the input format for the `ot2aat reorder` command, which converts glyph reordering patterns into Apple Advanced Typography (AAT) rearrangement subtables.

**Purpose:** Define rules for swapping and rearranging glyphs in the glyph stream (e.g., moving vowels before consonants in Indic scripts).

**Output formats:** MIF (Morph Input File) or ATIF (Advanced Typography Input File)

---

## File Structure

A reorder rules file consists of two sections in order:

```ruby
# ============================================================================
# 1. GLYPH CLASS DEFINITIONS (optional)
# ============================================================================

@class class_name = glyph1 glyph2 glyph3 ...

# ============================================================================
# 2. REORDERING RULES (required)
# ============================================================================

pattern_before => pattern_after
```

---

## Syntax Rules

### 1. Comments

```ruby
# Full-line comment - entire line is ignored

@class vowels = uni0E38 uni0E39  # End-of-line comment

# Blank lines are ignored
```

- Comments start with `#` and extend to end of line
- Can appear anywhere in the file
- Blank lines are ignored

### 2. Whitespace

- Whitespace (spaces, tabs) separates elements
- Multiple spaces treated as single separator
- Leading/trailing whitespace ignored
- Blank lines ignored

### 3. Case Sensitivity

- **Class names:** Case-sensitive (`@Vowels` ≠ `@vowels`)
- **Glyph names:** Case-sensitive (`uni0E38` ≠ `UNI0E38`)
- **Keywords:** Case-insensitive (`@CLASS` = `@class`)

---

## Glyph Class Definitions

### Syntax

```ruby
@class class_name = glyph1 glyph2 glyph3 ...
```

### Rules

1. **Must start with `@class` keyword**
2. **Class name:** Valid identifier (letters, digits, underscore; cannot start with digit)
3. **Equals sign:** Required separator between name and glyph list
4. **Glyph list:** Space-separated glyph names
5. **Must be defined before use** in rules
6. **No forward references**
7. **No duplicate class names**

### Examples

```ruby
# Simple class
@class lower_vowels = uni0E38 uni0E39 uni0E3A

# Multi-line (continuation via line breaks)
@class consonants = uni0E01 uni0E02 uni0E03
                    uni0E04 uni0E05 uni0E06
                    uni0E07 uni0E08 uni0E09

# Single glyph class (valid but unnecessary)
@class single = uni0331

# Empty class (ERROR)
@class empty =  # ERROR: must have at least one glyph
```

### Validation

- ✅ Class name must be unique
- ✅ Class must contain at least one glyph
- ✅ All glyph names must be valid
- ✅ Cannot redefine a class

### Error Examples

```ruby
# ERROR: Duplicate class name
@class vowels = uni0E38 uni0E39
@class vowels = uni0E34 uni0E35  # ERROR: 'vowels' already defined

# ERROR: Invalid class name
@class 123invalid = uni0E38  # ERROR: cannot start with digit
@class my-class = uni0E38    # ERROR: hyphen not allowed

# ERROR: Empty class
@class empty =  # ERROR: no glyphs specified
```

---

## Reordering Rules

### Syntax

```ruby
element1 element2 ... => element1' element2' ...
```

**Elements can be:**
- **Explicit glyph name:** `uni0E38`
- **Class reference:** `@class_name`

**Separator:** Whitespace between elements

**Operator:** `=>` (equals followed by greater-than)

### Rules

1. **Element count must match** on both sides
2. **Classes must be defined** before use
3. **Pattern must map** to one of 15 AAT rearrangement verbs
4. **Maximum 4 elements** per side (AAT limitation)

### Valid Patterns

```ruby
# Two-glyph swap
@vowels @marks => @marks @vowels
uni0E38 uni0331 => uni0331 uni0E38

# Three-glyph patterns
@cons @vowels @marks => @vowels @marks @cons
uni0E01 uni0E38 uni0E48 => uni0E38 uni0E48 uni0E01

# Four-glyph patterns
@a @b @c @d => @d @c @b @a

# Mixed explicit and classes
uni0E01 @vowels uni0E48 => uni0E48 @vowels uni0E01
```

### AAT Rearrangement Verbs

The tool automatically detects which AAT verb to use. Here are the 15 supported patterns:

**Two-element patterns:**
```ruby
A B => B A          # xD->Dx (swap)
```

**Three-element patterns:**
```ruby
A B C => B C A      # Ax->xA
A B C => C B A      # xD->Dx
A B C => C A B      # AxD->DxA
```

**Four-element patterns:**
```ruby
A B C D => C D A B  # ABx->xAB
A B C D => D C A B  # ABx->xBA
A B C D => A B D C  # xCD->CDx
A B C D => A B C D  # xCD->DCx
# ... and 7 more patterns
```

**Note:** If your pattern doesn't match any of the 15 verbs, the compiler will show an error with suggestions.

---

## Class Expansion and Limits

### CRITICAL: Class Size Matching Rule

**Each position in the pattern must have the same number of glyphs on both sides.**

This is because rearrangement rules create **matched pairs**, not cartesian products.

### How Expansion Works

Classes expand by **matching positions**, not by creating all combinations:

```ruby
@class vowels = a e i        # 3 glyphs
@class consonants = b c d    # 3 glyphs (MUST be same size!)

@vowels @consonants => @consonants @vowels
```

**Expands to 3 matched pairs:**
```ruby
a b => b a    # Index 0 from each class
e c => c e    # Index 1 from each class
i d => d i    # Index 2 from each class
```

**NOT a cartesian product** (which would be 3 × 3 = 9 combinations)

### Valid Examples

```ruby
# ✅ CORRECT: All positions match in size
@class vowels = a e i o u        # 5 glyphs
@class consonants = b c d f g    # 5 glyphs

@vowels @consonants => @consonants @vowels
# Expands to: 5 pairs (a↔b, e↔c, i↔d, o↔f, u↔g)

# ✅ CORRECT: Mix of explicit and classes (explicit = 1 glyph)
@class vowels = a e i            # 3 glyphs
@class consonants = b c d        # 3 glyphs

x @vowels @consonants => @consonants @vowels x
# Position 0: x (1) vs @consonants (3) - wait, this is WRONG!

# ✅ CORRECT version:
@class letters1 = a e i          # 3 glyphs
@class letters2 = b c d          # 3 glyphs
@class letters3 = x y z          # 3 glyphs

@letters1 @letters2 @letters3 => @letters3 @letters2 @letters1
# All positions have 3 glyphs each
```

### Invalid Examples

```ruby
# ❌ WRONG: Size mismatch
@class vowels = a e i o u        # 5 glyphs
@class consonants = b c d        # 3 glyphs - DIFFERENT SIZE!

@vowels @consonants => @consonants @vowels
# ERROR: Can't pair 5 vowels with 3 consonants

# ❌ WRONG: Explicit vs class size mismatch
@class vowels = a e i            # 3 glyphs

x @vowels => @vowels x
# Position 0: x (1) vs @vowels (3) - MISMATCH!
# Position 1: @vowels (3) vs x (1) - MISMATCH!

# ✅ CORRECT version: Keep explicit in same position
@class vowels = a e i
@class consonants = b c d

x @vowels @consonants => x @consonants @vowels
# Position 0: x (1) vs x (1) ✅
# Position 1: @vowels (3) vs @consonants (3) ✅
# Position 2: @consonants (3) vs @vowels (3) ✅
```

### Error Message

If sizes don't match, you'll get:

```
error: class size mismatch at position N
  --> rules.txt:15:1
   |
15 | @vowels @consonants => @consonants @vowels
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 
   |
   = note: Position 0: left has 5 glyph(s), right has 3 glyph(s)
   |
   = help: Both sides must use classes of same size
   = help: Ensure @vowels and @consonants have same number of glyphs
```

### Performance Limits

**Maximum combinations per rule: 100**

If a rule expands to more than 100 combinations, the compiler will error with:

```
error: class expansion exceeds limit
  --> rules.txt:15:1
   |
15 | @large_class1 @large_class2 => @large_class2 @large_class1
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 
   | this rule expands to 144 combinations (limit: 100)
   |
   = note: @large_class1 has 12 glyphs
   = note: @large_class2 has 12 glyphs
   = note: expansion: 12 × 12 = 144 combinations
   |
   = help: split into smaller classes or write explicit rules
   = help: excessive combinations hurt font performance
```

**Why this limit?**
- Large expansion creates bloated state tables
- Increases font file size
- Degrades rendering performance
- Usually indicates a design problem

**Solutions:**
1. Split large classes into smaller ones
2. Write more specific rules
3. Use explicit glyph pairs for exceptions
4. Re-evaluate whether all combinations are truly needed

### Calculating Expansion

```ruby
# Formula: product of all class sizes

# Example 1: Simple
@class a = g1 g2        # 2 glyphs
@class b = g3 g4 g5     # 3 glyphs
@a @b => @b @a          # 2 × 3 = 6 combinations ✅

# Example 2: Multiple classes
@class a = g1 g2        # 2 glyphs
@class b = g3 g4        # 2 glyphs  
@class c = g5 g6 g7     # 3 glyphs
@a @b @c => @c @b @a    # 2 × 2 × 3 = 12 combinations ✅

# Example 3: Mixed
@class vowels = v1 v2 v3 v4 v5      # 5 glyphs
@class marks = m1 m2 m3 m4 m5 m6    # 6 glyphs
@vowels @marks => @marks @vowels    # 5 × 6 = 30 combinations ✅

# Example 4: Too many (ERROR)
@class large1 = g1 ... g15          # 15 glyphs
@class large2 = g16 ... g25         # 10 glyphs
@large1 @large2 => @large2 @large1  # 15 × 10 = 150 ❌ EXCEEDS LIMIT
```

---

## Validation Rules

### At Parse Time

1. ✅ **Syntax:** Valid class definitions and rule syntax
2. ✅ **Class definitions:** Unique names, non-empty, valid glyphs
3. ✅ **Class references:** All referenced classes are defined
4. ✅ **Element count:** Same number of elements on both sides
5. ✅ **Pattern limit:** Maximum 4 elements per side
6. ✅ **Expansion limit:** Maximum 100 combinations per rule

### At Generation Time

1. ✅ **AAT pattern:** Pattern maps to one of 15 AAT verbs
2. ✅ **Glyph names:** All glyphs are valid (checked against font)
3. ✅ **No conflicts:** Rules don't conflict with each other

---

## Error Messages

All errors include:
- Error type and description
- File name and line number
- Relevant code snippet
- Helpful suggestions

### Examples

**Undefined class:**
```
error: undefined class '@consonants'
  --> thai_reorder.txt:15:1
   |
15 | @consonants @vowels => @vowels @consonants
   | ^^^^^^^^^^^ class not defined
   |
   = note: define class with: @class consonants = ...
   = help: did you mean '@lower_vowels'?
```

**Element count mismatch:**
```
error: element count mismatch
  --> thai_reorder.txt:18:1
   |
18 | @vowels @marks => @marks
   | ------------------------ pattern mismatch
   |
   = note: left side has 2 elements, right side has 1 element
   = help: both sides must have same number of elements
```

**Pattern not supported:**
```
error: pattern does not map to AAT rearrangement verb
  --> thai_reorder.txt:21:1
   |
21 | @a @b @c @d @e => @e @d @c @b @a
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 5-element pattern not supported
   |
   = note: AAT supports maximum 4 elements
   = note: available patterns: Ax->xA, xD->Dx, AxD->DxA, ABx->xAB, etc.
   = help: see documentation for list of 15 supported patterns
   = help: consider splitting into multiple rules
```

**Class expansion exceeds limit:**
```
error: class expansion exceeds limit
  --> thai_reorder.txt:25:1
   |
25 | @large_class1 @large_class2 => @large_class2 @large_class1
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 
   | this rule expands to 144 combinations (limit: 100)
   |
   = note: @large_class1 has 12 glyphs
   = note: @large_class2 has 12 glyphs
   = note: expansion: 12 × 12 = 144 combinations
   |
   = help: split into smaller classes or write explicit rules
```

**Invalid glyph name:**
```
error: invalid glyph name 'uni0E99999'
  --> thai_reorder.txt:30:15
   |
30 | uni0E38 uni0E99999 => uni0E99999 uni0E38
   |         ^^^^^^^^^^ glyph not recognized
   |
   = note: check Unicode value or glyph naming convention
   = help: valid format: uni + 4-6 hex digits (e.g., uni0E38)
```

---

## Command Line Usage

### From File (Recommended)

```bash
# MIF output
ot2aat reorder --mif -i rules.txt -f "Reordering" --selector 0 -o output.mif

# ATIF output
ot2aat reorder --atif -i rules.txt -f "Reordering" --selector 0 -o output.atif

# Output to stdout
ot2aat reorder --mif -i rules.txt -f "Reordering" --selector 0
```

### Single Rule (Explicit Glyphs Only)

```bash
# Simple two-glyph swap
ot2aat reorder --mif \
    -r "uni0E38 uni0331 => uni0331 uni0E38" \
    -f "Reordering" --selector 0

# Three-glyph pattern
ot2aat reorder --mif \
    -r "uni0E01 uni0E38 uni0E48 => uni0E38 uni0E48 uni0E01" \
    -f "Reordering" --selector 0 \
    -o output.mif
```

**Important:** Single-rule CLI (`-r`) **does NOT support classes**. Classes are only available in file-based input (`-i`).

### Options

| Option | Short | Required | Description |
|--------|-------|----------|-------------|
| `--mif` | | Yes* | Output MIF format |
| `--atif` | | Yes* | Output ATIF format |
| `-i, --input` | `-i` | Yes** | Input rules file |
| `-r, --rule` | `-r` | Yes** | Single rule (explicit glyphs only) |
| `-o, --output` | `-o` | No | Output file (default: stdout) |
| `-f, --feature` | `-f` | Yes | Feature name |
| `--selector` | | Yes | Selector number |
| `-h, --help` | `-h` | No | Show help |

\* Exactly one of `--mif` or `--atif` required  
\** Exactly one of `-i` or `-r` required (cannot use both)

---

## Complete Examples

### Example 1: Thai Vowel and Mark Reordering

**File: `thai_reorder.txt`**

```ruby
# ============================================================================
# Thai Vowel and Tone Mark Reordering
# ============================================================================

# Lower vowels (appear below consonant)
@class lower_vowels = uni0E38 uni0E39 uni0E3A

# Tone marks
@class tone_marks = uni0E48 uni0E49 uni0E4A uni0E4B uni0E4C

# Combining marks
@class combining = uni0331

# ============================================================================
# RULES
# ============================================================================

# Move combining marks before lower vowels
# Example: ุ◌̱ => ◌ุ̱
@lower_vowels @combining => @combining @lower_vowels

# Move tone marks before combining marks  
# Example: ่◌̱ => ◌่̱
@tone_marks @combining => @combining @tone_marks
```

**Command:**
```bash
ot2aat reorder --mif -i thai_reorder.txt -f "Reordering" --selector 0 -o thai_reorder.mif
```

### Example 2: Devanagari Pre-base Vowel

**File: `devanagari_reorder.txt`**

```ruby
# ============================================================================
# Devanagari Pre-base Vowel Reordering
# ============================================================================

# Consonants
@class consonants = uni0915 uni0916 uni0917 uni0918 uni0919

# Virama (halant)
@class virama = uni094D

# Pre-base vowels (i, ii)
@class preBas_vowels = uni093F uni0940

# ============================================================================
# RULES
# ============================================================================

# Move pre-base vowel before consonant+virama
# Logical: C + virama + i => i + C + virama
# Visual:  क् + ि => िक्
@consonants @virama @preBase_vowels => @preBase_vowels @consonants @virama
```

**Command:**
```bash
ot2aat reorder --mif -i devanagari_reorder.txt -f "Reordering" --selector 2 -o devanagari.mif
```

### Example 3: Mixed Explicit and Classes

**File: `mixed_reorder.txt`**

```ruby
# ============================================================================
# Mixed Reordering Example
# ============================================================================

@class vowels = uni0E38 uni0E39

# Rule with mixed elements
# Explicit glyph + class reference
uni0E01 @vowels uni0E48 => uni0E48 @vowels uni0E01

# Expands to:
# uni0E01 uni0E38 uni0E48 => uni0E48 uni0E38 uni0E01
# uni0E01 uni0E39 uni0E48 => uni0E48 uni0E39 uni0E01
```

### Example 4: Multiple Rules

**File: `multi_reorder.txt`**

```ruby
# ============================================================================
# Multiple Independent Rules
# ============================================================================

@class vowels_lower = uni0E38 uni0E39
@class vowels_upper = uni0E34 uni0E35
@class marks = uni0331 uni0332

# Rule 1: Lower vowels before marks
@vowels_lower @marks => @marks @vowels_lower

# Rule 2: Upper vowels before marks  
@vowels_upper @marks => @marks @vowels_upper

# All rules are grouped into one state table
# Compiler optimizes class definitions
```

---

## Best Practices

### 1. Class Organization

```ruby
# ✅ GOOD: Descriptive names, logical grouping
@class lower_vowels = uni0E38 uni0E39 uni0E3A
@class upper_vowels = uni0E34 uni0E35 uni0E36 uni0E37
@class tone_marks = uni0E48 uni0E49 uni0E4A uni0E4B uni0E4C

# ❌ BAD: Unclear names
@class v1 = uni0E38 uni0E39
@class v2 = uni0E34 uni0E35
@class m = uni0E48 uni0E49
```

### 2. Comments

```ruby
# ✅ GOOD: Explain purpose and examples
# Move lower vowels before combining marks
# Visual example: ุ◌̱ => ◌ุ̱
@lower_vowels @combining => @combining @lower_vowels

# ❌ BAD: No context
@lower_vowels @combining => @combining @lower_vowels
```

### 3. File Organization

```ruby
# ✅ GOOD: Clear sections
# Classes first, rules second
# Related classes grouped together

# ❌ BAD: Mixed definitions and rules
@class a = ...
a b => b a
@class b = ...
```

### 4. Explicit vs Classes

```ruby
# ✅ GOOD: Use classes for repeated patterns
@class vowels = uni0E38 uni0E39 uni0E3A
@vowels @marks => @marks @vowels

# ❌ BAD: Repetitive explicit rules
uni0E38 @marks => @marks uni0E38
uni0E39 @marks => @marks uni0E39
uni0E3A @marks => @marks uni0E3A
```

### 5. Performance Awareness

```ruby
# ✅ GOOD: Manageable expansion
@class vowels = v1 v2 v3 v4 v5          # 5 glyphs
@class marks = m1 m2 m3                  # 3 glyphs
@vowels @marks => @marks @vowels         # 5 × 3 = 15 ✅

# ⚠️  WARNING: Getting large
@class large1 = ... # 20 glyphs
@class large2 = ... # 20 glyphs
@large1 @large2 => @large2 @large1       # 20 × 20 = 400 ⚠️

# ❌ BAD: Excessive expansion
@class huge1 = ... # 50 glyphs
@class huge2 = ... # 50 glyphs
@huge1 @huge2 => @huge2 @huge1           # 50 × 50 = 2500 ❌
```

---

## Limitations

1. **Pattern complexity:** Maximum 4 elements per side
2. **Class expansion:** Maximum 100 combinations per rule
3. **AAT verbs:** Must match one of 15 predefined patterns
4. **No Unicode properties:** Not supported in v1.0 (planned for future)
5. **Single rule CLI:** No class support (explicit glyphs only)
6. **No forward references:** Classes must be defined before use

---

## Future Enhancements

### Planned for v2.0

**Unicode Properties:**
```ruby
# Define classes using Unicode properties
@class consonants = \p{Script=Thai} & \p{Lo}
@class marks = \p{Mn}
```

**Ranges:**
```ruby
# Define ranges
@class thai_consonants = uni0E01..uni0E2E
```

**Set Operations:**
```ruby
# Set operations for classes
@class letters = \p{L}
@class vowels = uni0E38 uni0E39 uni0E3A
@class consonants = [letters] -- [vowels]  # Set difference
```

---

## Summary

### Key Points

✅ **Two sections:** Class definitions, then rules  
✅ **Classes:** `@class name = glyphs`  
✅ **Rules:** `pattern => pattern`  
✅ **Elements:** Explicit glyphs or `@classname`  
✅ **Expansion:** Automatic, limited to 100 combinations  
✅ **Validation:** Comprehensive error checking with line numbers  
✅ **CLI:** File-based with classes, or single explicit rule  

### Quick Reference

```ruby
# Define classes
@class name = glyph1 glyph2 glyph3

# Write rules (element count must match)
@class1 @class2 => @class2 @class1
glyph1 @class => @class glyph1

# Comments
# Full line comment
rule => rule  # End-of-line comment
```

### Command Template

```bash
ot2aat reorder --mif|--atif \
    -i rules.txt \
    -f "FeatureName" \
    --selector N \
    -o output.mif
```

---

**Version:** 1.0  
**Last Updated:** 2025-01-15
