# OpenType to ot2aat Conversion Tools

## Overview

The `gposfea2kerxaar.py` script converts OpenType **GPOS (positioning)** features from AFDKO `.fea` files to the ot2aat `.aar` format, enabling automatic migration of existing mark positioning and kerning rules.

**Scope**: GPOS features only (kerning, mark attachment, distance adjustments). GSUB (substitution) features are out of scope.

**REDESIGNED FOR AAT'S SEMANTIC ATTACHMENT MODEL**: This converter properly handles the fundamental difference between OpenType and AAT anchor point systems through intelligent mark deduplication and relative positioning analysis.

**NEW IN VERSION 2.0:**
- ✅ Global `@class` definitions support
- ✅ Pair positioning (`pos glyph1 glyph2 <value>`) converts to distance rules
- ✅ Class-based kerning fully supported and expanded
- ✅ Mark deduplication across multiple OpenType classes
- ✅ Automatic semantic grouping by relative position
- ✅ Bracket notation support for OTM-generated files
- ✅ Mark-to-ligature tested and working
- ✅ Better error messages and warnings

---

## Key Concept: OpenType vs AAT Anchor Models

### OpenType Model (Class-Based)
- **Mark classes** group marks by behavior
- Each mark in a class can have **different anchor coordinates**
- Same marks can appear in multiple classes (e.g., mark-to-base and mark-to-mark)
- Bases reference mark classes
- Example:
```
  markClass uni0E31 <anchor -336 1078> @TOP_MARKS;
  markClass uni0E34 <anchor -20 1077> @TOP_MARKS;  # Different coords, same class
  pos base uni0E01 <anchor 900 1082> mark @TOP_MARKS;
```

### AAT Model (Semantic Attachment Points)
- **ALL marks use index [0]** for their own coordinates
- Marks are grouped by **semantic attachment point** (TOP/MIDDLE/BOTTOM)
- **Bases have multiple indices** for different attachment points:
  - `[0]` = First semantic group (e.g., BOTTOM)
  - `[1]` = Second semantic group (e.g., TOP)
  - `[2]` = Third semantic group (e.g., MIDDLE)
- Example from working ATIF:
```
  anchor uni0E31[0] := (-336, 1078);  # Top mark uses [0]
  anchor uni0E34[0] := (-20, 1077);   # Also top mark, also [0], different coords
  anchor uni0E38[0] := (-240, -120);  # Bottom mark, STILL [0]!
  
  anchor uni0E01[0] := (907, -90);    # Base: [0] = bottom attachment
  anchor uni0E01[1] := (900, 1082);   # Base: [1] = top attachment
```

### How the Converter Handles This

The converter uses **intelligent mark deduplication and relative positioning**:

1. **Parse all OpenType mark classes** from the `.fea` file
2. **Deduplicate marks by identity** - If `uni0E38 <-23, 0>` appears in multiple OT classes (e.g., `@POS_0_0_MARK_0` for mark-to-base and `@POS_7_0_MARK_0` for mark-to-mark), it's recognized as the same mark
3. **Group OT classes that share marks** - Classes with identical marks are merged into one semantic group
4. **Analyze attachment points** - Uses Y-coordinates from both base anchors and ligature anchors to determine where marks attach
5. **Sort groups by relative position** - Uses median Y-coordinate from attachment points
6. **Assign semantic labels** based on relative position:
   - **2 groups** → **BOTTOM** (lower Y), **TOP** (higher Y)
   - **3 groups** → **BOTTOM**, **MIDDLE**, **TOP**
   - **4+ groups** → **ATTACHMENT_0**, **ATTACHMENT_1**, etc.

**Example:** Font with base attachment points at Y=0 and Y=137:
- Marks attaching at Y=0 → **BOTTOM** group
- Marks attaching at Y=137 → **TOP** group
- Works automatically regardless of coordinate range!

**No manual configuration needed** - the converter adapts to any coordinate system, whether your bases use Y=-50/+1200 or Y=0/137.

---

## gposfea2kerxaar.py

### Purpose
Converts OpenType **GPOS (positioning)** mark positioning lookups to ot2aat format.

**Scope**: This converter handles GPOS features only (kerning, mark positioning, cursive attachment). For GSUB (substitution) features, a different converter would be needed.

### Supported Conversions

