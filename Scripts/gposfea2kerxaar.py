#!/usr/bin/env python3
"""
Convert OpenType AFDKO mark positioning syntax to ot2aat format
"""

import re
import sys
from collections import defaultdict

class OTToOT2AAT:
    def __init__(self):
        # Store mark classes: className -> { anchor: [glyphs] }
        # Multiple glyphs can have different anchors in same class
        self.mark_classes = defaultdict(lambda: defaultdict(list))
        self.bases = defaultdict(dict)  # glyph -> {markClass: anchor}
        self.base_marks = defaultdict(dict)  # mark -> {markClass: anchor}
        self.ligatures = defaultdict(lambda: defaultdict(list))  # lig -> {markClass: [anchors]}
        
    def parse_anchor(self, anchor_str):
        """Parse '<anchor X Y>' to '<X, Y>'"""
        match = re.search(r'<anchor\s+(-?\d+)\s+(-?\d+)>', anchor_str)
        if match:
            return f"<{match.group(1)}, {match.group(2)}>"
        return None
    
    def parse_markclass(self, line):
        """Parse: markClass glyph <anchor X Y> @CLASS;"""
        pattern = r'markClass\s+(\S+)\s+<anchor\s+(-?\d+)\s+(-?\d+)>\s+@(\w+);'
        match = re.match(pattern, line.strip())
        
        if match:
            glyph = match.group(1)
            x = match.group(2)
            y = match.group(3)
            class_name = match.group(4)
            
            anchor = f"<{x}, {y}>"
            
            # Group glyphs by their anchor point within the class
            self.mark_classes[class_name][anchor].append(glyph)
            return True
        return False
    
    def parse_base(self, lines, start_idx):
        """
        Parse: pos base glyph <anchor X Y> mark @CLASS
                            <anchor X Y> mark @CLASS;
        """
        line = lines[start_idx].strip()
        
        # Check for 'pos base'
        if not line.startswith('pos base '):
            return 0
        
        # Extract glyph name
        glyph_match = re.match(r'pos base\s+(\S+)', line)
        if not glyph_match:
            return 0
        
        glyph = glyph_match.group(1)
        
        # Collect all anchor definitions (may span multiple lines)
        full_def = line
        lines_consumed = 1
        
        # Continue until we find semicolon
        while not full_def.rstrip().endswith(';'):
            if start_idx + lines_consumed >= len(lines):
                break
            full_def += ' ' + lines[start_idx + lines_consumed].strip()
            lines_consumed += 1
        
        # Find all anchor/mark pairs
        pattern = r'<anchor\s+(-?\d+)\s+(-?\d+)>\s+mark\s+@(\w+)'
        matches = re.findall(pattern, full_def)
        
        for x, y, class_name in matches:
            anchor = f"<{x}, {y}>"
            self.bases[glyph][class_name] = anchor
        
        return lines_consumed
    
    def parse_mark2mark(self, lines, start_idx):
        """
        Parse: pos mark glyph <anchor X Y> mark @CLASS;
        """
        line = lines[start_idx].strip()
        
        if not line.startswith('pos mark '):
            return 0
        
        # Extract mark glyph name
        glyph_match = re.match(r'pos mark\s+(\S+)', line)
        if not glyph_match:
            return 0
        
        mark = glyph_match.group(1)
        
        # Collect full definition
        full_def = line
        lines_consumed = 1
        
        while not full_def.rstrip().endswith(';'):
            if start_idx + lines_consumed >= len(lines):
                break
            full_def += ' ' + lines[start_idx + lines_consumed].strip()
            lines_consumed += 1
        
        # Find anchor/mark pair
        pattern = r'<anchor\s+(-?\d+)\s+(-?\d+)>\s+mark\s+@(\w+)'
        matches = re.findall(pattern, full_def)
        
        for x, y, class_name in matches:
            anchor = f"<{x}, {y}>"
            self.base_marks[mark][class_name] = anchor
        
        return lines_consumed
    
    def parse_ligature(self, lines, start_idx):
        """
        Parse: pos ligature glyph
                   <anchor X Y> mark @CLASS
                   ligComponent
                   <anchor X Y> mark @CLASS;
        """
        line = lines[start_idx].strip()
        
        if not line.startswith('pos ligature '):
            return 0
        
        # Extract ligature name
        lig_match = re.match(r'pos ligature\s+(\S+)', line)
        if not lig_match:
            return 0
        
        ligature = lig_match.group(1)
        
        # Collect full definition
        full_def = line
        lines_consumed = 1
        
        while not full_def.rstrip().endswith(';'):
            if start_idx + lines_consumed >= len(lines):
                break
            full_def += ' ' + lines[start_idx + lines_consumed].strip()
            lines_consumed += 1
        
        # Split by ligComponent
        components = re.split(r'ligComponent', full_def)
        
        for comp_idx, component in enumerate(components):
            # Find all anchor/mark pairs in this component
            pattern = r'<anchor\s+(-?\d+)\s+(-?\d+)>\s+mark\s+@(\w+)'
            matches = re.findall(pattern, component)
            
            for x, y, class_name in matches:
                anchor = f"<{x}, {y}>"
                self.ligatures[ligature][class_name].append(anchor)
        
        return lines_consumed
    
    def parse_file(self, content):
        """Parse entire OpenType feature file"""
        lines = content.split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i].strip()
            
            # Skip empty lines and comments
            if not line or line.startswith('#'):
                i += 1
                continue
            
            # Remove inline comments
            line = re.sub(r'#.*$', '', line).strip()
            
            # Parse markClass
            if line.startswith('markClass'):
                if self.parse_markclass(line):
                    i += 1
                    continue
            
            # Parse pos base
            consumed = self.parse_base(lines, i)
            if consumed > 0:
                i += consumed
                continue
            
            # Parse pos mark
            consumed = self.parse_mark2mark(lines, i)
            if consumed > 0:
                i += consumed
                continue
            
            # Parse pos ligature
            consumed = self.parse_ligature(lines, i)
            if consumed > 0:
                i += consumed
                continue
            
            i += 1
    
    def generate_output(self):
            """Generate ot2aat format"""
            output = []
            
            output.append("# " + "=" * 76)
            output.append("# Converted from OpenType AFDKO format to ot2aat format")
            output.append("# " + "=" * 76)
            output.append("")
            
            # Mark classes - split by unique anchors
            if self.mark_classes:
                output.append("# " + "-" * 76)
                output.append("# MARK CLASSES")
                output.append("# " + "-" * 76)
                output.append("")
                output.append("# Note: OpenType marks with different anchors in same class")
                output.append("# have been split into separate classes for AAT compatibility")
                output.append("")
                
                class_counter = {}  # Track split classes
                
                for class_name in sorted(self.mark_classes.keys()):
                    anchors_dict = self.mark_classes[class_name]
                    
                    # If multiple anchors in same class, split them
                    if len(anchors_dict) > 1:
                        for idx, (anchor, glyphs) in enumerate(sorted(anchors_dict.items())):
                            split_class_name = f"{class_name}_{idx}"
                            output.append(f"@markclass {split_class_name} {anchor}")
                            
                            # Wrap glyphs at reasonable line length
                            line = "    "
                            for glyph in sorted(glyphs):
                                if len(line) + len(glyph) + 1 > 80:
                                    output.append(line.rstrip())
                                    line = "    "
                                line += glyph + " "
                            
                            if line.strip():
                                output.append(line.rstrip())
                            
                            output.append("")
                            
                            # Track the split for updating base references
                            if class_name not in class_counter:
                                class_counter[class_name] = []
                            class_counter[class_name].append(split_class_name)
                    else:
                        # Single anchor - use original class name
                        anchor, glyphs = list(anchors_dict.items())[0]
                        output.append(f"@markclass {class_name} {anchor}")
                        
                        line = "    "
                        for glyph in sorted(glyphs):
                            if len(line) + len(glyph) + 1 > 80:
                                output.append(line.rstrip())
                                line = "    "
                            line += glyph + " "
                        
                        if line.strip():
                            output.append(line.rstrip())
                        
                        output.append("")
                        
                        class_counter[class_name] = [class_name]
            
            # Mark-to-base - need to duplicate for split classes
            if self.bases:
                output.append("# " + "-" * 76)
                output.append("# MARK-TO-BASE")
                output.append("# " + "-" * 76)
                output.append("")
                
                for glyph in sorted(self.bases.keys()):
                    attachments = self.bases[glyph]
                    output.append(f"@base {glyph}")
                    
                    for class_name in sorted(attachments.keys()):
                        anchor = attachments[class_name]
                        
                        # If this class was split, use all split versions
                        if class_name in class_counter:
                            for split_name in class_counter[class_name]:
                                output.append(f"    {split_name} {anchor}")
                        else:
                            output.append(f"    {class_name} {anchor}")
                    
                    output.append("")
            
            # Mark-to-mark
            if self.base_marks:
                output.append("# " + "-" * 76)
                output.append("# MARK-TO-MARK")
                output.append("# " + "-" * 76)
                output.append("")
                
                for mark in sorted(self.base_marks.keys()):
                    attachments = self.base_marks[mark]
                    output.append(f"@mark2mark {mark}")
                    
                    for class_name in sorted(attachments.keys()):
                        anchor = attachments[class_name]
                        
                        if class_name in class_counter:
                            for split_name in class_counter[class_name]:
                                output.append(f"    {split_name} {anchor}")
                        else:
                            output.append(f"    {class_name} {anchor}")
                    
                    output.append("")
            
            # Ligatures
            if self.ligatures:
                output.append("# " + "-" * 76)
                output.append("# MARK-TO-LIGATURE")
                output.append("# " + "-" * 76)
                output.append("")
                
                for ligature in sorted(self.ligatures.keys()):
                    mark_classes = self.ligatures[ligature]
                    output.append(f"@ligature {ligature}")
                    
                    for class_name in sorted(mark_classes.keys()):
                        anchors = mark_classes[class_name]
                        
                        if class_name in class_counter:
                            for split_name in class_counter[class_name]:
                                line = f"    {split_name}"
                                for anchor in anchors:
                                    line += f" {anchor}"
                                output.append(line)
                        else:
                            line = f"    {class_name}"
                            for anchor in anchors:
                                line += f" {anchor}"
                            output.append(line)
                    
                    output.append("")
            
            return '\n'.join(output)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 ot2aat_converter.py input.fea [output.txt]")
        print()
        print("Convert OpenType AFDKO mark positioning to ot2aat format")
        print()
        print("Examples:")
        print("  python3 ot2aat_converter.py marks.fea")
        print("  python3 ot2aat_converter.py marks.fea converted.txt")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    # Read input
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {input_file}")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)
    
    # Convert
    converter = OTToOT2AAT()
    converter.parse_file(content)
    output = converter.generate_output()
    
    # Write output
    if output_file:
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(output)
            print(f"Successfully converted to: {output_file}")
        except Exception as e:
            print(f"Error writing file: {e}")
            sys.exit(1)
    else:
        print(output)
    
    # Print summary
    print(f"\nSummary:", file=sys.stderr)
    print(f"  Mark classes: {len(converter.mark_classes)}", file=sys.stderr)
    print(f"  Bases: {len(converter.bases)}", file=sys.stderr)
    print(f"  Mark-to-mark: {len(converter.base_marks)}", file=sys.stderr)
    print(f"  Ligatures: {len(converter.ligatures)}", file=sys.stderr)

if __name__ == '__main__':
    main()
    