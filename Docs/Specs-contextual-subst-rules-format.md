# Contextual Substitution Rules Format Specification v1.0

## Overview

This document specifies the input format for the `ot2aat contextsub` command, which converts contextual glyph substitution patterns into Apple Advanced Typography (AAT) Type 1 (Contextual Substitution) subtables.

**Purpose:** Define rules for substituting glyphs based on surrounding context (e.g., different vowel forms after different consonants).

**Output formats:** MIF (Morph Input File) or ATIF (Advanced Typography Input File)

---

## File Structure

A contextual substitution rules file consists of two sections in order:

```ruby
# ============================================================================
# 1. GLYPH CLASS DEFINITIONS (optional)
# ============================================================================

@class class_name = glyph1 glyph2 glyph3 ...

# ============================================================================
# 2. CONTEXTUAL SUBSTITUTION RULES (required)
# ============================================================================

# Simple context rules
after pattern: target => replacement
before pattern: target => replacement
between pattern1 and pattern2: target => replacement

# Full pattern matching
when pattern: target => replacement
when pattern: target1 => replacement1, target2 => replacement2
```

---

## Syntax Rules

### Comments and Whitespace

Same as reorder rules:
- Comments: `#` to end of line
- Blank lines: Ignored
- Multiple spaces: Treated as single separator

### Glyph Class Definitions

**Identical to reorder format:**

```ruby
@class class_name = glyph1 glyph2 glyph3 ...
```

- Must be defined before use
- No forward references
- No duplicate names
- Case-sensitive class names
- Case-sensitive glyph names

---

## Context Types

Four context types are supported, each mapping to specific AAT state machine patterns:

### 1. AFTER Context

**Syntax:**
```ruby
after context_pattern: target => replacement
```

**Meaning:** When we see `context_pattern`, then substitute the next occurrence of `target` with `replacement`.

**AAT behavior:**
1. See context_pattern → mark position, advance
2. See target → substitute current glyph

**Examples:**
```ruby
# After a consonant, use alternate vowel form
after @consonants: uni0BBF => uni0BBF.alt

# After space, use initial capital form
after space: @uppercase => @uppercase.init

# Multiple contexts (class)
after @consonants: @vowels => @vowels.alt
```

### 2. BEFORE Context

**Syntax:**
```ruby
before context_pattern: target => replacement
```

**Meaning:** When we see `target`, mark it; then when we see `context_pattern`, substitute the marked `target`.

**AAT behavior:**
1. See target → mark position, advance
2. See context_pattern → substitute marked glyph

**Examples:**
```ruby
# Before a vowel, use pre-vowel consonant form
before @vowels: @consonants => @consonants.prevowel

# Before end of word, use final form
before space: s => s.final
```

### 3. BETWEEN Context

**Syntax:**
```ruby
between context1 and context2: target => replacement
```

**Meaning:** When we see `context1`, then `target`, then `context2`, substitute `target`.

**AAT behavior:**
1. See context1 → change state (remember we saw context1)
2. See target → mark position, advance
3. See context2 → substitute marked glyph

**Examples:**
```ruby
# Use figure dash between digits
between @digits and @digits: hyphen => figureDash

# Special form between consonants and vowels
between @consonants and @vowels: virama => virama.special
```

### 4. WHEN Context (Full Pattern Matching)

**Syntax:**
```ruby
# Single substitution
when pattern: target => replacement

# Multiple substitutions
when pattern: target1 => replacement1, target2 => replacement2, ...
```

**Meaning:** Only substitute when the ENTIRE pattern is matched.

**AAT behavior:**
1. Build state machine that matches full pattern
2. Mark target positions while matching
3. Substitute when full pattern confirmed

**Examples:**
```ruby
# Single substitution in pattern
when @cons @vowel1 @vowel2: @cons => @cons.alt

# Multiple substitutions (auto multi-pass!)
when @cons @vowel1 @vowel2:
    @cons => @cons.alt,
    @vowel1 => @vowel1.alt,
    @vowel2 => @vowel2.alt

# Exact pattern match
when ka virama ssa: ka => ka_ssa_ligature
```

---

## Pattern Elements

Patterns can contain:
- **Explicit glyphs**: `ka`, `uni0B95`, `space`
- **Class references**: `@consonants`, `@vowels`
- **Mix of both**: `ka @vowels space`

**Pattern limits:**
- Minimum: 1 element
- Maximum: 10 elements per pattern
- For `when` context: full pattern is checked before substitution

---

## Substitution Syntax

### Single Substitution

```ruby
after @consonants: vowel => vowel.alt
```

**Format:** `target => replacement`

### Multiple Substitutions