| OpenType Feature | ot2aat Format | Status |
|-----------------|---------------|--------|
| `@CLASS = [glyphs]` | `@class CLASS = glyphs` | ✅ Tested |
| `pos glyph1 glyph2 <value>` | `@distance glyph1 glyph2 value` | ✅ Tested |
| `pos @CLASS1 @CLASS2 <value>` | `@distance` with class expansion | ✅ Tested |
| `markClass [glyph] <anchor X Y> @CLASS` | `@mark_group SEMANTIC` | ✅ Tested |
| `pos base glyph <anchor> mark @CLASS` | `@base glyph` with semantic groups | ✅ Tested |
| `pos mark glyph <anchor> mark @CLASS` | `@mark2mark glyph` | ✅ Tested |
| `pos ligature ... ligComponent` | `@ligature glyph` | ✅ Tested |
| `pos context target' lookup` | `@distance` | ✅ Tested |
| Value records `<xPlacement yPlacement ...>` | `@distance` | ✅ Tested |
| Bracket notation `[glyph]` | Handled automatically | ✅ Tested |

### Installation

No installation required. The script uses Python 3 standard library only.
```bash
# Make executable
chmod +x gposfea2kerxaar.py
```

### Usage

**Basic conversion:**
```bash
python3 gposfea2kerxaar.py input.fea output.aar
```

**Output to stdout:**
```bash
python3 gposfea2kerxaar.py input.fea
```

**Full workflow example:**
```bash
# Step 1: Convert OpenType GPOS to aar format
python3 gposfea2kerxaar.py thai_marks.fea thai_marks.aar

# Step 2: Generate ATIF
ot2aat markpos --atif -i thai_marks.aar -f "ThaiMarks" --selector 0 -o thai.atif

# Step 3: Add to font
ftxenhancer --atif thai.atif MyFont.ttf
```

**Note**: This converter processes GPOS features only. If your `.fea` file contains GSUB features (like `sub a by b`), they will be ignored.

---

## Conversion Behavior

### Global Class Definitions

The converter supports top-level `@class` definitions.

**Input (OpenType):**
```fea
@UPPERCASE = [A B C D E F G];
@lowercase = [a b c d e f g];

lookup KERN {
	pos @UPPERCASE @lowercase -10;
} KERN;
```

**Output (ot2aat):**
```
@class UPPERCASE = A B C D E F G
@class lowercase = a b c d e f g

@distance A a -10 horizontal
@distance A b -10 horizontal
...
@distance G g -10 horizontal
```

Classes are expanded to individual glyph pairs for maximum compatibility with AAT.

### Pair Positioning (Kerning)

**OpenType pair positioning is fully supported** and converted to AAT distance kerning.

**Input (OpenType):**
```fea
lookup KERN {
	pos A V -50;
	pos T o -30;
	pos @UPPERCASE @lowercase -10;
} KERN;
```

**Output (ot2aat):**
```
@distance A V -50 horizontal
@distance T o -30 horizontal
# Class-based pairs are expanded:
@distance A a -10 horizontal
@distance A b -10 horizontal
...
```

**Key Points:**
- Simple pairs: `pos glyph1 glyph2 <value>` → `@distance glyph1 glyph2 value`
- Class-based pairs: Fully expanded to individual pairs
- All converted to AAT kerx Type 0 (Distance kerning)

### Mark Deduplication and Semantic Detection

**The Problem**: OpenType files often define the same marks in multiple classes (e.g., once for mark-to-base positioning in one lookup, again for mark-to-mark positioning in another lookup). AAT requires each mark to appear in exactly one semantic group.

**The Solution**: Automatic deduplication and semantic grouping:

**Input (OpenType):**
```fea
lookup POS_0 {
	markClass uni0E48 <anchor -23 137> @POS_0_0_MARK_1;  # Mark-to-base
	markClass uni0E38 <anchor -23 0> @POS_0_0_MARK_0;
	
	pos base uni0E01 
		<anchor 133 0> mark @POS_0_0_MARK_0
		<anchor 130 137> mark @POS_0_0_MARK_1;
} POS_0;

lookup POS_7 {
	markClass uni0E38 <anchor -23 0> @POS_7_0_MARK_0;  # Same mark, different class!
	
	pos mark uni0E38 <anchor -23 -70> mark @POS_7_0_MARK_0;
} POS_7;
```

**Output (ot2aat):**
```
@mark_group BOTTOM
	uni0E38 <-23, 0>    # Appears once despite being in 2 OT classes

@mark_group TOP
	uni0E48 <-23, 137>

@base uni0E01
	BOTTOM <133, 0>     # Lower Y → BOTTOM
	TOP <130, 137>      # Higher Y → TOP

@mark2mark uni0E38
	BOTTOM <-23, -70>   # Correctly labeled
```

