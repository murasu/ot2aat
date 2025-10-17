#!/usr/bin/env python3

#  gposaar2kerxatif.py
#  ot2aat
#
#  Created by Muthu Nedumaran on 16/10/2025.
#  Updated with proper AAT anchor indexing rules
#

"""
Convert AAR (intermediate format) to ATIF (Apple Advanced Typography Instruction Format)
Handles mark positioning with proper anchor point indexing for AAT.

Key AAT Requirements:
- Anchor indices must be sequential (0, 1, 2...) with no gaps
- Each glyph can only define each anchor index ONCE across all tables
- All kerning is horizontal (AAT doesn't support vertical layout in the same way as GPOS)
- Mark-to-base: marks use [0], bases use sequential indices per mark class
- Mark-to-mark: attaching marks use [1], base marks use [1] for stacking points
"""

import re
from collections import defaultdict, OrderedDict
from typing import Dict, List, Tuple, Set

class AARToATIFConverter:
    def __init__(self):
        self.mark_groups = OrderedDict()  # group_name -> [(glyph, x, y), ...]
        self.bases = OrderedDict()  # glyph -> {group_name: (x, y), ...}
        self.mark2mark = OrderedDict()  # glyph -> {group_name: (x, y), ...}
        self.distance_rules = []  # [(glyph1, glyph2, distance), ...]
        
    def parse_aar(self, content: str):
        """Parse AAR file content"""
        lines = content.strip().split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i].strip()
            
            # Skip comments and empty lines
            if not line or line.startswith('#'):
                i += 1
                continue
            
            # Parse mark group
            if line.startswith('@mark_group'):
                group_name = line.split()[1]
                i += 1
                marks = []
                while i < len(lines):
                    line = lines[i].strip()
                    if not line or line.startswith('#'):
                        i += 1
                        continue
                    if line.startswith('@'):
                        break
                    # Parse: glyph <x, y>
                    match = re.match(r'(\S+)\s+<(-?\d+),\s*(-?\d+)>', line)
                    if match:
                        glyph, x, y = match.groups()
                        marks.append((glyph, int(x), int(y)))
                    i += 1
                self.mark_groups[group_name] = marks
                continue
            
            # Parse distance adjustment (always horizontal in AAT)
            if line.startswith('@distance'):
                # @distance glyph1 glyph2/CLASS distance [direction]
                parts = line.split()
                glyph1 = parts[1]
                target = parts[2]  # Could be glyph or @CLASS
                distance = int(parts[3])
                # Ignore direction - AAT kerning is always horizontal
                self.distance_rules.append((glyph1, target, distance))
                i += 1
                continue
            
            # Parse class definition (stored for later expansion)
            if line.startswith('@class'):
                # Classes are handled inline during expansion
                i += 1
                continue
            
            # Parse base
            if line.startswith('@base'):
                glyph = line.split()[1]
                i += 1
                anchors = {}
                while i < len(lines):
                    line = lines[i].strip()
                    if not line or line.startswith('#'):
                        i += 1
                        continue
                    if line.startswith('@'):
                        break
                    # Parse: GROUP_NAME <x, y>
                    match = re.match(r'(\S+)\s+<(-?\d+),\s*(-?\d+)>', line)
                    if match:
                        group, x, y = match.groups()
                        anchors[group] = (int(x), int(y))
                    i += 1
                self.bases[glyph] = anchors
                continue
            
            # Parse mark2mark
            if line.startswith('@mark2mark'):
                glyph = line.split()[1]
                i += 1
                anchors = {}
                while i < len(lines):
                    line = lines[i].strip()
                    if not line or line.startswith('#'):
                        i += 1
                        continue
                    if line.startswith('@'):
                        break
                    # Parse: GROUP_NAME <x, y>
                    match = re.match(r'(\S+)\s+<(-?\d+),\s*(-?\d+)>', line)
                    if match:
                        group, x, y = match.groups()
                        anchors[group] = (int(x), int(y))
                    i += 1
                self.mark2mark[glyph] = anchors
                continue
            
            i += 1
    
    def expand_class(self, content: str, class_name: str) -> List[str]:
        """Expand a class reference to list of glyphs"""
        # Strip @ prefix if present
        class_name = class_name.lstrip('@')
    
        # Find class definition
        pattern = rf'@class\s+{re.escape(class_name)}\s+=\s+(.+)'
        match = re.search(pattern, content)
        if match:
            return match.group(1).strip().split()
        return []
    
    def get_marks_in_table2(self) -> Set[str]:
        """Get marks that appear in mark-to-mark table (will use anchor [1])"""
        marks_in_table2 = set()
        
        # Marks that are bases in mark2mark
        for mark_glyph in self.mark2mark.keys():
            marks_in_table2.add(mark_glyph)
        
        # Also need to know which marks can ATTACH in mark2mark
        # These are marks whose groups appear in mark2mark bases
        attaching_groups = set()
        for anchors in self.mark2mark.values():
            attaching_groups.update(anchors.keys())
        
        # Find all marks in those groups
        for group_name in attaching_groups:
            if group_name in self.mark_groups:
                for glyph, _, _ in self.mark_groups[group_name]:
                    marks_in_table2.add(glyph)
        
        return marks_in_table2
    
    def generate_atif(self, original_content: str) -> str:
        """Generate ATIF output"""
        output = []
        
        # Header
        output.append("// " + "-" * 79)
        output.append("//")
        output.append("//  Generated ATIF for mark positioning")
        output.append("//  Converted from AAR format")
        output.append("//")
        output.append("//  AAT Anchor Indexing Rules:")
        output.append("//  - Indices must be sequential (0, 1, 2...) with NO gaps")
        output.append("//  - Each glyph can only define each index ONCE across ALL tables")
        output.append("//  - Table 1 (mark-to-base): marks use [0], bases use [0, 1, 2...]")
        output.append("//  - Table 2 (mark-to-mark): attaching marks use [1], base marks use [1]")
        output.append("//")
        output.append("// " + "-" * 79)
        output.append("")
        
        # Determine which marks appear in table 2
        marks_in_table2 = self.get_marks_in_table2()
        
        # Table 0: Distance kerning (if any)
        if self.distance_rules:
            output.append("// " + "-" * 79)
            output.append("// Table 0: Horizontal kerning (distance adjustments)")
            output.append("// " + "-" * 79)
            output.append("")
            output.append("kerning list {")
            output.append("    layout is horizontal;")
            output.append("    kerning is horizontal;")
            output.append("")
            
            for glyph1, target, distance in self.distance_rules:
                if target.startswith('@'):
                    # It's a class reference
                    targets = self.expand_class(original_content, target)
                else:
                    # It's a single glyph
                    targets = [target]
                
                for t in targets:
                    output.append(f"    {glyph1} + {t} => {distance};")
            
            output.append("};")
            output.append("")
        
        # Table 1: Mark-to-base
        output.append("// " + "-" * 79)
        output.append("// Table 1: Mark-to-base positioning")
        output.append("// " + "-" * 79)
        output.append("")
        output.append("control point kerning subtable {")
        output.append("    layout is horizontal;")
        output.append("    kerning is horizontal;")
        output.append("")
        
        # Define mark anchors (all use index [0] for attaching to bases)
        output.append("    // Mark anchors (all use index [0] for attaching to bases)")
        all_marks = set()
        for group_name, marks in self.mark_groups.items():
            for glyph, x, y in marks:
                output.append(f"    anchor {glyph}[0] := ({x}, {y});")
                all_marks.add(glyph)
        output.append("")
        
        # Define base anchors (sequential indices per group)
        output.append("    // Base anchors (sequential indices per mark class)")
        group_names = list(self.mark_groups.keys())
        for base_glyph, anchors in self.bases.items():
            for idx, group_name in enumerate(group_names):
                if group_name in anchors:
                    x, y = anchors[group_name]
                    output.append(f"    anchor {base_glyph}[{idx}] := ({x}, {y});")
        output.append("")
        
        # Define classes
        base_glyphs = list(self.bases.keys())
        output.append(f"    class bases {{ {', '.join(base_glyphs)} }};")
        output.append("")
        
        for group_name, marks in self.mark_groups.items():
            mark_list = [m[0] for m in marks]
            class_name = f"marks_{group_name}"
            output.append(f"    class {class_name} {{ {', '.join(mark_list)} }};")
        output.append("")
        
        # State machine
        output.append("    state Start {")
        output.append("        bases: sawBase;")
        output.append("    };")
        output.append("")
        output.append("    state withBase {")
        for group_name in self.mark_groups.keys():
            class_name = f"marks_{group_name}"
            transition = f"sawMark_{group_name}"
            output.append(f"        {class_name}: {transition};")
        output.append("        bases: sawBase;")
        output.append("    };")
        output.append("")
        output.append("    transition sawBase {")
        output.append("        change state to withBase;")
        output.append("        mark glyph;")
        output.append("    };")
        output.append("")
        
        for idx, group_name in enumerate(group_names):
            transition = f"sawMark_{group_name}"
            action = f"snapMark_{group_name}"
            output.append(f"    transition {transition} {{")
            output.append("        change state to withBase;")
            output.append(f"        kerning action: {action};")
            output.append("    };")
            output.append("")
        
        for idx, group_name in enumerate(group_names):
            action = f"snapMark_{group_name}"
            output.append(f"    anchor point action {action} {{")
            output.append(f"        marked glyph point: {idx};")
            output.append("        current glyph point: 0;")
            output.append("    };")
            if idx < len(group_names) - 1:
                output.append("")
        
        output.append("};")
        output.append("")
        
        # Table 2: Mark-to-mark
        if self.mark2mark:
            output.append("// " + "-" * 79)
            output.append("// Table 2: Mark-to-mark positioning")
            output.append("// " + "-" * 79)
            output.append("")
            output.append("control point kerning subtable {")
            output.append("    layout is horizontal;")
            output.append("    kerning is horizontal;")
            output.append("")
            
            # Find which marks ONLY attach (don't serve as bases)
            marks_only_attaching = set()
            marks_serving_as_bases = set(self.mark2mark.keys())
            
            # Get all marks that can attach
            attaching_groups = set()
            for anchors in self.mark2mark.values():
                attaching_groups.update(anchors.keys())
            
            for group_name in attaching_groups:
                if group_name in self.mark_groups:
                    for glyph, _, _ in self.mark_groups[group_name]:
                        if glyph not in marks_serving_as_bases:
                            marks_only_attaching.add(glyph)
            
            # Define attaching mark anchors (use index [1])
            # ONLY for marks that don't also serve as bases
            if marks_only_attaching:
                output.append("    // Attaching mark anchors (use index [1] for attaching to other marks)")
                output.append("    // ONLY marks that don't also serve as bases")
                for glyph in sorted(marks_only_attaching):
                    # Find this mark's coordinates from mark_groups
                    for group_name, marks in self.mark_groups.items():
                        for mark_glyph, x, y in marks:
                            if mark_glyph == glyph:
                                output.append(f"    anchor {glyph}[1] := ({x}, {y});")
                                break
                output.append("")
            
            # Define base mark anchors (use index [1] for stacking points)
            output.append("    // Base mark anchors (use index [1] for providing stacking points)")
            for mark_glyph, anchors in self.mark2mark.items():
                for group_name, (x, y) in anchors.items():
                    # All use index [1] - same as attaching marks
                    output.append(f"    anchor {mark_glyph}[1] := ({x}, {y});")
            output.append("")
            
            # Classes
            base_marks = list(self.mark2mark.keys())
            output.append(f"    class bases {{ {', '.join(base_marks)} }};")
            output.append("")
            
            # Marks that can attach (only those that don't serve as bases)
            if marks_only_attaching:
                output.append(f"    class marks {{ {', '.join(sorted(marks_only_attaching))} }};")
                output.append("")
            
            # State machine
            output.append("    state Start {")
            output.append("        bases: sawBase;")
            output.append("    };")
            output.append("")
            output.append("    state withBase {")
            if marks_only_attaching:
                output.append("        marks: sawMark;")
            output.append("        bases: sawBase;")
            output.append("    };")
            output.append("")
            output.append("    transition sawBase {")
            output.append("        change state to withBase;")
            output.append("        mark glyph;")
            output.append("    };")
            output.append("")
            
            if marks_only_attaching:
                output.append("    transition sawMark {")
                output.append("        change state to Start;")
                output.append("        kerning action: snapMark;")
                output.append("    };")
                output.append("")
            
            output.append("    anchor point action snapMark {")
            output.append("        marked glyph point: 1;")
            output.append("        current glyph point: 1;")
            output.append("    };")
            output.append("};")
        
        return '\n'.join(output)


def main():
    import sys
    
    if len(sys.argv) != 3:
        print("Usage: python gposaar2kerxatif.py input.aar output.atif")
        print("\nConverts AAR (intermediate format) to ATIF (AAT kerx format)")
        print("Handles mark positioning with proper AAT anchor indexing")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        # Read AAR
        with open(input_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Convert
        converter = AARToATIFConverter()
        converter.parse_aar(content)
        atif_content = converter.generate_atif(content)
        
        # Write ATIF
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(atif_content)
        
        print(f"✓ Converted {input_file} -> {output_file}")
        print("\nNext steps:")
        print("1. Review the generated ATIF file")
        print("2. Compile with: ftxenhancer -t kerx=output.atif your_font.ttf")
        print("3. Test the font on macOS/iOS")
        
    except FileNotFoundError:
        print(f"Error: File not found: {input_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error during conversion: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
