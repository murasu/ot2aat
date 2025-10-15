Absolutely! Let me update the specification to reflect the new `.aar` format with semantic grouping and per-mark anchors.

# Mark Positioning Format Specification v2.0 (Updated)

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
# 1. MARK GROUP DEFINITIONS (required for mark positioning)
# ============================================================================

@mark_group SEMANTIC_NAME
    mark1 <x1, y1>
    mark2 <x2, y2>
    mark3 <x3, y3>
    ...

# ============================================================================
# 2. DISTANCE POSITIONING (optional - contextual kerning)
# ============================================================================

# Simple pairs
@distance glyph1 glyph2 value [direction]
@distance @CLASS1 @CLASS2 value [direction]

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
    SEMANTIC_1 <x1, y1>
    SEMANTIC_2 <x2, y2>

# Or class-based
@class BASES = base1 base2 base3
@base @BASES
    SEMANTIC_1 <x, y>
    SEMANTIC_2 <x, y>

# ============================================================================
# 4. MARK-TO-MARK (optional - marks that other marks attach to)
# ============================================================================

@mark2mark markGlyph
    SEMANTIC_1 <x1, y1>

@class BASE_MARKS = mark1 mark2 mark3
@mark2mark @BASE_MARKS
    SEMANTIC_1 <x, y>

# ============================================================================
# 5. MARK-TO-LIGATURE (optional - ligatures with multiple attachment points)
# ============================================================================

@ligature ligGlyph
    SEMANTIC_1 <x1, y1> <x2, y2> <x3, y3>  # One anchor per component
```

---

## Key Concepts: AAT Semantic Model

### OpenType vs AAT Anchor Philosophy

**OpenType Model:**
- Marks grouped into classes by **behavior**
- All marks in a class share **one anchor coordinate**
- Example: `markClass [uni0E48 uni0E49] <anchor 0 148> @TOP_MARKS;`

**AAT Semantic Model (Our Format):**
- Marks grouped by **semantic attachment point** (where they attach)
- Each mark has its **own anchor coordinate**
- Example:
```ruby
@mark_group TOP
    uni0E48 <-23, 137>
    uni0E49 <-23, 137>
```

### Semantic Group Names

Use descriptive names that indicate **where** marks attach:

**Standard names:**
- `BOTTOM` - Marks that attach below (subscripts, lower vowels)
- `TOP` - Marks that attach above (superscripts, upper vowels, tone marks)
- `MIDDLE` - Marks that attach at mid-height

**Custom names:**
- `ATTACHMENT_0`, `ATTACHMENT_1`, ... for scripts with many attachment points
- Script-specific: `NUKTA`, `REPH`, `VIRAMA` (Indic scripts)

**Ordering matters:** Groups are sorted alphabetically with special ordering:
- `BOTTOM` < `MIDDLE` < `TOP` < `ATTACHMENT_*`
- This determines AAT anchor indices

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
- **Semantic names:** Case-sensitive (`BOTTOM` ≠ `bottom`)
- **Class names:** Case-sensitive (`@MARKS` ≠ `@marks`)
- **Keywords:** Case-insensitive (`@mark_group` = `@MARK_GROUP`)

### Coordinates

Anchor coordinates use font units (integers):
- **Format:** `<x, y>` with spaces optional
- **Examples:** `<100, 150>`, `<-23, 0>`, `< 100 , 150 >`
- **Range:** Any integer value (positive or negative)

---

## Section 1: Mark Group Definitions

Define semantic groups of marks where each mark has its own anchor point.

### Syntax

```ruby
@mark_group SEMANTIC_NAME
    mark1 <x1, y1>
    mark2 <x2, y2>
    mark3 <x3, y3>
    ...
```

### Parameters

- **SEMANTIC_NAME:** Descriptive name (e.g., `TOP`, `BOTTOM`, `MIDDLE`)
- **mark1, mark2, ...:** Glyph names
- **<x, y>:** Individual anchor coordinates for each mark

### Examples

```ruby
# Thai top marks (each mark has its own coordinates)
@mark_group TOP
    uni0E48 <-23, 137>
    uni0E49 <-23, 137>
    uni0E4A <-23, 137>
    uni0E4B <-23, 137>
    uni0E31 <-23, 137>
    uni0E31.narrow <-58, 137>