**Key Points:**
- Converter recognizes `@POS_0_0_MARK_0` and `@POS_7_0_MARK_0` contain the same marks
- Deduplicates `uni0E38` (appears once despite 2 definitions)
- Labels BOTTOM/TOP based on relative Y position (0 vs 137)
- **No absolute thresholds** - adapts to your font's coordinate system
- Each mark retains its **individual coordinates**

### Base Glyph Conversion

OpenType bases with marks at different heights become bases with multiple semantic attachment points.

**Input (OpenType):**
```fea
markClass uni0E48 <anchor -23 137> @TOP;
markClass uni0E38 <anchor -23 0> @BOTTOM;

pos base uni0E01 
	<anchor 130 137> mark @TOP
	<anchor 133 0> mark @BOTTOM;
```

**Output (ot2aat):**
```
@base uni0E01
	BOTTOM <133, 0>
	TOP <130, 137>
```

All bases are automatically analyzed and assigned semantic attachment points based on relative Y-coordinates.

### Mark-to-Ligature with Component Separation

Ligature components are preserved with semantic grouping. The AAT state machine will use the **DEL glyph** to divide between components.

**Input (OpenType):**
```fea
markClass uni064D.ar <anchor 29 7> @BELOW;
markClass uni0615.ar <anchor 35 107> @ABOVE;

pos ligature uniFEFB.ar 
	<anchor 149 7> mark @BELOW
	<anchor 150 176> mark @ABOVE
	ligComponent 
	<anchor 85 7> mark @BELOW
	<anchor 85 111> mark @ABOVE;
```

**Output (ot2aat):**
```
@mark_group BOTTOM
	uni064D.ar <29, 7>

@mark_group TOP
	uni0615.ar <35, 107>

@ligature uniFEFB.ar
	BOTTOM <149, 7> <85, 7>      # Component 1, Component 2
	TOP <150, 176> <85, 111>     # Component 1, Component 2
```

The Swift generators will create state machines with DEL transitions between components.

### Contextual Positioning (Distance Rules)

Contextual distance adjustments are fully supported:

**Input (OpenType):**
```fea
lookup ADJUST {
	pos uni0E38 <0 -38 0 0>;
	pos uni0E39 <0 -38 0 0>;
} ADJUST;

lookup CONTEXT {
	pos uni0331 [uni0E38 uni0E39]' lookup ADJUST;
} CONTEXT;
```

**Output (ot2aat):**
```
@class TARGETS_uni0331 = uni0E38 uni0E39
@distance uni0331 @TARGETS_uni0331 -38 vertical
```

**This is fully supported and working!** Contextual positioning with lookup references is a core feature.

### Bracket Notation Support

The converter handles both standard notation and bracket notation (used by OTM and some other tools):

**Both formats work:**
```fea
markClass uniFBB3.ar <anchor 14 7> @MARKS;     # Standard (GlyphsApp)
markClass [uniFBB3.ar ] <anchor 14 7> @MARKS;  # Brackets (OTM)
```

**Output is identical:**
```
@mark_group BOTTOM
	uniFBB3.ar <14, 7>
```

This ensures compatibility with `.fea` files from multiple sources.

---

## New .aar Format Specification

### Global Classes
```
@class CLASSNAME = glyph1 glyph2 glyph3 ...
```

- Defined at file scope (before any positioning rules)
- Can be referenced in distance rules with `@CLASSNAME`
- Automatically expanded to individual glyph pairs

### Mark Groups
```
@mark_group ATTACHMENT_POINT
	glyph1 <x, y>
	glyph2 <x, y>
	...
```

- `ATTACHMENT_POINT`: BOTTOM, TOP, MIDDLE, or ATTACHMENT_N
- Each mark keeps its individual coordinates
- All marks in a group will use AAT anchor index [0]
- Each mark appears exactly once (deduplicated)

### Base Glyphs
```
@base glyph
	ATTACHMENT_POINT1 <x, y>
	ATTACHMENT_POINT2 <x, y>
	...
```

- Lists semantic attachment points
- Will be converted to base[0], base[1], base[2] in AAT

### Mark-to-Mark
```
@mark2mark mark_glyph
	ATTACHMENT_POINT <x, y>
	...
```

- Same semantic grouping as bases
- Marks can act as both marks and bases

### Ligatures
```
@ligature glyph
	ATTACHMENT_POINT <x1, y1> <x2, y2> <x3, y3>
	...
```

- Each semantic group has coordinates for each component
- AAT uses DEL glyph to transition between components

### Distance Rules
```
@distance context target adjustment direction
@class CLASSNAME = glyph1 glyph2 ...
```

