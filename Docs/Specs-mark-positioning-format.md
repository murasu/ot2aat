# Mark Positioning Format Specification v1.0

## Overview

This document specifies the input format for the `ot2aat markpos` command, which converts OpenType GPOS mark positioning and kerning adjustments into Apple Advanced Typography (AAT) kerx/ankr tables.

**Purpose:** Define rules for positioning marks relative to bases, marks relative to other marks, marks on ligatures, and contextual distance adjustments.

**Output formats:** 
- **ATIF** (Advanced Typography Input File) - Modern format, human-readable
- **KIF** (Kerning Input File) - MIF-style tab-separated format for kerning tables

**Supported positioning types:**
1. **Distance positioning** (contextual kerning adjustments)
2. **Mark-to-base** (marks attach to base glyphs)
3. **Mark-to-mark** (marks attach to other marks, stacking)
4. **Mark-to-ligature** (marks attach to ligature components)

---

## File Structure

A mark positioning rules file contains up to five sections in order:

```ruby
# ============================================================================
# 1. MARK CLASS DEFINITIONS (required for mark positioning)
# ============================================================================

@markclass MARK_CLASS_NAME <x, y>
    mark1 mark2 mark3 ...

# ============================================================================
# 2. DISTANCE POSITIONING (optional - contextual kerning)
# ============================================================================

# Simple pairs
@distance glyph1 glyph2 value
@distance @CLASS1 @CLASS2 value

# Class-based matrix
@matrix
    left @CLASS1 @CLASS2
    right @CLASS3 @CLASS4
    @CLASS1 @CLASS3 => value
    @CLASS1 @CLASS4 => value
    ...

# ============================================================================
# 3. MARK-TO-BASE (optional)
# ============================================================================

@base baseGlyph
    MARK_CLASS_1 <x1, y1>
    MARK_CLASS_2 <x2, y2>

# Or class-based
@class BASES = base1 base2 base3
@base @BASES
    MARK_CLASS_1 <x, y>
    MARK_CLASS_2 <x, y>

# ============================================================================
# 4. MARK-TO-MARK (optional - marks that other marks attach to)
# ============================================================================

@mark2mark markGlyph
    MARK_CLASS_1 <x1, y1>

@class BASE_MARKS = mark1 mark2 mark3
@mark2mark @BASE_MARKS
    MARK_CLASS_1 <x, y>

# ============================================================================
# 5. MARK-TO-LIGATURE (optional - ligatures with multiple attachment points)
# ============================================================================

@ligature ligGlyph
    MARK_CLASS_1 <x1, y1> <x2, y2> <x3, y3>  # One anchor per component
```

---

## Syntax Rules

### Comments and Whitespace

Same as other ot2aat formats:
- **Comments:** `#` to end of line
- **Blank lines:** Ignored
- **Indentation:** Recommended for readability, not required
- **Multiple spaces:** Treated as single separator

### Case Sensitivity

- **Glyph names:** Case-sensitive (`uni0E01` ≠ `UNI0E01`)
- **Class names:** Case-sensitive (`@MARKS` ≠ `@marks`)
- **Keywords:** Case-insensitive (`@markclass` = `@MARKCLASS`)

### Coordinates

Anchor coordinates use font units (integers):
- **Format:** `<x, y>` with spaces optional
- **Examples:** `<100, 150>`, `<-23, 0>`, `< 100 , 150 >`
- **Range:** Any integer value (positive or negative)

---

## Section 1: Mark Class Definitions

Define groups of marks that share the same anchor point.

### Syntax

```ruby
@markclass CLASS_NAME <x, y>
    mark1 mark2 mark3 ...
```

### Parameters

- **CLASS_NAME:** Descriptive name (e.g., `TOP_MARKS`, `BOTTOM_MARKS`)
- **<x, y>:** Anchor point coordinates shared by all marks in class
- **Glyphs:** Space-separated list of mark glyph names

### Examples

```ruby
# Thai top marks (vowels and tone marks)
@markclass TOP_MARKS <0, 148>
    uni0E48 uni0E49 uni0E4A uni0E4B

# Thai bottom marks (vowels)
@markclass BOTTOM_MARKS <-23, 0>
    uni0E38 uni0E39 uni0E3A

# Small stacking marks (for mark-to-mark)
@markclass SMALL_MARKS <0, 178>
    uni0E48.small uni0E49.small

# Arabic top marks
@markclass ARABIC_TOP <29, 112>
    uni064B uni064C uni064E uni064F uni0651 uni0652
```

### Validation Rules

✅ **Required:**
- Class name must be unique
- At least one glyph in class
- All glyph names must be valid
- Anchor coordinates must be integers

