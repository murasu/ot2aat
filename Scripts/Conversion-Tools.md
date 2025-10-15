# OpenType to ot2aat Conversion Tools

## Overview

The `gposfea2kerxaar.py` script converts OpenType **GPOS (positioning)** features from AFDKO `.fea` files to the ot2aat `.aar` format, enabling automatic migration of existing mark positioning and kerning rules.

**Scope**: GPOS features only (kerning, mark attachment, distance adjustments). GSUB (substitution) features are out of scope.

**REDESIGNED FOR AAT'S SEMANTIC ATTACHMENT MODEL**: This converter now properly handles the fundamental difference between OpenType and AAT anchor point systems.

**NEW IN VERSION 2.0:**
- ✅ Global `@class` definitions support
- ✅ Pair positioning (`pos glyph1 glyph2 <value>`) now converts to distance rules
- ✅ Class-based kerning fully supported and expanded
- ✅ Better error messages and warnings
- ✅ Preserves `lookupflag UseMarkFilteringSet`

---

## Key Concept: OpenType vs AAT Anchor Models

### OpenType Model (Class-Based)
- **Mark classes** group marks by behavior
- Each mark in a class can have **different anchor coordinates**
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
  - `[0]` = TOP attachment
  - `[1]` = MIDDLE attachment  
  - `[2]` = BOTTOM attachment
- Example from working ATIF:
  ```
  anchor uni0E31[0] := (-336, 1078);  # Top mark uses [0]
  anchor uni0E34[0] := (-20, 1077);   # Also top mark, also [0], different coords
  anchor uni0E38[0] := (-240, -120);  # Bottom mark, STILL [0]!
  
  anchor uni0E01[0] := (900, 1082);   # Base: [0] = top attachment
  anchor uni0E01[1] := (907, -90);    # Base: [1] = bottom attachment
  ```

### How the Converter Handles This

The converter **automatically detects semantic attachment points** based on Y-coordinates:
- **Y ≥ 500**: TOP attachment point
- **-200 < Y < 500**: MIDDLE attachment point
- **Y ≤ -200**: BOTTOM attachment point

---

## gposfea2kerxaar.py

### Purpose
Converts OpenType **GPOS (positioning)** mark positioning lookups to ot2aat format.

**Scope**: This converter handles GPOS features only (kerning, mark positioning, cursive attachment). For GSUB (substitution) features, a different converter would be needed.

### Supported Conversions

| OpenType Feature | ot2aat Format | Notes |
|-----------------|---------------|-------|
| `@CLASS = [glyphs]` | `@class CLASS = glyphs` | ✅ Top-level class definitions |
| `pos glyph1 glyph2 <value>` | `@distance glyph1 glyph2 value` | ✅ Pair positioning (kerning) |
| `pos @CLASS1 @CLASS2 <value>` | `@distance` with class expansion | ✅ Class-based pair positioning |
| `markClass [glyph] <anchor X Y> @CLASS` | `@mark_group SEMANTIC` | ✅ Auto-detects TOP/MIDDLE/BOTTOM by Y-coord |
| `pos base glyph <anchor> mark @CLASS` | `@base glyph` with semantic groups | ✅ Maps to TOP/MIDDLE/BOTTOM |
| `pos mark glyph <anchor> mark @CLASS` | `@mark2mark glyph` | ✅ Semantic grouping |
| `pos ligature ... ligComponent` | `@ligature glyph` | ✅ Component-based (uses DEL divider) |
| `pos context target' lookup` | `@distance` | ✅ **Full support** - Contextual positioning fully working |
| Value records `<xPlacement yPlacement ...>` | `@distance` | ✅ Full support |
| `lookupflag UseMarkFilteringSet` | Preserved in output | ✅ Maintained for AAT state machine |

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

**NEW**: The converter now supports top-level `@class` definitions.

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

### Semantic Attachment Point Detection

**The Problem**: OpenType allows marks in the same class to have different Y-coordinates. AAT requires understanding which marks attach to which base points.

**The Solution**: Automatic classification by Y-coordinate:

**Input (OpenType):**
```fea
markClass uni0E4D <anchor -427 1081> @MARKS;   # High Y
markClass uni0E31 <anchor -336 1078> @MARKS;   # High Y
markClass uni0E38 <anchor -240 -120> @MARKS;   # Low Y (negative)
```

**Output (ot2aat):**
```
@mark_group TOP
	uni0E4D <-427, 1081>
	uni0E31 <-336, 1078>

@mark_group BOTTOM
	uni0E38 <-240, -120>
```

**Key Points:**
- Each mark retains its **individual coordinates**
- Marks are **grouped by semantic meaning**, not OpenType class
- Y-coordinate thresholds:
  - TOP: Y ≥ 500
  - MIDDLE: -200 < Y < 500
  - BOTTOM: Y ≤ -200

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
	TOP <130, 137>
	BOTTOM <133, 0>
```

All bases are automatically analyzed and assigned semantic attachment points based on the mark groups they reference.

### Mark-to-Ligature with DEL Divider

Ligature components are preserved as-is. The AAT state machine will use the **DEL glyph** to divide between components.

**Input (OpenType):**
```fea
pos ligature uniFEFB.ar 
	<anchor 150 176> mark @TOP
	<anchor 149 7> mark @BOTTOM
	ligComponent 
	<anchor 85 111> mark @TOP
	<anchor 85 7> mark @BOTTOM;
```

**Output (ot2aat):**
```
@ligature uniFEFB.ar
	TOP <150, 176> <85, 111>
	BOTTOM <149, 7> <85, 7>
```

The Swift generators will create state machines with DEL transitions between components.

### Contextual Positioning (Distance Rules)

Distance rules are preserved as-is (already working correctly):

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

**This is fully supported and working!** The contextual positioning with lookup references is one of the core features of the converter.

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

- `ATTACHMENT_POINT`: TOP, MIDDLE, or BOTTOM
- Each mark keeps its individual coordinates
- All marks in a group will use AAT anchor index [0]

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

### Ligatures
```
@ligature glyph
	ATTACHMENT_POINT <x1, y1> <x2, y2> <x3, y3>
	...
```

- Each semantic group has coordinates for each component
- AAT uses DEL glyph to transition between components

### Distance Rules (Unchanged)
```
@distance context target adjustment direction
@class CLASSNAME = glyph1 glyph2 ...
```

**Updated**: Now includes pair positioning conversions:
- OpenType: `pos glyph1 glyph2 <value>` → `@distance glyph1 glyph2 value horizontal`
- Class-based pairs are expanded to individual glyph pairs
- Contextual distance rules preserved as before

---

## Examples

### Example 1: Thai Marks with Semantic Detection

**Input:** `thai_marks.fea`
```fea
lookup POS_0 {
	markClass uni0E48 <anchor -23 137> @TOP;
	markClass uni0E4D <anchor -23 137> @TOP;
	markClass uni0E38 <anchor -23 0> @BOTTOM;
	markClass uni0E39 <anchor -23 0> @BOTTOM;
	
	pos base uni0E01 
		<anchor 133 0> mark @BOTTOM 
		<anchor 130 137> mark @TOP;
} POS_0;
```

**Command:**
```bash
python3 gposfea2kerxaar.py thai_marks.fea thai_marks.aar
```

**Output:** `thai_marks.aar`
```
@mark_group TOP
	uni0E48 <-23, 137>
	uni0E4D <-23, 137>

@mark_group BOTTOM
	uni0E38 <-23, 0>
	uni0E39 <-23, 0>

@base uni0E01
	TOP <130, 137>
	BOTTOM <133, 0>
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

**IMPORTANT**: Contextual positioning with lookup references is fully supported!

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

This is one of the most important features - contextual kerning adjustments based on surrounding glyphs.

### Example 4: Pair Positioning with Classes

**NEW FEATURE**: Class-based kerning

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
@distance A c -10 horizontal
...
@distance G g -10 horizontal
```

### Example 5: Arabic Ligatures

**Input:**
```fea
markClass uni0654 <anchor 21 60> @ABOVE;
markClass uni064D <anchor 29 7> @BELOW;