# Thai bottom marks (different coordinates per mark)
@mark_group BOTTOM
    uni0E38 <-23, 0>
    uni0E38.small <-21, -42>
    uni0E39 <-23, 0>
    uni0E39.small <-21, -42>
    uni0E3A <-23, 0>

# Arabic top marks
@mark_group TOP
    uni064B <29, 112>
    uni064C <41, 112>
    uni064E <29, 112>
    uni064F <29, 112>
    uni0651 <36, 112>

# Arabic bottom marks
@mark_group BOTTOM
    uni064D <29, 7>
    uni0650 <29, 7>
    uni0655 <21, 7>
```

### Why Per-Mark Anchors?

**Flexibility:** Different marks in the same semantic group can have different coordinates:
```ruby
@mark_group TOP
    uni0E31 <-23, 137>        # Regular spacing
    uni0E31.narrow <-58, 137> # Narrower variant, different X
```

**Mark Deduplication:** If the same mark appears in multiple OpenType classes (e.g., for mark-to-base and mark-to-mark), it appears only once in the semantic group.

### Validation Rules

✅ **Required:**
- Semantic name must be unique
- At least one mark in group
- All glyph names must be valid
- Each mark has anchor coordinates
- No duplicate marks within same group

❌ **Invalid:**
```ruby
@mark_group TOP
    # Empty group - ERROR

@mark_group TOP
    uni0E48 <-23, 137>
@mark_group TOP  # Duplicate name - ERROR
    uni0E49 <-23, 137>

@mark_group BOTTOM
    uni0E38 <-23, 0>
    uni0E38 <-23, -10>  # Duplicate mark - ERROR
```

---

## Section 2: Distance Positioning

*(Same as before, no changes needed)*

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
# After uni0331, move lower marks closer
@distance uni0331 uni0E38 -38 vertical
@distance uni0331 uni0E39 -38 vertical

# Class-based (expands to all pairs)
@class TALL_CONS = uni0E1B uni0E1D uni0E1F
@class LOWER_MARKS = uni0E38 uni0E39 uni0E3A
@distance @TALL_CONS @LOWER_MARKS -30 horizontal
```

### Format 2: Class-Based Matrix

```ruby
@matrix
    left @CLASS1 @CLASS2 ...
    right @CLASS3 @CLASS4 ...
    @CLASS1 @CLASS3 => value
    @CLASS1 @CLASS4 => value
    ...
```

**Example:**

```ruby
@class lefts01 = uniFEDC.ar uniFEDB.ar
@class rights00 = uniFE71.ar uniFE77.ar

@matrix
    left lefts01
    right rights00
    rights00 lefts01 => -28
```

---

## Section 3: Mark-to-Base

Define attachment points on base glyphs for semantic groups.

Maps to: **Type 4 Attachment subtable** in kerx with anchor points

### Syntax: Individual Base

```ruby
@base baseGlyph
    SEMANTIC_1 <x1, y1>
    SEMANTIC_2 <x2, y2>
    ...
```

### Syntax: Class-Based (Uniform)

All bases in class get same attachment points:

```ruby
@class BASE_CLASS = base1 base2 base3
@base @BASE_CLASS
    SEMANTIC_1 <x, y>
    SEMANTIC_2 <x, y>
```

### Syntax: Class-Based (Per-Glyph Variation)

Different attachment points for each base:

```ruby
@class CONSONANTS = ka ga nga
@base @CONSONANTS
    ka: TOP <100, 150>, BOTTOM <100, 0>
    ga: TOP <110, 150>, BOTTOM <110, 0>
    nga: TOP <120, 150>, BOTTOM <120, 0>
```

### Examples

```ruby
# Thai - individual bases
@base uni0E01
    BOTTOM <133, 0>
    TOP <130, 137>

@base uni0E02
    BOTTOM <113, 0>
    TOP <119, 137>

# Thai - class-based uniform
@class TALL_CONS = uni0E1B uni0E1D uni0E1F
@base @TALL_CONS
    BOTTOM <172, 0>
    TOP <172, 148>

# Arabic - per-glyph variation
@class BASES = uni0621.ar uni0627.ar
@base @BASES
    uni0621.ar: TOP <65, 91>, BOTTOM <52, 7>
    uni0627.ar: TOP <31, 176>, BOTTOM <31, 7>
```