❌ **Invalid:**
```ruby
@markclass TOP_MARKS <0, 148>
    # Empty class - ERROR

@markclass TOP_MARKS <0, 148>
    mark1
@markclass TOP_MARKS <0, 150>  # Duplicate name - ERROR
    mark2
```

---

## Section 2: Distance Positioning

Contextual kerning adjustments between glyphs or classes.

Maps to: **Type 0 (pairs) or Type 2 (matrix) kerx subtables**

### Format 1: Simple Pairs

```ruby
@distance context target adjustment [direction]
```

**Parameters:**
- **context:** Glyph or `@CLASS` that triggers adjustment
- **target:** Glyph or `@CLASS` to adjust
- **adjustment:** Integer value in font units (negative = closer, positive = farther)
- **direction:** Optional `horizontal` (default) or `vertical`

**Examples:**

```ruby
# After uni0331, move lower marks closer by 50 units
@distance uni0331 uni0E38 -50
@distance uni0331 uni0E39 -50

# Class-based (expands to all pairs)
@class TALL_CONS = uni0E1B uni0E1D uni0E1F
@class LOWER_MARKS = uni0E38 uni0E39 uni0E3A
@distance @TALL_CONS @LOWER_MARKS -30

# Explicit direction
@distance uni0331 @LOWER_MARKS -50 horizontal

# Vertical adjustment
@distance @MARKS @TALL_CONS -20 vertical
```

### Format 2: Class-Based Matrix

For complex kerning patterns with multiple classes.

```ruby
@matrix
    left @CLASS1 @CLASS2 ...
    right @CLASS3 @CLASS4 ...
    @CLASS1 @CLASS3 => value
    @CLASS1 @CLASS4 => value
    @CLASS2 @CLASS3 => value
    ...
```

**Parameters:**
- **left:** List of classes for left-side glyphs
- **right:** List of classes for right-side glyphs
- **Pairs:** Each `@LEFT_CLASS @RIGHT_CLASS => value` defines adjustment

**Example:**

```ruby
@class lefts01 = uniFEDC.ar uniFEDB.ar uniFB91.ar uniFB90.ar
@class lefts02 = uni0631.ar uniFEAE.ar uni0632.ar uniFEB0.ar

@class rights00 = uniFE71.ar uniFE77.ar uniFE79.ar
@class rights01 = kasra_ar.isol.ar uniFE74.ar

@matrix
    left lefts01 lefts02
    right rights00 rights01
    
    rights00 lefts01 => -28
    rights01 lefts02 => 13
```

### Generated Output

**ATIF (Type 0 - Simple pairs):**
```swift
kerning list {
    layout is horizontal;
    kerning is horizontal;
    
    uni0331 + uni0E38 => -50;
    uni0331 + uni0E39 => -50;
}
```

**ATIF (Type 2 - Matrix):**
```swift
kerning matrix {
    layout is horizontal;
    kerning is horizontal;
    
    class lefts01 { uniFEDC.ar, uniFEDB.ar };
    class rights00 { uniFE71.ar, uniFE77.ar };
    
    left classes { lefts01 };
    right classes { rights00 };
    
    rights00 + lefts01 => -28;
}
```

---

## Section 3: Mark-to-Base

Define attachment points on base glyphs for mark classes.

Maps to: **Type 4 Attachment subtable** in kerx with anchor points

### Syntax: Individual Base

```ruby
@base baseGlyph
    MARK_CLASS_1 <x1, y1>
    MARK_CLASS_2 <x2, y2>
    ...
```

### Syntax: Class-Based (Uniform)

All bases in class get same attachment points:

```ruby
@class BASE_CLASS = base1 base2 base3
@base @BASE_CLASS
    MARK_CLASS_1 <x, y>
    MARK_CLASS_2 <x, y>
```

### Syntax: Class-Based (Per-Glyph Variation)

Different attachment points for each base:

```ruby
@class CONSONANTS = ka ga nga
@base @CONSONANTS
    ka: TOP_MARKS <100, 150>, BOTTOM_MARKS <100, 0>
    ga: TOP_MARKS <110, 150>, BOTTOM_MARKS <110, 0>
    nga: TOP_MARKS <120, 150>, BOTTOM_MARKS <120, 0>
```

### Examples

```ruby
# Thai - individual bases
@base uni0E01
    TOP_MARKS <169, 148>
    BOTTOM_MARKS <169, 0>

@base uni0E02
    TOP_MARKS <170, 148>
    BOTTOM_MARKS <170, 0>

# Thai - class-based uniform
@class TALL_CONS = uni0E1B uni0E1D uni0E1F
@base @TALL_CONS
    TOP_MARKS <172, 148>
    BOTTOM_MARKS <172, 0>

# Arabic - per-glyph variation
@class BASES = uni0621.ar uni0627.ar uni0623.ar
@base @BASES
    uni0621.ar: ARABIC_TOP <65, 91>, ARABIC_BOT <52, 7>
    uni0627.ar: ARABIC_TOP <31, 176>, ARABIC_BOT <31, 7>
    uni0623.ar: ARABIC_TOP <33, 164>, ARABIC_BOT <33, 7>
```