pos ligature uniFEFB.ar 
	<anchor 149 7> mark @BELOW 
	<anchor 150 176> mark @ABOVE
	ligComponent 
	<anchor 85 7> mark @BELOW 
	<anchor 85 111> mark @ABOVE;
```

**Output:**
```
@mark_group TOP
	uni0654 <21, 60>

@mark_group BOTTOM
	uni064D <29, 7>

@ligature uniFEFB.ar
	TOP <150, 176> <85, 111>
	BOTTOM <149, 7> <85, 7>
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

### Y-Coordinate Thresholds

The semantic detection uses fixed thresholds. If your font has unusual metrics:
- TOP marks below Y=500
- BOTTOM marks above Y=-200

You may need to manually adjust the thresholds in the Python script (see `AttachmentPoint.classify()` method).

### Features Not Yet Supported

These are GPOS features that could theoretically be added to the converter:

- ❌ **Cursive attachment** (`pos cursive`) - AAT uses mark-to-base model, not entry/exit chains. Requires manual conversion to anchor-based positioning.
- 🟡 **Single positioning with advance** (`pos glyph <xPl yPl xAdv yAdv>`) - Currently only placement values (xPl, yPl) are converted. xAdvance/yAdvance support planned for future.
- 🟡 **Most lookup flags** - `UseMarkFilteringSet` is preserved, but others like `IgnoreMarks`, `RightToLeft` not yet supported. Planned for future.

**Note**: This converter handles **GPOS (positioning) features only**. GSUB (substitution) features like `sub a by b` are out of scope and require a different converter.

### Features Now Supported (Previously Listed as Unsupported)

- ✅ **Pair positioning** (`pos glyph1 glyph2`) - Fully supported via `@distance` rules
- ✅ **Contextual positioning** (`pos context target' lookup ADJUST`) - **This is fully working!** Converts to `@distance` rules
- ✅ **Global @class definitions** - Supported at top level
- ✅ **Class-based pair positioning** - Classes are expanded to individual pairs
- ✅ **UseMarkFilteringSet flag** - Preserved in mark positioning conversion

---

## Troubleshooting

### Incorrect Semantic Grouping

**Symptom:** Marks grouped into wrong attachment point (TOP/MIDDLE/BOTTOM)

**Cause:** Y-coordinates don't match the thresholds

**Solution:** Check the summary output:
```bash
python3 gposfea2kerxaar.py input.fea 2>&1 | grep "marks:"
```

Shows:
```
TOP marks: 14
BOTTOM marks: 3
```

If grouping is wrong, adjust thresholds in the script or manually edit the `.aar` file.

### Mixed Attachment Points in OpenType Class

**Symptom:** Warning message about mixed attachment points

**Cause:** Single OpenType mark class contains marks with both high and low Y-coordinates

**Solution:** This is expected when converting from OpenType. The converter uses the first mark's attachment point and warns you. Check the output to ensure it's correct.

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

### Pair Positioning Not Converting

**Symptom:** No marks in any semantic group

**Cause:** Marks not inside `lookup` blocks, or no mark positioning in file

**Solution:** Verify your OpenType file has `pos base` or `pos mark` statements inside lookups.

---

## Migration from Old Converter

If you have existing `.aar` files from the old converter, you'll need to regenerate them:

1. **Old format** used split mark classes:
   ```
   @markclass MARK_0 <-9, 0>
	   uni0331
   @markclass MARK_1 <-15, 0>
	   uni0331.alt
   ```

2. **New format** uses semantic groups:
   ```
   @mark_group TOP
	   uni0331 <-9, 0>
	   uni0331.alt <-15, 0>
   ```

**New features in this version:**
- ✅ Global `@class` definitions supported
- ✅ Pair positioning (`pos glyph1 glyph2`) now converts to `@distance`
- ✅ Class-based kerning fully supported
- ✅ Better error messages for undefined classes

**Action required:** Re-run the converter on your original `.fea` files to take advantage of new features.

---

## See Also

- [SPECIFICATION.md](SPECIFICATION.md) - Full ot2aat format specification
- [README.md](README.md) - Main project documentation
- [OpenType Feature File Syntax](https://adobe-type-tools.github.io/afdko/OpenTypeFeatureFileSpecification.html)