```ruby
when @cons @vowel1 @vowel2:
    @cons => @cons.alt,
    @vowel1 => @vowel1.alt,
    @vowel2 => @vowel2.alt
```

**Format:** Multiple `target => replacement` pairs separated by commas

**Indentation:** Recommended for readability (not required)

### Wildcard Substitutions

```ruby
# Add suffix to all glyphs
after @consonants: * => *.alt

# Replace suffix
after @consonants: *.oldstyle => *.proportional
```

**Patterns:**
- `* => * ".suffix"` - Add suffix
- `* ".suffix" => *` - Remove suffix  
- `* ".old" => * ".new"` - Replace suffix
- `*` alone matches current context glyphs

---

## Class Expansion Rules

### Position-wise Matching (Like Reorder)

**For simple contexts (`after`, `before`, `between`):**

Classes must have **same size** at corresponding positions:

```ruby
@class vowels = a e i o u        # 5 glyphs
@class vowels_alt = a.alt e.alt i.alt o.alt u.alt  # 5 glyphs

# ✅ CORRECT: Both classes same size
after @consonants: @vowels => @vowels_alt
```

Expands to 5 matched pairs:
```ruby
after @consonants: a => a.alt
after @consonants: e => e.alt
...
```

### Pattern Matching (When Context)

**For `when` context with multiple substitutions:**

All target classes in the pattern must have the same size:

```ruby
@class cons = ka ga nga           # 3 glyphs
@class vowel1 = a e i              # 3 glyphs
@class vowel2 = u o aa             # 3 glyphs

# ✅ CORRECT: All 3 classes same size
when @cons @vowel1 @vowel2:
    @cons => @cons.alt,
    @vowel1 => @vowel1.alt,
    @vowel2 => @vowel2.alt
```

Expands to 3 pattern sets:
```ruby
when ka a u: ka => ka.alt, a => a.alt, u => u.alt
when ga e o: ga => ga.alt, e => e.alt, o => o.alt
when nga i aa: nga => nga.alt, i => i.alt, aa => aa.alt
```

---

## Multi-pass Generation

### Automatic for Complex Rules

When a rule has **multiple substitutions** in a `when` context, the tool automatically generates multiple passes:

**Input:**
```ruby
when @cons @vowel1 @vowel2:
    @cons => @cons.alt,
    @vowel1 => @vowel1.alt,
    @vowel2 => @vowel2.alt
```

**Generated Pass 1** (Mark positions with temporary glyphs):
```ruby
# Compiler generates temporary glyphs: temp_0, temp_1
when @cons @vowel1 @vowel2:
    @cons => temp_0,
    @vowel1 => temp_1
    # @vowel2 stays unchanged (last one)
```

**Generated Pass 2** (Final substitutions):
```ruby
when temp_0 temp_1 @vowel2:
    temp_0 => @cons.alt,
    temp_1 => @vowel1.alt,
    @vowel2 => @vowel2.alt
```

**Generated Pass 3** (Automatic cleanup):
```ruby
# Compiler automatically removes temporary glyphs
temp_0 => DEL
temp_1 => DEL
```

### Why Multi-pass?

AAT can only mark **one position** at a time for substitution. For multiple simultaneous substitutions, we need:
1. First pass: Mark positions with temporary glyphs
2. Second pass: Substitute based on markers
3. Cleanup pass: Remove temporary glyphs

The tool handles this **automatically** - users just write the logical rule.

---

## Validation Rules

### At Parse Time

1. ✅ **Syntax**: Valid context type and substitution syntax
2. ✅ **Class definitions**: Unique names, non-empty, defined before use
3. ✅ **Pattern length**: 1-10 elements per pattern
4. ✅ **Class sizes**: Matching sizes for position-wise expansion
5. ✅ **Target presence**: Targets exist in pattern (for `when` context)

### At Generation Time

1. ✅ **Glyph names**: All glyphs valid (checked against font)
2. ✅ **Expansion limit**: Total expansions reasonable
3. ✅ **State machine**: Can generate valid AAT state machine
4. ✅ **Temporary glyphs**: Sufficient unused glyph IDs available

---

## Error Messages

All errors include file name, line number, and helpful suggestions.

### Examples

**Undefined class:**
```
error: undefined class '@consonants'
  --> rules.txt:15:7
   |
15 | after @consonants: @vowels => @vowels.alt
   |       ^^^^^^^^^^^ class not defined
   |
   = note: define class with: @class consonants = ...
   = help: did you mean '@cons'?
```

**Pattern too long:**
```
error: pattern exceeds maximum length
  --> rules.txt:22:1
   |
22 | when a b c d e f g h i j k: a => a.alt
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ pattern has 11 elements
   |
   = note: maximum pattern length is 10 elements
   = help: split into multiple rules or use classes
```