### Generated ATIF

```swift
control point kerning subtable {
    layout is horizontal;
    kerning is horizontal;
    uses anchor points;
    
    // Mark anchors (auto-indexed)
    anchor uni0E48[0] := (0, 148);
    anchor uni0E49[0] := (0, 148);
    
    anchor uni0E38[1] := (-23, 0);
    anchor uni0E39[1] := (-23, 0);
    
    // Base anchors
    anchor uni0E01[0] := (169, 148);
    anchor uni0E01[1] := (169, 0);
    
    class bases { uni0E01, uni0E02 };
    class marksTop { uni0E48, uni0E49 };
    class marksBot { uni0E38, uni0E39 };
    
    state Start {
        bases: sawBase;
    }
    
    state withBase {
        marksTop: sawMarkTop;
        marksBot: sawMarkBot;
        bases: sawBase;
    }
    
    transition sawBase {
        change state to withBase;
        mark glyph;
    }
    
    transition sawMarkTop {
        change state to withBase;
        kerning action: snapMarkTop;
    }
    
    transition sawMarkBot {
        change state to withBase;
        kerning action: snapMarkBot;
    }
    
    anchor point action snapMarkTop {
        marked glyph point: 0;
        current glyph point: 0;
    }
    
    anchor point action snapMarkBot {
        marked glyph point: 1;
        current glyph point: 1;
    }
}
```

---

## Section 4: Mark-to-Mark

Define marks that can have other marks attached to them (mark stacking).

Maps to: **Type 4 Attachment subtable** in kerx

### Key Concept

A mark glyph can serve **two roles**:
1. **Attaching mark** (defined in `@markclass`)
2. **Base mark** (defined in `@mark2mark`)

**Example:** Thai small tone marks stack on top of vowel marks:
- `uni0E38` is in `BOTTOM_MARKS` (attaches to bases)
- `uni0E38` also acts as base for `SMALL_MARKS` (has attachment point)

### Syntax: Individual Mark

```ruby
@mark2mark markGlyph
    MARK_CLASS_1 <x1, y1>
```

### Syntax: Class-Based

```ruby
@class BASE_MARKS = mark1 mark2 mark3
@mark2mark @BASE_MARKS
    MARK_CLASS_1 <x, y>
```

### Examples

```ruby
# Thai mark stacking
@markclass BOTTOM_MARKS <-23, 0>
    uni0E38 uni0E39 uni0E3A

@markclass SMALL_MARKS <0, 178>
    uni0E48.small uni0E49.small

# These bottom marks can have small marks stacked on them
@mark2mark uni0E38
    SMALL_MARKS <-23, -70>

@mark2mark uni0E39
    SMALL_MARKS <-23, -68>

@mark2mark uni0E3A
    SMALL_MARKS <-23, -48>

# Or class-based if they share attachment point
@class STACKABLE = uni0E48 uni0E49 uni0E4A
@mark2mark @STACKABLE
    SMALL_MARKS <0, 178>
```

### Arabic Example (Complex Stacking)

```ruby
@markclass LOWER_MARKS <-23, 0>
    uni0E38 uni0E39 uni0E3A

# These marks can act as bases for other marks
@mark2mark uni0E38
    LOWER_MARKS <-23, -70>  # Another mark from same class!

@mark2mark uni0E39
    LOWER_MARKS <-23, -68>

@mark2mark uni0E3A
    LOWER_MARKS <-23, -48>
```

This allows: `base + uni0E38 + uni0E39` where `uni0E39` attaches to `uni0E38`.

### Generated ATIF

```swift
control point kerning subtable {
    layout is horizontal;
    kerning is horizontal;
    uses anchor points;
    
    // Attaching mark anchors (index 0)
    anchor uni0E48.small[0] := (0, 178);
    anchor uni0E49.small[0] := (0, 178);
    
    // Base mark anchors (index 1)
    anchor uni0E38[1] := (-23, -70);
    anchor uni0E39[1] := (-23, -68);
    anchor uni0E3A[1] := (-23, -48);
    
    class bases { uni0E38, uni0E39, uni0E3A };
    class marks { uni0E48.small, uni0E49.small };
    
    state Start {
        bases: sawBase;
    }
    
    state withBase {
        marks: sawMark;
        bases: sawBase;
    }
    
    transition sawBase {
        change state to withBase;
        mark glyph;
    }
    
    transition sawMark {
        change state to Start;
        kerning action: snapMark;
    }
    
    anchor point action snapMark {
        marked glyph point: 1;
        current glyph point: 0;
    }
}
```