- Converted from pair positioning and contextual rules
- Class-based pairs expanded to individual glyph pairs

---

## Testing Status

| Feature | Status | Test Files |
|---------|--------|------------|
| Mark-to-base | ✅ Fully Tested | Thai, Arabic examples |
| Mark-to-mark | ✅ Fully Tested | Thai mark stacking |
| Mark-to-ligature | ✅ Fully Tested | Arabic ligatures |
| Distance rules | ✅ Fully Tested | Thai contextual adjustments |
| Pair positioning | ✅ Fully Tested | Basic kerning pairs |
| Class-based kerning | ✅ Fully Tested | Class expansion |
| Mark deduplication | ✅ Fully Tested | Thai marks (2 OT classes → 1 group) |
| Bracket notation | ✅ Fully Tested | OTM-generated files |
| Semantic grouping | ✅ Fully Tested | Relative position detection |

**All core features are tested and working with real-world font data.**

---

## Examples

### Example 1: Mark Deduplication (Thai)

**Input:** `thai_marks.fea`
```fea
lookup POS_0 {
	markClass uni0E48 <anchor -23 137> @POS_0_0_MARK_1;
	markClass uni0E38 <anchor -23 0> @POS_0_0_MARK_0;
	
	pos base uni0E01 
		<anchor 133 0> mark @POS_0_0_MARK_0
		<anchor 130 137> mark @POS_0_0_MARK_1;
} POS_0;

lookup POS_7 {
	# Same marks, different class name!
	markClass uni0E38 <anchor -23 0> @POS_7_0_MARK_0;
	
	pos mark uni0E38 <anchor -23 -70> mark @POS_7_0_MARK_0;
} POS_7;
```

**Command:**
```bash
python3 gposfea2kerxaar.py thai_marks.fea thai_marks.aar
```

**Output:** `thai_marks.aar`
```
@mark_group BOTTOM
	uni0E38 <-23, 0>    # Appears once despite being in 2 OT classes

@mark_group TOP
	uni0E48 <-23, 137>

@base uni0E01
	BOTTOM <133, 0>
	TOP <130, 137>

@mark2mark uni0E38
	BOTTOM <-23, -70>
```

### Example 2: Mark-to-Mark Stacking

**Input:**
```fea
lookup MKMK {
	markClass uni0E48 <anchor -259 1076> @TONE;
	markClass uni0E49 <anchor -448 1080> @TONE;
	
	pos mark uni0E4D <anchor -547 1520> mark @TONE;
	pos mark uni0E31 <anchor -335 1558> mark @TONE;
} MKMK;
```

**Output:**
```
@mark_group TOP
	uni0E48 <-259, 1076>
	uni0E49 <-448, 1080>

@mark2mark uni0E4D
	TOP <-547, 1520>

@mark2mark uni0E31
	TOP <-335, 1558>
```

### Example 3: Contextual Distance (Thai Marks)

**Input:** From `thai_marks.fea`
```fea
lookup POS_2 useExtension {
	pos uni0E38 <0 -38 0 0>;
	pos uni0E39 <0 -38 0 0>;
} POS_2;

lookup POS_1 useExtension {
	pos uni0331 [uni0E38 uni0E39]' lookup POS_2;
} POS_1;
```

**Command:**
```bash
python3 gposfea2kerxaar.py thai_marks.fea thai_marks.aar
```

**Output:**
```
@class TARGETS_uni0331 = uni0E38 uni0E39
@distance uni0331 @TARGETS_uni0331 -38 vertical
```

### Example 4: Pair Positioning with Classes

**Input:**
```fea
@UPPERCASE = [A B C D E F G];
@lowercase = [a b c d e f g];

lookup KERN {
	pos A V -50;
	pos T o -30;
	pos @UPPERCASE @lowercase -10;
} KERN;
```

**Output:**
```
@class UPPERCASE = A B C D E F G
@class lowercase = a b c d e f g

@distance A V -50 horizontal
@distance T o -30 horizontal
@distance A a -10 horizontal
@distance A b -10 horizontal
...
@distance G g -10 horizontal
```

### Example 5: Arabic Ligatures with Brackets (OTM)

**Input:**
```fea
lookup GPOS_LOOKUP_00009 {
	markClass [uni064D.ar ] <anchor 29 7> @MARKS_CLASS_0;
	markClass [uni0615.ar ] <anchor 35 107> @MARKS_CLASS_1;
	
	pos ligature uniFEFB.ar 
		<anchor 149 7> mark @MARKS_CLASS_0
		<anchor 150 176> mark @MARKS_CLASS_1
		ligComponent 
		<anchor 85 7> mark @MARKS_CLASS_0
		<anchor 85 111> mark @MARKS_CLASS_1;
} GPOS_LOOKUP_00009;
```