### Generated ATIF

```swift
control point kerning subtable {
    layout is horizontal;
    kerning is horizontal;
    uses anchor points;
    scan glyphs backward;

    // Mark anchors (all use index [0])
    anchor uni0E48[0] := (-23, 137);
    anchor uni0E49[0] := (-23, 137);
    anchor uni0E38[0] := (-23, 0);
    anchor uni0E39[0] := (-23, 0);
    
    // Base anchors (sequential indices per semantic)
    anchor uni0E01[0] := (133, 0);    // BOTTOM attachment
    anchor uni0E01[1] := (130, 137);  // TOP attachment
    
    class bases { uni0E01, uni0E02 };
    class marks_BOTTOM { uni0E38, uni0E39 };
    class marks_TOP { uni0E48, uni0E49 };
    
    state Start {
        bases: sawBase;
    };
    
    state withBase {
        marks_BOTTOM: sawMark_BOTTOM;
        marks_TOP: sawMark_TOP;
        bases: sawBase;
    };
    
    transition sawBase {
        change state to withBase;
        mark glyph;
    };
    
    transition sawMark_BOTTOM {
        change state to withBase;
        kerning action: snapMark_BOTTOM;
    };
    
    transition sawMark_TOP {
        change state to withBase;
        kerning action: snapMark_TOP;
    };
    
    anchor point action snapMark_BOTTOM {
        marked glyph point: 0;  // Base's BOTTOM (index 0)
        current glyph point: 0; // Mark's anchor (always 0)
    };
    
    anchor point action snapMark_TOP {
        marked glyph point: 1;  // Base's TOP (index 1)
        current glyph point: 0; // Mark's anchor (always 0)
    };
};
```

---

## Section 4: Mark-to-Mark

Define marks that can have other marks attached to them (mark stacking).

Maps to: **Type 4 Attachment subtable** in kerx

### Key Concept

A mark glyph can serve **two roles**:
1. **Attaching mark** (defined in `@mark_group`)
2. **Base mark** (defined in `@mark2mark`)

**Example:** Thai vowel marks can have tone marks stacked on them:
- `uni0E38` is in `BOTTOM` group (attaches to bases)
- `uni0E38` also acts as base for `TOP` marks (has attachment point)

### Syntax: Individual Mark

```ruby
@mark2mark markGlyph
    SEMANTIC_1 <x1, y1>
```

### Syntax: Class-Based

```ruby
@class BASE_MARKS = mark1 mark2 mark3
@mark2mark @BASE_MARKS
    SEMANTIC_1 <x, y>
```

### Examples

```ruby
# Thai mark stacking - tone marks stack on vowels
@mark_group BOTTOM
    uni0E38 <-23, 0>
    uni0E39 <-23, 0>
    uni0E3A <-23, 0>

@mark_group TOP
    uni0E48 <-23, 137>
    uni0E49 <-23, 137>

# These bottom marks can have top marks stacked on them
@mark2mark uni0E38
    BOTTOM <-23, -70>

@mark2mark uni0E39
    BOTTOM <-23, -68>

@mark2mark uni0E3A
    BOTTOM <-23, -48>

# Or class-based if they share attachment point
@class STACKABLE = uni0E31 uni0E34 uni0E35
@mark2mark @STACKABLE
    TOP <-23, 182>
```

### Generated ATIF

```swift
control point kerning subtable {
    layout is horizontal;
    kerning is horizontal;
    uses anchor points;
    scan glyphs backward;

    // Attaching mark anchors (use index [0])
    anchor uni0E48[0] := (-23, 137);
    anchor uni0E49[0] := (-23, 137);
    
    // Base mark anchors (index [2] = after all mark groups)
    anchor uni0E38[2] := (-23, -70);
    anchor uni0E39[2] := (-23, -68);
    anchor uni0E3A[2] := (-23, -48);
    
    class bases { uni0E38, uni0E39, uni0E3A };
    class marks_TOP { uni0E48, uni0E49 };
    
    state Start {
        bases: sawBase;
    };
    
    state withBase {
        marks_TOP: sawMark;
        bases: sawBase;
    };
    
    transition sawBase {
        change state to withBase;
        mark glyph;
    };
    
    transition sawMark {
        change state to Start;
        kerning action: snapMark;
    };
    
    anchor point action snapMark {
        marked glyph point: 2;  // Base mark's attachment point
        current glyph point: 0; // Attaching mark's anchor
    };
};
```