---

## Section 5: Mark-to-Ligature

Define attachment points for each component of a ligature.

Maps to: **Type 4 Attachment subtable** with DEL detection

### Syntax

```ruby
@ligature ligatureGlyph
    MARK_CLASS <x1, y1> <x2, y2> <x3, y3> ...
```

**One anchor per ligature component.** Number of anchors = number of components.

### Examples

```ruby
# Simple fi ligature (2 components)
@ligature f_i
    TOP_MARKS <100, 150> <250, 150>

# ffi ligature (3 components)
@ligature f_f_i
    TOP_MARKS <100, 150> <200, 150> <300, 150>

# Arabic lam-alef ligatures (2 components with top and bottom)
@ligature uniFEFB.ar
    ARABIC_BOT <149, 7> <85, 7>
    ARABIC_TOP <150, 176> <85, 111>

# Complex ligature (4 components)
@ligature uniFDF2.ar
    ARABIC_BOT <326, 7> <264, 7> <172, 7> <49, 7>
    ARABIC_TOP <326, 182> <261, 182> <170, 182> <52, 113>
```

### DEL Detection Mechanism

**How AAT detects ligature components:**

When a ligature is formed in AAT (e.g., `f + i => fi`), the glyph stream becomes:
```
<fi> <DEL>
```

For `f + f + i => ffi`:
```
<ffi> <DEL> <DEL>
```

**The state machine uses DEL glyphs to track component boundaries:**

```ruby
state SLig {
    DEL: sawLigDel;        # Transition to next component
    marks: sawMark1;       # Marks attach to current component
}

state SLig2 {
    DEL: sawLigDel2;       # Another component boundary
    marks: sawMark2;       # Marks attach to second component
}
```

**You don't handle this manually** - the tool generates the correct state machine automatically.

### Generated ATIF (Simplified)

```swift
control point kerning subtable {
    layout is horizontal;
    kerning is horizontal;
    uses anchor points;
    scan glyphs backward;
    
    // Mark anchors
    anchor uni0E48[0] := (0, 148);
    
    // Ligature component anchors
    anchor f_i[0] := (100, 150);  // Component 1
    anchor f_i[1] := (250, 150);  // Component 2
    
    class ligs { f_i };
    class marks { uni0E48, uni0E49 };
    
    state Start {
        ligs: sawLig;
    }
    
    state SLig {
        DEL: sawLigDel;      # Detect component boundary
        marks: sawMark1;
        ligs: sawLig;
    }
    
    state SLig2 {
        marks: sawMark2;
        ligs: sawLig;
    }
    
    transition sawLig {
        change state to SLig;
        mark glyph;
    }
    
    transition sawLigDel {
        change state to SLig2;  # Move to next component
    }
    
    transition sawMark1 {
        change state to SLig;
        kerning action: snapMark1;
    }
    
    transition sawMark2 {
        change state to SLig2;
        kerning action: snapMark2;
    }
    
    anchor point action snapMark1 {
        marked glyph point: 0;  # Component 1
        current glyph point: 0;
    }
    
    anchor point action snapMark2 {
        marked glyph point: 1;  # Component 2
        current glyph point: 0;
    }
}
```

---

## Anchor Point Auto-Indexing

**Critical:** You never specify anchor point indices. The tool auto-assigns them based on declaration order and usage.

### Indexing Rules

**For marks (in `@markclass`):**
- First mark class declared → index 0
- Second mark class declared → index 1
- Third mark class declared → index 2
- etc.

**For bases (in `@base`):**
- Same indices as their corresponding mark classes
- If base has `TOP_MARKS <x, y>` and `TOP_MARKS` is index 0, base anchor is also index 0

**For mark-to-mark:**
- Attaching marks use their original index (from `@markclass`)
- Base marks get new indices starting after all mark classes

**For ligatures:**
- Component 1 uses mark class index
- Component 2 uses mark class index + 1
- Component 3 uses mark class index + 2
- etc.

### Example: Complete Indexing

```ruby
# Mark class declarations (auto-indexed 0, 1, 2)
@markclass TOP_MARKS <0, 148>        # Index 0
    uni0E48 uni0E49

@markclass BOTTOM_MARKS <-23, 0>     # Index 1
    uni0E38 uni0E39

@markclass SMALL_MARKS <0, 178>      # Index 2
    uni0E48.small

# Mark-to-base (uses indices 0 and 1)
@base uni0E01
    TOP_MARKS <169, 148>      # Index 0 (matches TOP_MARKS)
    BOTTOM_MARKS <169, 0>     # Index 1 (matches BOTTOM_MARKS)

# Mark-to-mark (gets new index 3)
@mark2mark uni0E38
    SMALL_MARKS <-23, -70>    # Mark index 2, base index 3

# Ligature (uses indices 0 and 1 for component 1, 2 and 3 for component 2)
@ligature f_i
    TOP_MARKS <100, 150> <250, 150>     # Indices 0 (comp1), 1 (comp2)
```

