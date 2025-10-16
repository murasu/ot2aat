#!/usr/bin/env python3

#  gposaar2kerxatif.py
#  ot2aat
#
#  Created by Muthu Nedumaran on 16/10/2025.
#

"""
Convert AAR (intermediate format) to ATIF (Apple Advanced Typography Instruction Format)
Handles mark positioning with proper anchor point indexing for AAT.
"""

import re
from collections import defaultdict, OrderedDict
from typing import Dict, List, Tuple

class AARToATIFConverter:
    def __init__(self):
        self.mark_groups = OrderedDict()  # group_name -> [(glyph, x, y), ...]
        self.bases = OrderedDict()  # glyph -> {group_name: (x, y), ...}
        self.mark2mark = OrderedDict()  # glyph -> {group_name: (x, y), ...}
        self.distance_rules = []  # [(glyph1, glyph2, distance, direction), ...]
        
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
            
            # Parse distance adjustment
            if line.startswith('@distance'):
                # @distance glyph1 glyph2/CLASS distance direction
                parts = line.split()
                glyph1 = parts[1]
                target = parts[2]  # Could be glyph or @CLASS
                distance = int(parts[3])
                direction = parts[4] if len(parts) > 4 else 'horizontal'
                self.distance_rules.append((glyph1, target, distance, direction))
                i += 1
                continue
            
            # Parse class definition
            if line.startswith('@class'):
                # @class NAME = glyph1 glyph2 ...
                # We'll handle this inline in distance rules
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
    
    def generate_atif(self, original_content: str) -> str:
        """Generate ATIF output"""
        output = []
        
        # Header
        output.append("// " + "-" * 79)
        output.append("//")
        output.append("//  Generated ATIF for mark positioning")
        output.append("//  Converted from AAR format")
        output.append("//")
        output.append("// " + "-" * 79)
        output.append("")
        
        # Table 0: Distance kerning
        if self.distance_rules:
            output.append("// " + "-" * 79)
            output.append("// Table 0: Distance kerning (simple pairs)")
            output.append("// " + "-" * 79)
            output.append("")
            output.append("kerning list {")
            output.append("    layout is horizontal;")
            output.append("    kerning is horizontal;")
            output.append("")
            
            for glyph1, target, distance, direction in self.distance_rules:
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
        output.append("    uses anchor points;")
        output.append("    scan glyphs forward;")
        output.append("")
        
        # Define mark anchors (all use index [0])
        output.append("    // Mark anchors (all use index [0])")
        all_marks = set()
        for group_name, marks in self.mark_groups.items():
            for glyph, x, y in marks:
                output.append(f"    anchor {glyph}[0] := ({x}, {y});")
                all_marks.add(glyph)
        output.append("")
        
        # Define base anchors (sequential indices per group)
        output.append("    // Base anchors (sequential indices per semantic)")
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
            output.append("    uses anchor points;")
            output.append("    scan glyphs backward;")
            output.append("")
            
            # NO redefinition of mark [0] anchors - they're already defined in Table 1!
            # Only define new [1] anchors for marks that act as bases
            output.append("    // Mark-to-mark base anchors (use index [1])")
            output.append("    // Note: Attaching anchors [0] already defined in Table 1")
            for mark_glyph, anchors in self.mark2mark.items():
                for group_name, (x, y) in anchors.items():
                    # Use index [1] since [0] is already used for attaching
                    output.append(f"    anchor {mark_glyph}[1] := ({x}, {y});")
            output.append("")
            
            # Classes - marks that can be bases
            base_marks = list(self.mark2mark.keys())
            output.append(f"    class bases {{ {', '.join(base_marks)} }};")
            output.append("")
            
            # All marks as potential attachers
            all_mark_lists = []
            for group_name, marks in self.mark_groups.items():
                mark_list = [m[0] for m in marks]
                class_name = f"marks_{group_name}"
                output.append(f"    class {class_name} {{ {', '.join(mark_list)} }};")
                all_mark_lists.extend(mark_list)
            output.append("")
            
            # State machine
            output.append("    state Start {")
            output.append("        bases: sawBase;")
            output.append("    };")
            output.append("")
            output.append("    state withBase {")
            for group_name in self.mark_groups.keys():
                class_name = f"marks_{group_name}"
                output.append(f"        {class_name}: sawMark;")
            output.append("        bases: sawBase;")
            output.append("    };")
            output.append("")
            output.append("    transition sawBase {")
            output.append("        change state to withBase;")
            output.append("        mark glyph;")
            output.append("    };")
            output.append("")
            output.append("    transition sawMark {")
            output.append("        change state to Start;")
            output.append("        kerning action: snapMark;")
            output.append("    };")
            output.append("")
            output.append("    anchor point action snapMark {")
            output.append("        marked glyph point: 1;")  # Point [1] not [2]!
            output.append("        current glyph point: 0;")
            output.append("    };")
            output.append("};")
        
        return '\n'.join(output)


def main():
    import sys
    
    if len(sys.argv) != 3:
        print("Usage: python aar_to_atif.py input.aar output.atif")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
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
    
    print(f"Converted {input_file} -> {output_file}")


if __name__ == '__main__':
    main()