**Class size mismatch:**
```
error: class size mismatch in substitution
  --> rules.txt:18:1
   |
18 | after @consonants: @vowels => @vowels_alt
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 
   |
   = note: @vowels has 5 glyphs
   = note: @vowels_alt has 3 glyphs
   = help: both classes must have same number of glyphs
```

**Target not in pattern:**
```
error: substitution target not in pattern
  --> rules.txt:25:1
   |
25 | when @cons @vowel1: @vowel2 => @vowel2.alt
   |                     ^^^^^^^ not in pattern
   |
   = note: pattern is: @cons @vowel1
   = note: @vowel2 does not appear in the pattern
   = help: targets must appear in the when pattern
```

---

## Command Line Usage

### From File (Recommended)

```bash
# MIF output
ot2aat contextsub --mif -i rules.txt -f "Contextual" --selector 0 -o output.mif

# ATIF output
ot2aat contextsub --atif -i rules.txt -f "Contextual" --selector 0 -o output.atif

# Output to stdout
ot2aat contextsub --mif -i rules.txt -f "Contextual" --selector 0
```

### Single Rule (Explicit Glyphs Only)

```bash
# Simple after context
ot2aat contextsub --mif \
    -r "after ka: aa => aa.alt" \
    -f "Contextual" --selector 0

# When context (single substitution)
ot2aat contextsub --mif \
    -r "when ka virama ssa: ka => ka.alt" \
    -f "Contextual" --selector 0
```

**Note:** Single-rule CLI does NOT support:
- Classes (use file input for classes)
- Multiple substitutions (use file input)
- Wildcards (use file input)

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
\** Exactly one of `-i` or `-r` required

---

## Complete Examples

### Example 1: Tamil Vowel Variants

**File: `tamil_contextual.txt`**

```ruby
# ============================================================================
# Tamil Contextual Vowel Forms
# ============================================================================

# Consonant groups for different vowel forms
@class group1_cons = uni0B95 uni0B99 uni0B9A uni0B9C uni0B9E uni0B9F uni0BA3
@class group2_cons = uni0BA4 uni0BA8 uni0BA9 uni0BAA uni0BAE uni0BAF uni0BB0

# Vowel signs
@class vowels = uni0BBF uni0BC0 uni0BC1 uni0BC2

# Alternate vowel forms
@class vowels_alt1 = uni0BBF.alt1 uni0BC0.alt1 uni0BC1.alt1 uni0BC2.alt1
@class vowels_alt2 = uni0BBF.alt2 uni0BC0.alt2 uni0BC1.alt2 uni0BC2.alt2

# Rules: Different vowel forms after different consonant groups
after @group1_cons: @vowels => @vowels_alt1
after @group2_cons: @vowels => @vowels_alt2
```

**Command:**
```bash
ot2aat contextsub --mif -i tamil_contextual.txt -f "Contextual" --selector 1 -o tamil_ctx.mif
```

### Example 2: Devanagari Pre-base Forms

**File: `devanagari_contextual.txt`**

```ruby
# ============================================================================
# Devanagari Contextual Forms
# ============================================================================

@class consonants = uni0915 uni0916 uni0917 uni0918 uni0919
@class vowels = uni093F uni0940 uni0941 uni0942
@class consonants_prevowel = uni0915.prevowel uni0916.prevowel uni0917.prevowel uni0918.prevowel uni0919.prevowel

# Before pre-base vowels, use special consonant forms
before @vowels: @consonants => @consonants_prevowel
```

### Example 3: Arabic Contextual Forms

**File: `arabic_contextual.txt`**

```ruby
# ============================================================================
# Arabic Contextual Letter Forms
# ============================================================================

@class letters = beh teh theh
@class letters_init = beh.init teh.init theh.init
@class letters_medi = beh.medi teh.medi theh.medi
@class letters_fina = beh.fina teh.fina theh.fina

# Initial forms after space
after space: @letters => @letters_init

# Final forms before space
before space: @letters => @letters_fina

# Medial forms between letters
between @letters and @letters: @letters => @letters_medi
```

### Example 4: Complex Pattern with Multiple Substitutions

**File: `complex_contextual.txt`**

```ruby
# ============================================================================
# Complex Contextual Substitution
# ============================================================================

@class cons = ka ga nga        # 3 glyphs
@class vowel1 = aa i ii        # 3 glyphs  
@class vowel2 = u uu e         # 3 glyphs

# All consonants have alternates
@class cons_alt = ka.alt ga.alt nga.alt
@class vowel1_alt = aa.alt i.alt ii.alt
@class vowel2_alt = u.alt uu.alt e.alt

# When we see consonant + vowel1 + vowel2, change all three
# Tool automatically generates multi-pass!
when @cons @vowel1 @vowel2:
    @cons => @cons_alt,
    @vowel1 => @vowel1_alt,
    @vowel2 => @vowel2_alt
```