### Generated Anchor Declarations

```swift
// Marks (indices 0, 1, 2)
anchor uni0E48[0] := (0, 148);
anchor uni0E49[0] := (0, 148);
anchor uni0E38[1] := (-23, 0);
anchor uni0E39[1] := (-23, 0);
anchor uni0E48.small[2] := (0, 178);

// Bases (indices 0, 1)
anchor uni0E01[0] := (169, 148);
anchor uni0E01[1] := (169, 0);

// Mark-to-mark (mark index 2, base index 3)
anchor uni0E38[3] := (-23, -70);

// Ligature (component 1: indices 0, 1; component 2: indices 2, 3)
anchor f_i[0] := (100, 150);
anchor f_i[2] := (250, 150);
```

---

## Multi-Table Generation

The tool generates multiple subtables in the correct order for AAT processing.

### Table Order in ATIF/KIF

```
Table 0: Distance positioning (Type 0 simple pairs)
Table 1: Distance positioning (Type 2 class matrix) - if used
Table 2: Mark-to-base (primary attachment points)
Table 3: Mark-to-base (additional mark classes) - if needed
Table 4: Mark-to-mark (stacking)
Table 5: Mark-to-ligature (component 1)
Table 6: Mark-to-ligature (component 2) - if multiple mark classes
...
```

### Grouping Strategy

**Mark-to-base:** One subtable per set of mark classes that share the same bases.

**Mark-to-mark:** One subtable per stacking relationship.

**Mark-to-ligature:** One subtable per ligature set (grouped by which mark classes they use).

### Example Output Structure

```ruby
// Input
@markclass TOP <0, 148>
    m1 m2
@markclass BOT <0, 0>
    m3 m4

@distance g1 g2 -50

@base b1
    TOP <100, 150>
    BOT <100, 0>

@mark2mark m1
    TOP <0, 178>

@ligature lig1
    TOP <100, 150> <200, 150>
```

**Generated:**
```
Table 0: Distance (g1, g2, -50)
Table 1: Mark-to-base (TOP and BOT on b1)
Table 2: Mark-to-mark (TOP stacks on m1)
Table 3: Mark-to-ligature (TOP on lig1 components)
```

---

## Validation Rules

### Parse-Time Validation

✅ **Syntax checks:**
- Valid keywords (`@markclass`, `@base`, `@mark2mark`, `@ligature`, `@distance`, `@matrix`)
- Proper anchor syntax `<x, y>` with integers
- Valid glyph names (no spaces, special chars)
- Class references start with `@`

✅ **Semantic checks:**
- Mark classes defined before use
- No duplicate mark class names
- No duplicate base definitions for same glyph
- Ligature component count matches mark class usage

✅ **Logical checks:**
- At least one glyph in each class
- Mark classes defined if using @base/@mark2mark/@ligature
- Distance adjustments are integers
- Anchor coordinates are integers

### Generation-Time Validation

✅ **Font checks:**
- All glyph names exist in font
- No missing glyphs

✅ **AAT limits:**
- Maximum 255 mark classes (AAT limit)
- Maximum component count per ligature
- State table complexity within limits

✅ **Index checks:**
- Anchor indices don't overflow
- Sufficient anchor points available

---

## Error Messages

All errors include file name, line number, and helpful suggestions.

### Example: Undefined Mark Class

```
error: undefined mark class '@TOP_MARKS'
  --> marks.txt:25:5
   |
25 | @base uni0E01
   |     TOP_MARKS <169, 148>
   |     ^^^^^^^^^ class not defined
   |
   = note: define mark class with: @markclass TOP_MARKS <x, y>
   = help: did you mean '@TOP_MARK'?
```

### Example: Invalid Anchor Syntax

```
error: invalid anchor coordinate syntax
  --> marks.txt:15:20
   |
15 |     TOP_MARKS <100 150>
   |                    ^^^ missing comma between coordinates
   |
   = note: anchor format is <x, y> with comma separator
   = help: correct syntax: <100, 150>
```

### Example: Component Count Mismatch

```
error: ligature component count mismatch
  --> marks.txt:40:1
   |
40 | @ligature f_i
41 |     TOP_MARKS <100, 150> <200, 150> <300, 150>
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 
   |
   = note: 'f_i' ligature has 2 components (f + i)
   = note: but 3 anchor points provided
   = help: provide exactly 2 anchor points: <x1, y1> <x2, y2>
```

### Example: Same Glyph in Multiple Mark Classes