**Output:**
```
@mark_group BOTTOM
	uni064D.ar <29, 7>

@mark_group TOP
	uni0615.ar <35, 107>

@ligature uniFEFB.ar
	BOTTOM <149, 7> <85, 7>
	TOP <150, 176> <85, 111>
```

---

## Known Limitations

### Must Be Inside Lookups
All positioning rules must be inside `lookup` blocks. Top-level `@class` definitions are allowed, but positioning statements must be in lookups:

✅ **Supported:**
```fea
@UPPERCASE = [A B C];  # Top-level class OK

lookup POS_0 {
	markClass uni0331 <anchor -9 0> @MARK;
	pos base uni0E01 <anchor 133 0> mark @MARK;
	pos A V -50;  # Pair positioning inside lookup
} POS_0;
```

❌ **Not supported:**
```fea
pos A V -50;  # Top-level positioning (outside lookup)
pos base uni0E01 <anchor 133 0> mark @MARK;  # Top-level
```

### Features Not Yet Supported

These are GPOS features that could theoretically be added to the converter:

- ❌ **Cursive attachment** (`pos cursive`) - AAT uses mark-to-base model, not entry/exit chains. Requires manual conversion to anchor-based positioning.
- 🟡 **Single positioning with advance** (`pos glyph <xPl yPl xAdv yAdv>`) - Currently only placement values (xPl, yPl) are converted. xAdvance/yAdvance support planned for future.
- 🟡 **Most lookup flags** - Currently no lookup flags are actively processed. Planned for future.

**Note**: This converter handles **GPOS (positioning) features only**. GSUB (substitution) features like `sub a by b` are out of scope and require a different converter.

---

## Troubleshooting

### Marks Not Being Detected

**Symptom:** Output shows `OpenType mark classes: 0`

**Cause:** Marks not inside `lookup` blocks

**Solution:** Verify your OpenType file has `markClass` and positioning statements inside lookups:
```fea
lookup POS_0 {
	markClass uni0331 <anchor -9 0> @MARK;  # Must be inside lookup
	pos base uni0E01 <anchor 133 0> mark @MARK;
} POS_0;
```

### Incorrect Semantic Grouping

**Symptom:** All marks in single ATTACHMENT_0 group instead of BOTTOM/TOP

**Cause:** No base or ligature attachments to analyze (marks defined but never used)

**Solution:** Ensure your `.fea` file has `pos base` or `pos ligature` statements. The converter needs attachment points to determine semantic grouping.

### Undefined Class References

**Symptom:** Warning message "Undefined class @CLASSNAME"

**Cause:** Class referenced in pair positioning but not defined

**Solution:** Ensure all classes are defined before they're used:
```fea
@UPPERCASE = [A B C D];  # Define first

lookup KERN {
	pos @UPPERCASE @lowercase -10;  # Use later
} KERN;
```

### Duplicate Marks Expected

**Symptom:** Marks appear in multiple groups

**This should not happen!** The converter specifically deduplicates marks. If you see this:

1. Check the console output for the deduplication summary
2. Verify you're using the latest version of the script
3. File a bug report with your `.fea` file

---

## Migration from Old Converter

If you have existing `.aar` files from version 1.0, you'll need to regenerate them:

**Old format (v1.0):**
```
@markclass MARK_0 <-9, 0>
	uni0331
@markclass MARK_1 <-15, 0>
	uni0331.alt
```

**New format (v2.0):**
```
@mark_group BOTTOM
	uni0331 <-9, 0>
	uni0331.alt <-15, 0>
```

**What's new in v2.0:**
- ✅ Mark deduplication - same marks in multiple OT classes merged
- ✅ Semantic grouping - BOTTOM/TOP/MIDDLE labels
- ✅ Relative positioning - works with any coordinate system
- ✅ Bracket notation support
- ✅ Mark-to-ligature tested and working
- ✅ Global `@class` definitions
- ✅ Better error messages

**Action required:** Re-run the converter on your original `.fea` files to take advantage of v2.0 features.

---

## See Also

- [SPECIFICATION.md](SPECIFICATION.md) - Full ot2aat format specification
- [README.md](README.md) - Main project documentation
- [OpenType Feature File Syntax](https://adobe-type-tools.github.io/afdko/OpenTypeFeatureFileSpecification.html)