**This generates 3 passes automatically:**
1. Mark positions with temp glyphs
2. Substitute based on markers
3. Cleanup temp glyphs

### Example 5: Wildcards

**File: `wildcard_contextual.txt`**

```ruby
# ============================================================================
# Wildcard Contextual Substitution
# ============================================================================

@class consonants = ka ga nga ca ja

# After any consonant, add .post suffix to all vowels
after @consonants: * => *.post

# Remove .oldstyle suffix after space
after space: *.oldstyle => *
```

---

## Best Practices

### 1. Organization

```ruby
# ✅ GOOD: Clear sections
# Classes first
@class consonants = ...
@class vowels = ...

# Rules grouped by context type
after @consonants: ...
after @consonants: ...

before @vowels: ...
before @vowels: ...
```

### 2. Class Naming

```ruby
# ✅ GOOD: Descriptive names
@class base_consonants = ...
@class consonants_prevowel = ...

# ❌ BAD: Unclear names
@class c1 = ...
@class c2 = ...
```

### 3. Comments

```ruby
# ✅ GOOD: Explain the context
# After base consonants, i-matra takes alternate form
# Visual: க + ி => கி (different position)
after @base_consonants: uni0BBF => uni0BBF.alt

# ❌ BAD: No explanation
after @base_consonants: uni0BBF => uni0BBF.alt
```

### 4. Rule Ordering

```ruby
# ✅ GOOD: Group related rules
# All "after" contexts together
after @group1: @vowels => @vowels.alt1
after @group2: @vowels => @vowels.alt2

# All "when" patterns together
when @cons @vowel: @cons => @cons.alt
```

### 5. Complexity Management

```ruby
# ✅ GOOD: Simple, clear rules
when @cons @vowel @mark: @cons => @cons.alt

# ⚠️  WARNING: Getting complex
when @a @b @c @d @e @f: @a => @a.alt, @b => @b.alt, ...

# ❌ TOO COMPLEX: Split into smaller rules
when @a @b @c @d @e @f @g @h @i @j: ... # At max limit!
```

---

## Pattern Verification

### Full Sequence Matching

All context types provide **full pattern verification**:

✅ **after context** - Verifies the preceding pattern is complete  
✅ **before context** - Verifies the following pattern is complete  
✅ **between context** - Verifies both surrounding patterns  
✅ **when context (single)** - Verifies the complete sequence before substituting  
✅ **when context (multiple)** - Uses multi-pass with pattern verification  

**Example:**
```ruby
when t h e: h => h.special
```

This will ONLY substitute `h` when it appears in the exact sequence "the". Typing:
- "the" → t + h.special + e ✅
- "th" → t + h (no change, pattern incomplete) ✅
- "he" → h + e (no change, no 't' before) ✅

**Implementation Note:** Single-target `when` rules are automatically decomposed 
into simpler `after`/`between` contexts internally for optimal performance and 
correctness. This is transparent to the user.

---

## Future Enhancements

### Planned for v2.0

**Unicode Properties:**
```ruby
@class consonants = \p{Script=Tamil} & \p{Lo}
```

**Ranges:**
```ruby
@class tamil_consonants = uni0B95..uni0BB9
```

**Set Operations:**
```ruby
@class special_cons = @all_cons -- @regular_cons
```

**Explicit Pass Control:**
```ruby
pass 1:
    when @cons @vowel: @cons => temp_marker

pass 2:
    when temp_marker @vowel: temp_marker => @cons.alt
```

---

## Summary

### Key Points

✅ **Four context types**: `after`, `before`, `between`, `when`  
✅ **Clean syntax**: No explicit marks, inferred from `=>`  
✅ **Multi-pass**: Automatic for complex rules  
✅ **Wildcards**: `* => *.suffix` supported  
✅ **Max pattern length**: 10 elements  
✅ **Class matching**: Position-wise like reorder  

### Quick Reference

```ruby
# Define classes
@class name = glyph1 glyph2 glyph3

# Simple contexts
after pattern: target => replacement
before pattern: target => replacement
between pattern1 and pattern2: target => replacement

# Full pattern matching
when pattern: target => replacement
when pattern: target1 => repl1, target2 => repl2

# Wildcards
after pattern: * => *.suffix
```

### Command Template

```bash
ot2aat contextsub --mif|--atif \
    -i rules.txt \
    -f "FeatureName" \
    --selector N \
    -o output.mif
```

---

**Version:** 1.0  
**Last Updated:** 2025-01-15