```
error: glyph appears in multiple mark classes
  --> marks.txt:18:5
   |
10 | @markclass TOP_MARKS <0, 148>
11 |     uni0E48 uni0E49
   |     ------- first defined here
   |
18 | @markclass SIDE_MARKS <10, 100>
19 |     uni0E48 uni0E4C
   |     ^^^^^^^ also defined here
   |
   = note: each mark glyph can only be in one mark class
   = help: remove uni0E48 from one of the mark classes
```

---

## Command Line Usage

### Basic Usage

```bash
# ATIF output
ot2aat markpos --atif -i marks.txt -f "MarkPos" --selector 0 -o output.atif

# KIF output (MIF-style)
ot2aat markpos --mif -i marks.txt -f "MarkPos" --selector 0 -o output.kif

# Output to stdout
ot2aat markpos --atif -i marks.txt -f "MarkPos" --selector 0
```

### Options

| Option | Short | Required | Description |
|--------|-------|----------|-------------|
| `--mif` | | Yes* | Output KIF/MIF format |
| `--atif` | | Yes* | Output ATIF format |
| `-i, --input` | `-i` | Yes | Input rules file |
| `-o, --output` | `-o` | No | Output file (default: stdout) |
| `-f, --feature` | `-f` | Yes | Feature name |
| `--selector` | | Yes | Selector number |
| `-h, --help` | `-h` | No | Show help |

\* Exactly one of `--mif` or `--atif` required

### Examples

```bash
# Thai mark positioning
ot2aat markpos --atif \
    -i thai_marks.txt \
    -f "MarkPositioning" \
    --selector 0 \
    -o thai_marks.atif

# Arabic with distance adjustments
ot2aat markpos --atif \
    -i arabic_marks.txt \
    -f "ArabicMarks" \
    --selector 1 \
    -o arabic_marks.atif

# KIF output for custom tool
ot2aat markpos --mif \
    -i marks.txt \
    -f "Marks" \
    --selector 0 \
    -o marks.kif
```

---

## Complete Examples

### Example 1: Thai Mark Positioning

**File: `thai_marks.txt`**

```ruby
# ============================================================================
# Thai Mark Positioning
# ============================================================================

# ----------------------------------------------------------------------------
# MARK CLASSES
# ----------------------------------------------------------------------------

# Top marks (tone marks)
@markclass TOP_MARKS <0, 148>
    uni0E48 uni0E49 uni0E4A uni0E4B

# Bottom marks (vowels)
@markclass BOTTOM_MARKS <-23, 0>
    uni0E38 uni0E39 uni0E3A

# Small stacking marks
@markclass SMALL_MARKS <0, 178>
    uni0E48.small uni0E49.small

# ----------------------------------------------------------------------------
# MARK-TO-BASE
# ----------------------------------------------------------------------------

# Individual bases
@base uni0E01
    TOP_MARKS <169, 148>
    BOTTOM_MARKS <169, 0>

@base uni0E02
    TOP_MARKS <170, 148>
    BOTTOM_MARKS <170, 0>

# Class-based for similar glyphs
@class TALL_CONS = uni0E1B uni0E1D uni0E1F
@base @TALL_CONS
    TOP_MARKS <172, 148>
    BOTTOM_MARKS <172, 0>

# ----------------------------------------------------------------------------
# MARK-TO-MARK (bottom marks can have small marks stacked)
# ----------------------------------------------------------------------------

@mark2mark uni0E38
    SMALL_MARKS <-23, -70>

@mark2mark uni0E39
    SMALL_MARKS <-23, -68>

@mark2mark uni0E3A
    SMALL_MARKS <-23, -48>

# ----------------------------------------------------------------------------
# DISTANCE POSITIONING
# ----------------------------------------------------------------------------

# After tall consonants, adjust lower marks
@distance @TALL_CONS @BOTTOM_MARKS -30
```

**Command:**
```bash
ot2aat markpos --atif -i thai_marks.txt -f "ThaiMarks" --selector 0 -o thai.atif
```

---

### Example 2: Arabic Mark Positioning with Distance

**File: `arabic_marks.txt`**