---

## Section 5: Mark-to-Ligature

Define attachment points for each component of a ligature.

Maps to: **Type 4 Attachment subtable** with DEL detection

### Syntax

```ruby
@ligature ligatureGlyph
    SEMANTIC_1 <x1, y1> <x2, y2> <x3, y3> ...
    SEMANTIC_2 <x1, y1> <x2, y2> <x3, y3> ...
```

**One anchor per ligature component for each semantic group.**

### Examples

```ruby
# Arabic lam-alef ligatures (2 components)
@ligature uniFEFB.ar
    BOTTOM <149, 7> <85, 7>
    TOP <150, 176> <85, 111>

@ligature uniFEFC.ar
    BOTTOM <149, 7> <85, 7>
    TOP <150, 176> <85, 111>

# Allah ligature (4 components!)
@ligature uniFDF2.ar
    BOTTOM <326, 7> <264, 7> <172, 7> <49, 7>
    TOP <326, 182> <261, 182> <170, 182> <52, 113>
```

### Generated ATIF (Simplified)

```swift
control point kerning subtable {
    layout is horizontal;
    kerning is horizontal;
    uses anchor points;
    scan glyphs backward;
    
    // Mark anchors (all use index [0])
    anchor uni064D[0] := (29, 7);
    anchor uni0615[0] := (35, 107);
    
    // Ligature component anchors
    // Component 1: BOTTOM=[0], TOP=[1]
    // Component 2: BOTTOM=[2], TOP=[3]
    anchor uniFEFB.ar[0] := (149, 7);    // Comp1 BOTTOM
    anchor uniFEFB.ar[1] := (150, 176);  // Comp1 TOP
    anchor uniFEFB.ar[2] := (85, 7);     // Comp2 BOTTOM
    anchor uniFEFB.ar[3] := (85, 111);   // Comp2 TOP
    
    class ligs { uniFEFB.ar };
    class marks_BOTTOM { uni064D };
    class marks_TOP { uni0615 };
    
    state Start {
        ligs: sawLig;
    };
    
    state SLig {
        DEL: sawDel0;        // Detect component boundary
        marks_BOTTOM: sawMark_BOTTOM_comp0;
        marks_TOP: sawMark_TOP_comp0;
        ligs: sawLig;
    };
    
    state SLig1 {
        marks_BOTTOM: sawMark_BOTTOM_comp1;
        marks_TOP: sawMark_TOP_comp1;
        ligs: sawLig;
    };
    
    // ... transitions and actions ...
};
```

---

## Anchor Point Auto-Indexing (AAT Model)

**Critical:** You never specify anchor point indices. The tool auto-assigns them based on the AAT semantic model.

### AAT Indexing Rules

**For marks (in `@mark_group`):**
- **ALL marks use index [0]** for their own anchor
- Each mark has different coordinates, but same index
- Example:
```swift
anchor uni0E48[0] := (-23, 137);  // TOP mark
anchor uni0E38[0] := (-23, 0);    // BOTTOM mark
```

**For bases (in `@base`):**
- **Sequential indices per semantic group**
- Ordered alphabetically: BOTTOM < MIDDLE < TOP < ATTACHMENT_*
- Example for 2 groups (BOTTOM, TOP):
```swift
anchor uni0E01[0] := (133, 0);    // BOTTOM attachment
anchor uni0E01[1] := (130, 137);  // TOP attachment
```

**For mark-to-mark:**
- Attaching marks use index [0] (from their mark group)
- Base marks get new index = number of mark groups
- Example with 2 mark groups:
```swift
anchor uni0E48[0] := (-23, 137);  // Attaching mark
anchor uni0E38[2] := (-23, -70);  // Base mark (2 = after groups 0,1)
```