```ruby
# ============================================================================
# Arabic Mark Positioning
# ============================================================================

# ----------------------------------------------------------------------------
# MARK CLASSES
# ----------------------------------------------------------------------------

@markclass ARABIC_TOP <29, 112>
    uni064B uni064C uni064E uni064F uni0651 uni0652 uni0654

@markclass ARABIC_BOT <29, 7>
    uni064D uni0650 uni0655 uni0656

# ----------------------------------------------------------------------------
# DISTANCE POSITIONING (Type 0 - Simple pairs)
# ----------------------------------------------------------------------------

@distance uni0660.pnum.ar uni0666.pnum.ar -10
@distance uni0660.pnum.ar uni0667.pnum.ar -9
@distance uni0662.pnum.ar uni0668.pnum.ar -15

# ----------------------------------------------------------------------------
# DISTANCE POSITIONING (Type 2 - Class matrix)
# ----------------------------------------------------------------------------

@class lefts01 = uniFEDC.ar uniFEDB.ar uniFB91.ar
@class lefts02 = uni0631.ar uniFEAE.ar uni0632.ar

@class rights00 = uniFE71.ar uniFE77.ar uniFE79.ar
@class rights01 = kasra_ar.isol.ar uniFE74.ar

@matrix
    left lefts01 lefts02
    right rights00 rights01
    
    rights00 lefts01 => -28
    rights01 lefts02 => 13

# ----------------------------------------------------------------------------
# MARK-TO-BASE
# ----------------------------------------------------------------------------

@class BASES = uni0621.ar uni0627.ar uni0623.ar
@base @BASES
    uni0621.ar: ARABIC_TOP <65, 91>, ARABIC_BOT <52, 7>
    uni0627.ar: ARABIC_TOP <31, 176>, ARABIC_BOT <31, 7>
    uni0623.ar: ARABIC_TOP <33, 164>, ARABIC_BOT <33, 7>

# ----------------------------------------------------------------------------
# MARK-TO-MARK
# ----------------------------------------------------------------------------

# Bottom marks can have other marks stacked
@class BOT_BASE = uni064D uni0650 uni0655
@mark2mark @BOT_BASE
    ARABIC_TOP <29, -32>

# ----------------------------------------------------------------------------
# MARK-TO-LIGATURE
# ----------------------------------------------------------------------------

# Lam-alef ligatures (2 components)
@ligature uniFEFB.ar
    ARABIC_BOT <149, 7> <85, 7>
    ARABIC_TOP <150, 176> <85, 111>

@ligature uniFEFC.ar
    ARABIC_BOT <149, 7> <85, 7>
    ARABIC_TOP <150, 176> <85, 111>

# Allah ligature (4 components!)
@ligature uniFDF2.ar
    ARABIC_BOT <326, 7> <264, 7> <172, 7> <49, 7>
    ARABIC_TOP <326, 182> <261, 182> <170, 182> <52, 113>
```

**Command:**
```bash
ot2aat markpos --atif -i arabic_marks.txt -f "ArabicMarks" --selector 1 -o arabic.atif
```

---

### Example 3: Hebrew Mark Positioning

**File: `hebrew_marks.txt`**

```ruby
# ============================================================================
# Hebrew Mark Positioning
# ============================================================================

# ----------------------------------------------------------------------------
# MARK CLASSES
# ----------------------------------------------------------------------------

@markclass NIQQUD <0, 0>
    uni05B0 uni05B1 uni05B2 uni05B3 uni05B4 uni05B5 uni05B6 uni05B7
    uni05B8 uni05B9 uni05BA uni05BB

@markclass CANTILLATION <0, -52>
    uni0591 uni0592 uni0593 uni0594

# ----------------------------------------------------------------------------
# MARK-TO-BASE
# ----------------------------------------------------------------------------

@class CONSONANTS = uni05D0 uni05D1 uni05D2 uni05D3 uni05D4
@base @CONSONANTS
    uni05D0: NIQQUD <0, -52>, CANTILLATION <0, -100>
    uni05D1: NIQQUD <-11, -6>, CANTILLATION <-11, -54>
    uni05D2: NIQQUD <-8, -10>, CANTILLATION <-8, -58>
    uni05D3: NIQQUD <0, 0>, CANTILLATION <0, -48>
    uni05D4: NIQQUD <0, -52>, CANTILLATION <0, -100>

# ----------------------------------------------------------------------------
# MARK-TO-MARK (cantillation stacks on niqqud)
# ----------------------------------------------------------------------------

@class NIQQUD_BASE = uni05B4 uni05B5 uni05B6 uni05B7
@mark2mark @NIQQUD_BASE
    CANTILLATION <0, -30>
```

**Command:**
```bash
ot2aat markpos --atif -i hebrew_marks.txt -f "HebrewMarks" --selector 0 -o hebrew.atif
```

---

## Best Practices

### 1. Organization

```ruby
# ✅ GOOD: Clear sections with comments
# Mark classes first
@markclass TOP <0, 148>
    ...

# Distance adjustments
@distance ...

# Mark-to-base
@base ...

# Mark-to-mark
@mark2mark ...

# Ligatures
@ligature ...
```

### 2. Naming Conventions

```ruby
# ✅ GOOD: Descriptive names
@markclass TOP_MARKS <0, 148>
@markclass BOTTOM_MARKS <0, 0>
@markclass SMALL_STACKING <0, 178>

# ❌ BAD: Unclear names
@markclass M1 <0, 148>
@markclass M2 <0, 0>
```