**For ligatures:**
- Component 1: uses semantic indices (0, 1, 2, ...)
- Component 2: uses semantic indices + group_count
- Component 3: uses semantic indices + (2 * group_count)
- Example with 2 groups (BOTTOM, TOP), 2 components:
```swift
anchor lig[0] := (149, 7);    // Comp1 BOTTOM
anchor lig[1] := (150, 176);  // Comp1 TOP
anchor lig[2] := (85, 7);     // Comp2 BOTTOM (2 = 0 + 2*1)
anchor lig[3] := (85, 111);   // Comp2 TOP (3 = 1 + 2*1)
```

### Complete Indexing Example

```ruby
# Semantic groups (auto-ordered: BOTTOM=0, TOP=1)
@mark_group BOTTOM
    uni0E38 <-23, 0>
    uni0E39 <-23, 0>

@mark_group TOP
    uni0E48 <-23, 137>
    uni0E49 <-23, 137>

# Mark-to-base (uses indices 0 and 1)
@base uni0E01
    BOTTOM <133, 0>      # Index 0
    TOP <130, 137>       # Index 1

# Mark-to-mark (gets new index 2)
@mark2mark uni0E38
    BOTTOM <-23, -70>    # Mark=0, Base=2

# Ligature (2 components, 2 groups)
@ligature f_i
    BOTTOM <100, 0> <250, 0>      # Indices 0, 2
    TOP <100, 150> <250, 150>     # Indices 1, 3
```

### Generated Anchor Declarations

```swift
// Marks (all use index [0])
anchor uni0E38[0] := (-23, 0);
anchor uni0E39[0] := (-23, 0);
anchor uni0E48[0] := (-23, 137);
anchor uni0E49[0] := (-23, 137);

// Bases (sequential per semantic: BOTTOM=0, TOP=1)
anchor uni0E01[0] := (133, 0);
anchor uni0E01[1] := (130, 137);

// Mark-to-mark (base index = 2)
anchor uni0E38[2] := (-23, -70);

// Ligature (comp1: 0,1; comp2: 2,3)
anchor f_i[0] := (100, 0);    // Comp1 BOTTOM
anchor f_i[1] := (100, 150);  // Comp1 TOP
anchor f_i[2] := (250, 0);    // Comp2 BOTTOM
anchor f_i[3] := (250, 150);  // Comp2 TOP
```

---

## Complete Examples

### Example 1: Thai Mark Positioning (Updated)

**File: `thai_marks.aar`**

```ruby
# ============================================================================
# Thai Mark Positioning
# ============================================================================

# ----------------------------------------------------------------------------
# MARK GROUPS (each mark has its own anchor)
# ----------------------------------------------------------------------------

@mark_group BOTTOM
    uni0331 <-9, 0>
    uni0331.alt <-15, 0>
    uni0E38 <-23, 0>
    uni0E38.small <-21, -42>
    uni0E39 <-23, 0>
    uni0E39.small <-21, -42>
    uni0E3A <-23, 0>
    uni0E3A.small <-21, -42>

@mark_group TOP
    tildecomb <-20, 137>
    uni0E31 <-23, 137>
    uni0E31.narrow <-58, 137>
    uni0E34 <-23, 137>
    uni0E34.narrow <-59, 137>
    uni0E48 <-23, 137>
    uni0E48.narrow <-59, 137>
    uni0E48.small <-23, 197>
    uni0E49 <-23, 137>
    uni0E49.narrow <-59, 137>
    uni0E49.small <-23, 197>

# ----------------------------------------------------------------------------
# DISTANCE POSITIONING
# ----------------------------------------------------------------------------

@class TARGETS_uni0331 = uni0E38 uni0E39
@distance uni0331 @TARGETS_uni0331 -38 vertical

# ----------------------------------------------------------------------------
# MARK-TO-BASE
# ----------------------------------------------------------------------------

@base uni0E01
    BOTTOM <133, 0>
    TOP <130, 137>

@base uni0E02
    BOTTOM <113, 0>
    TOP <119, 137>

# ... more bases ...

# ----------------------------------------------------------------------------
# MARK-TO-MARK (bottom marks can have top marks stacked)
# ----------------------------------------------------------------------------

@mark2mark uni0E38
    BOTTOM <-23, -70>

@mark2mark uni0E39
    BOTTOM <-23, -68>

@mark2mark uni0E3A
    BOTTOM <-23, -48>

# Top marks can stack on each other
@mark2mark uni0E31
    TOP <-16, 183>

@mark2mark uni0E48
    TOP <-23, 216>
```