### 3. Comments for Coordinates

```ruby
# ✅ GOOD: Explain positioning logic
@base uni0E01
    TOP_MARKS <169, 148>      # Above descender height
    BOTTOM_MARKS <169, 0>     # At baseline

# ✅ GOOD: Note special cases
@mark2mark uni0E38
    SMALL_MARKS <-23, -70>    # Adjusted for double stacking
```

### 4. Class-Based When Possible

```ruby
# ✅ GOOD: Group similar glyphs
@class TALL_CONS = uni0E1B uni0E1D uni0E1F
@base @TALL_CONS
    TOP_MARKS <172, 148>
    BOTTOM_MARKS <172, 0>

# ❌ BAD: Repetitive individual definitions
@base uni0E1B
    TOP_MARKS <172, 148>
    BOTTOM_MARKS <172, 0>
@base uni0E1D
    TOP_MARKS <172, 148>
    BOTTOM_MARKS <172, 0>
# ... etc
```

### 5. Test with Real Text

Always test with representative text samples:
- Single marks on bases
- Multiple marks stacked
- Marks on ligatures
- Edge cases (no base before mark, etc.)

---

## Comparison with OpenType

### Similarities

✅ **Mark classes with anchors** - Same concept as OT `markClass`  
✅ **Base anchors** - Same concept as OT `pos base`  
✅ **Mark-to-mark** - Same concept as OT `pos mark`  
✅ **Ligature components** - Same concept as OT component indices  

### Differences

🔄 **Anchor indexing** - AAT uses explicit indices, we auto-assign  
🔄 **Distance positioning** - OT uses GPOS lookup Type 2, we use kerx  
🔄 **File format** - Simpler, more declarative than AFDKO  
🔄 **Component detection** - AAT uses DEL glyphs, OT uses explicit component count  

### Example Comparison

**OpenType (AFDKO):**
```
markClass uni0E48 <anchor 0 148> @TOP;
pos base uni0E01 <anchor 169 148> mark @TOP;
```

**Our format:**
```ruby
@markclass TOP_MARKS <0, 148>
    uni0E48

@base uni0E01
    TOP_MARKS <169, 148>
```

**Advantage:** More readable, less repetitive, auto-indexes anchors.

---

## Limitations and Known Issues

### Current Limitations

1. **No baseline adjustment** - All anchors relative to glyph origin
2. **No cursive attachment** - Only mark positioning supported
3. **Maximum 255 mark classes** - AAT limitation
4. **Component detection via DEL** - Requires proper ligature formation

### Workarounds

**For complex stacking:** Use multiple mark-to-mark rules in sequence.

**For missing features:** Combine with contextual substitution to pre-process glyphs.

**For component detection:** Ensure ligatures are properly formed in morx tables before kerx processing.

---

## Future Enhancements

### Planned for v2.0

**Unicode properties in classes:**
```ruby
@markclass MARKS <0, 0>
    \p{Mn}  # All non-spacing marks
```

**Baseline-relative positioning:**
```ruby
@base uni0E01
    TOP_MARKS <169, 148> baseline=hanging
```

**Named anchor reuse:**
```ruby
@anchor TOP_ANCHOR <100, 150>
@base base1
    TOP_MARKS @TOP_ANCHOR
```

**Conditional mark positioning:**
```ruby
@base uni0E01
    TOP_MARKS <169, 148> when after @TALL_CONS
    TOP_MARKS <169, 130> otherwise
```

---

## Summary

### Key Points

✅ **Four types in one file:** Distance, mark-to-base, mark-to-mark, mark-to-ligature  
✅ **Auto-indexing:** Never specify anchor indices manually  
✅ **Class-based:** Efficient grouping of similar glyphs  
✅ **DEL detection:** Automatic ligature component handling  
✅ **Clean syntax:** Declarative, easy to read and maintain  

### Quick Reference

```ruby
# Mark classes
@markclass NAME <x, y>
    glyph1 glyph2 ...

# Distance
@distance context target value
@matrix
    left @CLASS1 @CLASS2
    right @CLASS3 @CLASS4
    @CLASS1 @CLASS3 => value

# Mark-to-base
@base glyph
    MARK_CLASS_1 <x, y>
    MARK_CLASS_2 <x, y>

# Mark-to-mark
@mark2mark glyph
    MARK_CLASS <x, y>

# Ligature
@ligature glyph
    MARK_CLASS <x1, y1> <x2, y2> ...
```

### Command Template

```bash
ot2aat markpos --mif|--atif \
    -i rules.txt \
    -f "FeatureName" \
    --selector N \
    -o output.atif
```

---

**Version:** 1.0  
**Last Updated:** 2025-01-15  
**Author:** Muthu Nedumaran