---

### Example 2: Arabic Ligatures (Updated)

**File: `simple_ligature_attachment.aar`**

```ruby
# ============================================================================
# Arabic Mark Positioning with Ligatures
# ============================================================================

# ----------------------------------------------------------------------------
# MARK GROUPS
# ----------------------------------------------------------------------------

@mark_group BOTTOM
    uni064D.ar <29, 7>
    uni0650.ar <29, 7>
    uni0655.ar <21, 7>
    uni0656.ar <6, 7>

@mark_group TOP
    uni0615.ar <35, 107>
    uni064B.ar <29, 112>
    uni064C.ar <41, 112>
    uni064E.ar <29, 112>
    uni064F.ar <29, 112>
    uni0651.ar <36, 112>
    uni0652.ar <23, 112>

# ----------------------------------------------------------------------------
# MARK-TO-LIGATURE
# ----------------------------------------------------------------------------

@ligature uniFEFB.ar
    BOTTOM <149, 7> <85, 7>
    TOP <150, 176> <85, 111>

@ligature uniFEFC.ar
    BOTTOM <149, 7> <85, 7>
    TOP <150, 176> <85, 111>

@ligature uniFDF2.ar
    BOTTOM <326, 7> <264, 7> <172, 7> <49, 7>
    TOP <326, 182> <261, 182> <170, 182> <52, 113>
```

---

## Comparison with OpenType

### Similarities

✅ **Mark positioning concept** - Same goal as OT GPOS  
✅ **Base anchors** - Same concept as OT `pos base`  
✅ **Mark-to-mark** - Same concept as OT `pos mark`  
✅ **Ligature components** - Same concept as OT component indices  

### Key Differences

🔄 **Per-mark anchors** - Each mark has its own coordinates vs. shared class anchor  
🔄 **Semantic grouping** - Groups by attachment point (BOTTOM/TOP) vs. behavior  
🔄 **Mark deduplication** - Marks appear once even if in multiple OT classes  
🔄 **Auto-indexing** - AAT uses explicit indices, we generate them automatically  
🔄 **File format** - Simpler, more declarative than AFDKO  

### Example Comparison

**OpenType (AFDKO):**
```
markClass uni0E48 <anchor 0 148> @TOP;
markClass uni0E49 <anchor 0 148> @TOP;
pos base uni0E01 <anchor 169 148> mark @TOP;
```

**Our format (.aar):**
```ruby
@mark_group TOP
    uni0E48 <-23, 137>
    uni0E49 <-23, 137>

@base uni0E01
    TOP <130, 137>
```

**Advantages:**
- Each mark can have different coordinates
- More readable semantic names
- Auto-indexes anchors to AAT model
- Mark deduplication built-in

---

## Summary

### Key Points

✅ **Semantic grouping:** Marks grouped by WHERE they attach (BOTTOM/TOP), not behavior  
✅ **Per-mark anchors:** Each mark has its own coordinates  
✅ **AAT-native model:** All marks use [0], bases use sequential indices  
✅ **Auto-indexing:** Never specify anchor indices manually  
✅ **Mark deduplication:** Marks appear once regardless of OT class usage  

### Quick Reference

```ruby
# Mark groups (each mark has own anchor)
@mark_group SEMANTIC_NAME
    mark1 <x1, y1>
    mark2 <x2, y2>

# Distance
@distance context target value [direction]

# Mark-to-base (references semantic names)
@base glyph
    SEMANTIC_1 <x, y>
    SEMANTIC_2 <x, y>

# Mark-to-mark (references semantic names)
@mark2mark glyph
    SEMANTIC <x, y>

# Ligature (references semantic names)
@ligature glyph
    SEMANTIC <x1, y1> <x2, y2> ...
```

---

**Version:** 2.0  
**Last Updated:** 2025-01-15  
**Author:** Muthu Nedumaran  
**Changes from v1.0:** Updated to reflect semantic grouping model with per-mark anchors