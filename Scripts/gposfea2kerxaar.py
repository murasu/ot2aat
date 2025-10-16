#!/usr/bin/env python3
"""
Convert OpenType GPOS (positioning) features to ot2aat format
Uses OpenType's own mark class grouping instead of arbitrary Y-coordinate thresholds

SCOPE: GPOS features only (kerning, mark positioning, distance adjustments)
       GSUB (substitution) features are out of scope

KEY PRINCIPLE: Preserve OpenType's mark class grouping
- Each OpenType mark class becomes a semantic group
- Groups are labeled for readability (TOP/BOTTOM/MIDDLE based on Y position)
- AAT anchor indices assigned by group order, not absolute Y values
"""

import re
import sys
from collections import defaultdict
from typing import Dict, List, Tuple, Optional, Set

# MARK: - Data Structures

class Mark:
    """Individual mark with coordinates and OpenType class"""
    def __init__(self, glyph: str, x: int, y: int, ot_class: str):
        self.glyph = glyph
        self.x = x
        self.y = y
        self.ot_class = ot_class  # Track which OpenType class this came from
    
    def anchor_str(self) -> str:
        return f"<{self.x}, {self.y}>"


class SemanticGroup:
    """Group of marks that attach to the same base anchor point"""
    def __init__(self, name: str):
        self.name = name  # e.g., "TOP", "BOTTOM", "ATTACHMENT_0"
        self.marks: List[Mark] = []
        self.marks_set: Set[str] = set()  # Track glyph names to avoid duplicates
    
    def add_mark(self, mark: Mark):
        if mark.glyph not in self.marks_set:
            self.marks.append(mark)
            self.marks_set.add(mark.glyph)
    
    def is_empty(self) -> bool:
        return len(self.marks) == 0


class BaseGlyph:
    """Base glyph with multiple attachment points"""
    def __init__(self, glyph: str):
        self.glyph = glyph
        self.attachments: Dict[str, Tuple[int, int]] = {}  # semantic_group -> (x, y)
    
    def add_attachment(self, semantic_group: str, x: int, y: int):
        self.attachments[semantic_group] = (x, y)


class BaseMarkGlyph:
    """Mark that receives other marks (mark-to-mark)"""
    def __init__(self, mark: str):
        self.mark = mark
        self.attachments: Dict[str, Tuple[int, int]] = {}  # semantic_group -> (x, y)
    
    def add_attachment(self, semantic_group: str, x: int, y: int):
        self.attachments[semantic_group] = (x, y)


class LigatureGlyph:
    """Ligature with component-based attachments"""
    def __init__(self, ligature: str):
        self.ligature = ligature
        self.component_anchors: Dict[str, List[Tuple[int, int]]] = defaultdict(list)
    
    def add_component_anchor(self, semantic_group: str, x: int, y: int):
        self.component_anchors[semantic_group].append((x, y))


# MARK: - Main Converter Class

class OTToOT2AAT:
    def __init__(self):
        # Track marks by OpenType class
        # ot_class -> [(glyph, x, y), ...]
        self.ot_marks: Dict[str, List[Tuple[str, int, int]]] = defaultdict(list)
        
        # Track base attachments: base_glyph -> [(ot_class, x, y), ...]
        self.base_attachments: Dict[str, List[Tuple[str, int, int]]] = defaultdict(list)
        
        # Track base mark attachments: base_mark -> [(ot_class, x, y), ...]
        self.base_mark_attachments: Dict[str, List[Tuple[str, int, int]]] = defaultdict(list)
        
        # Track ligature attachments: ligature -> {ot_class: [(x, y), ...]}
        self.ligature_attachments: Dict[str, Dict[str, List[Tuple[int, int]]]] = defaultdict(lambda: defaultdict(list))
        
        # Final semantic groups (computed after parsing)
        self.semantic_groups: Dict[str, SemanticGroup] = {}
        
        # Mapping from OpenType class to semantic group name
        self.ot_class_to_semantic: Dict[str, str] = {}
        
        # Final structured data for output
        self.bases: Dict[str, BaseGlyph] = {}
        self.base_marks: Dict[str, BaseMarkGlyph] = {}
        self.ligatures: Dict[str, LigatureGlyph] = {}
        
        self.distance_rules = []
        self.lookups = {}
        self.global_classes: Dict[str, List[str]] = {}
    
    def parse_class_definition(self, line: str) -> bool:
        """Parse: @CLASS = [glyph1 glyph2 glyph3];"""
        pattern = r'@(\w+)\s*=\s*\[([^\]]+)\];'
        match = re.match(pattern, line.strip())
        
        if match:
            class_name = match.group(1)
            glyphs_str = match.group(2)
            glyphs = [g.strip() for g in glyphs_str.split() if g.strip()]
            
            if glyphs:
                self.global_classes[class_name] = glyphs
                print(f"  Defined class @{class_name} with {len(glyphs)} glyphs", file=sys.stderr)
            return True
        return False
    
    def expand_class_reference(self, element: str) -> List[str]:
        """Expand @CLASS to list of glyphs, or return single glyph"""
        if element.startswith('@'):
            class_name = element[1:]
            if class_name in self.global_classes:
                return self.global_classes[class_name]
            else:
                print(f"Warning: Undefined class @{class_name}", file=sys.stderr)
                return []
        else:
            return [element]
    
    def parse_pair_positioning(self, line: str) -> bool:
        """Parse: pos [glyph1 glyph2] [glyph3] <xPlacement yPlacement xAdvance yAdvance>;"""
        
        # Match bracketed class or single glyph for both left and right
        # (?:\[\s*([^\]]+)\s*\]|(\S+)) matches either [class] or glyph
        pattern = r'pos\s+(?:\[\s*([^\]]+)\s*\]|(\S+))\s+(?:\[\s*([^\]]+)\s*\]|(\S+))\s+<(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)>;'
        match = re.match(pattern, line.strip())
        
        if match:
            # Left can be group 1 (bracketed) or group 2 (single)
            left_elem = match.group(1) if match.group(1) else match.group(2)
            # Right can be group 3 (bracketed) or group 4 (single)
            right_elem = match.group(3) if match.group(3) else match.group(4)
            
            x_placement = int(match.group(5))
            y_placement = int(match.group(6))
            x_advance = int(match.group(7))
            y_advance = int(match.group(8))
            
            # For AAT distance rules, we use xAdvance (horizontal kerning)
            if x_advance == 0:
                return True  # Valid but nothing to convert
            
            # Handle bracketed classes (split on whitespace) or single glyphs
            left_glyphs = left_elem.split() if ' ' in left_elem else [left_elem]
            right_glyphs = right_elem.split() if ' ' in right_elem else [right_elem]
            
            for left in left_glyphs:
                for right in right_glyphs:
                    self.distance_rules.append((left, right, x_advance, 'horizontal'))
            
            return True
        
        return False
    
    def parse_markclass(self, line: str):
        """Parse: markClass glyph <anchor X Y> @CLASS;"""
        # Handle optional brackets: [glyph] or glyph
        pattern = r'markClass\s+\[?\s*(\S+?)\s*\]?\s+<anchor\s+(-?\d+)\s+(-?\d+)>\s+@(\w+);'
        match = re.match(pattern, line.strip())
        
        if match:
            glyph = match.group(1)
            x = int(match.group(2))
            y = int(match.group(3))
            ot_class = match.group(4)
            
            # Store mark with its OpenType class
            self.ot_marks[ot_class].append((glyph, x, y))
            return True
        return False
    
    def parse_base(self, lines: List[str], start_idx: int) -> int:
        """Parse: pos base glyph <anchor X Y> mark @CLASS ..."""
        line = lines[start_idx].strip()
        
        if not line.startswith('pos base '):
            return 0
        
        glyph_match = re.match(r'pos base\s+(\S+)', line)
        if not glyph_match:
            return 0
        
        glyph = glyph_match.group(1)
        
        # Collect full definition
        full_def = line
        lines_consumed = 1
        
        while not full_def.rstrip().endswith(';'):
            if start_idx + lines_consumed >= len(lines):
                break
            full_def += ' ' + lines[start_idx + lines_consumed].strip()
            lines_consumed += 1
        
        # Find all anchor/mark pairs
        pattern = r'<anchor\s+(-?\d+)\s+(-?\d+)>\s+mark\s+@(\w+)'
        matches = re.findall(pattern, full_def)
        
        for x, y, ot_class in matches:
            self.base_attachments[glyph].append((ot_class, int(x), int(y)))
        
        return lines_consumed
    
    def parse_mark2mark(self, lines: List[str], start_idx: int) -> int:
        """Parse: pos mark glyph <anchor X Y> mark @CLASS;"""
        line = lines[start_idx].strip()
        
        if not line.startswith('pos mark '):
            return 0
        
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
        
        # Find anchor/mark pairs
        pattern = r'<anchor\s+(-?\d+)\s+(-?\d+)>\s+mark\s+@(\w+)'
        matches = re.findall(pattern, full_def)
        
        for x, y, ot_class in matches:
            self.base_mark_attachments[mark].append((ot_class, int(x), int(y)))
        
        return lines_consumed
    
    def parse_ligature(self, lines: List[str], start_idx: int) -> int:
        """Parse: pos ligature glyph <anchor X Y> mark @CLASS ligComponent ..."""
        line = lines[start_idx].strip()
        
        if not line.startswith('pos ligature '):
            return 0
        
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
        
        for component in components:
            pattern = r'<anchor\s+(-?\d+)\s+(-?\d+)>\s+mark\s+@(\w+)'
            matches = re.findall(pattern, component)
            
            for x, y, ot_class in matches:
                self.ligature_attachments[ligature][ot_class].append((int(x), int(y)))
        
        return lines_consumed
    
    def parse_lookup(self, lines: List[str], start_idx: int) -> int:
        """Parse lookup definition for positioning rules and value records"""
        line = lines[start_idx].strip()
        
        if not line.startswith('lookup '):
            return 0
        
        lookup_match = re.match(r'lookup\s+(\S+)', line)
        if not lookup_match:
            return 0
        
        lookup_name = lookup_match.group(1)
        lookup_values = {}
        
        lines_consumed = 1
        
        while start_idx + lines_consumed < len(lines):
            current_line = lines[start_idx + lines_consumed].strip()
            
            if current_line.startswith('}'):
                lines_consumed += 1
                break
            
            if not current_line or current_line.startswith('#'):
                lines_consumed += 1
                continue
            
            current_line = re.sub(r'#.*$', '', current_line).strip()
            
            if current_line.startswith('markClass'):
                self.parse_markclass(current_line)
                lines_consumed += 1
                continue
            
            if current_line.startswith('pos '):
                if not ('mark' in current_line or 'base' in current_line or
                        'ligature' in current_line or "'" in current_line):
                    # Collect full definition (may span multiple lines)
                    full_def = current_line
                    temp_consumed = 1
                    
                    while not full_def.rstrip().endswith(';'):
                        if start_idx + lines_consumed + temp_consumed >= len(lines):
                            break
                        full_def += ' ' + lines[start_idx + lines_consumed + temp_consumed].strip()
                        temp_consumed += 1
                    
                    if self.parse_pair_positioning(full_def):
                        lines_consumed += temp_consumed
                        continue
                
            if current_line.startswith('pos base '):
                consumed = self.parse_base(lines, start_idx + lines_consumed)
                if consumed > 0:
                    lines_consumed += consumed
                    continue
            
            if current_line.startswith('pos mark '):
                consumed = self.parse_mark2mark(lines, start_idx + lines_consumed)
                if consumed > 0:
                    lines_consumed += consumed
                    continue
            
            if current_line.startswith('pos ligature '):
                consumed = self.parse_ligature(lines, start_idx + lines_consumed)
                if consumed > 0:
                    lines_consumed += consumed
                    continue
            
            if "'" in current_line and 'lookup' in current_line:
                pattern = r'pos\s+\[?\s*(\S+?)\s*\]?\s+(?:\[([^\]]+)\]|(\S+))\'\s+lookup\s+(\w+);'
                match = re.match(pattern, current_line)
                
                if match:
                    context = match.group(1)
                    targets_in_brackets = match.group(2)
                    single_target = match.group(3)
                    lookup_ref = match.group(4)
                    
                    targets = targets_in_brackets.split() if targets_in_brackets else [single_target]
                    
                    if lookup_ref in self.lookups:
                        lookup_values_ref = self.lookups[lookup_ref]
                        
                        for target in targets:
                            if target in lookup_values_ref:
                                values = lookup_values_ref[target]
                                
                                x_placement = values['x_placement']
                                y_placement = values['y_placement']
                                
                                if x_placement != 0 and y_placement != 0:
                                    print(f"Warning: Both x and y placement for {target}, using y_placement only",
                                          file=sys.stderr)
                                    direction = 'vertical'
                                    adjustment = y_placement
                                elif x_placement != 0:
                                    direction = 'horizontal'
                                    adjustment = x_placement
                                elif y_placement != 0:
                                    direction = 'vertical'
                                    adjustment = y_placement
                                else:
                                    continue
                                
                                self.distance_rules.append((context, target, adjustment, direction))
                
                lines_consumed += 1
                continue
            
            pattern = r'pos\s+\[?\s*(\S+?)\s*\]?\s+<(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)>;'
            match = re.match(pattern, current_line)
            
            if match:
                glyph = match.group(1)
                x_placement = int(match.group(2))
                y_placement = int(match.group(3))
                x_advance = int(match.group(4))
                y_advance = int(match.group(5))
                
                lookup_values[glyph] = {
                    'x_placement': x_placement,
                    'y_placement': y_placement,
                    'x_advance': x_advance,
                    'y_advance': y_advance
                }
            
            lines_consumed += 1
        
        self.lookups[lookup_name] = lookup_values
        return lines_consumed
    
    def compute_semantic_groups(self):
        """Compute semantic groups by deduplicating marks across OpenType classes"""
        
        # Step 1: Build a map of mark identity (glyph, x, y) to all OT classes that define it
        mark_identity_to_classes: Dict[Tuple[str, int, int], Set[str]] = defaultdict(set)
        
        for ot_class, marks in self.ot_marks.items():
            for glyph, x, y in marks:
                mark_identity_to_classes[(glyph, x, y)].add(ot_class)
        
        # Step 2: Group OT classes that share marks (they're the same semantic group)
        ot_class_groups: List[Set[str]] = []
        processed_classes = set()
        
        for ot_class in self.ot_marks.keys():
            if ot_class in processed_classes:
                continue
            
            # Find all marks in this OT class
            marks_in_class = {(g, x, y) for g, x, y in self.ot_marks[ot_class]}
            
            # Find all OT classes that share these marks
            related_classes = set([ot_class])
            for mark_id in marks_in_class:
                related_classes.update(mark_identity_to_classes[mark_id])
            
            ot_class_groups.append(related_classes)
            processed_classes.update(related_classes)
        
        # Step 3: For each group, determine representative Y for sorting
        group_base_ys = []
        for class_group in ot_class_groups:
            # Collect Y values from bases AND ligatures
            attachment_ys = []
            
            # From base attachments
            for ot_class in class_group:
                for base_glyph, attachments in self.base_attachments.items():
                    for att_class, x, y in attachments:
                        if att_class in class_group:
                            attachment_ys.append(y)
            
            # From ligature attachments (NEW!)
            for ot_class in class_group:
                for ligature, ot_class_anchors in self.ligature_attachments.items():
                    if ot_class in ot_class_anchors:
                        for x, y in ot_class_anchors[ot_class]:
                            attachment_ys.append(y)
            
            # Use median attachment Y, or median mark Y if no attachments
            if attachment_ys:
                attachment_ys_sorted = sorted(attachment_ys)
                median_y = attachment_ys_sorted[len(attachment_ys_sorted) // 2]
            else:
                # No bases or ligatures, use mark Y
                mark_ys = []
                for ot_class in class_group:
                    mark_ys.extend([y for _, _, y in self.ot_marks[ot_class]])
                mark_ys_sorted = sorted(set(mark_ys))
                median_y = mark_ys_sorted[len(mark_ys_sorted) // 2] if mark_ys_sorted else 0
            
            group_base_ys.append((class_group, median_y))
        
        # Step 4: Sort groups by median Y
        group_base_ys.sort(key=lambda x: x[1])
        
        # Step 5: Assign semantic names
        num_groups = len(group_base_ys)
        
        for idx, (class_group, median_y) in enumerate(group_base_ys):
            # Determine semantic name
            if num_groups == 1:
                semantic_name = "ATTACHMENT_0"
            elif num_groups == 2:
                semantic_name = "BOTTOM" if idx == 0 else "TOP"
            elif num_groups == 3:
                if idx == 0:
                    semantic_name = "BOTTOM"
                elif idx == 1:
                    semantic_name = "MIDDLE"
                else:
                    semantic_name = "TOP"
            else:
                semantic_name = f"ATTACHMENT_{idx}"
            
            # Map all OT classes in this group to the semantic name
            for ot_class in class_group:
                self.ot_class_to_semantic[ot_class] = semantic_name
            
            # Create semantic group
            if semantic_name not in self.semantic_groups:
                self.semantic_groups[semantic_name] = SemanticGroup(semantic_name)
            
            # Add unique marks (deduplicated by identity)
            unique_marks = set()
            for ot_class in class_group:
                for glyph, x, y in self.ot_marks[ot_class]:
                    unique_marks.add((glyph, x, y))
            
            # Add to semantic group
            representative_class = list(class_group)[0]
            for glyph, x, y in sorted(unique_marks):
                mark = Mark(glyph, x, y, representative_class)
                self.semantic_groups[semantic_name].add_mark(mark)
        
        print(f"\nComputed semantic groups:", file=sys.stderr)
        for semantic_name, group in sorted(self.semantic_groups.items()):
            ot_classes = [oc for oc, sn in self.ot_class_to_semantic.items() if sn == semantic_name]
            print(f"  {semantic_name}: {len(group.marks)} unique marks from OT classes: {', '.join(sorted(ot_classes))}", file=sys.stderr)
                    
        # DEBUG: Show what we found
        print(f"\nDEBUG - OT class groups detected: {len(ot_class_groups)}", file=sys.stderr)
        for idx, (class_group, median_y) in enumerate(group_base_ys):
            print(f"  Group {idx}: classes={sorted(class_group)}, median_y={median_y}", file=sys.stderr)
        
        # DEBUG: Show ligature attachments
        print(f"\nDEBUG - Ligature attachments:", file=sys.stderr)
        for lig, classes in self.ligature_attachments.items():
            print(f"  {lig}:", file=sys.stderr)
            for ot_class, anchors in classes.items():
                print(f"    {ot_class}: {anchors}", file=sys.stderr)


            
    
    def build_structured_data(self):
        """Build final structured data for output"""
        
        # Build bases - preserve OpenType anchor order
        for base_glyph, attachments in self.base_attachments.items():
            if base_glyph not in self.bases:
                self.bases[base_glyph] = BaseGlyph(base_glyph)
            
            for ot_class, x, y in attachments:
                # Simple mapping: OT class → semantic group
                semantic_name = self.ot_class_to_semantic.get(ot_class, "ATTACHMENT_0")
                self.bases[base_glyph].add_attachment(semantic_name, x, y)
        
        # Build base marks
        for base_mark, attachments in self.base_mark_attachments.items():
            if base_mark not in self.base_marks:
                self.base_marks[base_mark] = BaseMarkGlyph(base_mark)
            
            for ot_class, x, y in attachments:
                semantic_name = self.ot_class_to_semantic.get(ot_class, "ATTACHMENT_0")
                self.base_marks[base_mark].add_attachment(semantic_name, x, y)
        
        # Build ligatures
        for ligature, ot_class_anchors in self.ligature_attachments.items():
            if ligature not in self.ligatures:
                self.ligatures[ligature] = LigatureGlyph(ligature)
            
            for ot_class, anchors in ot_class_anchors.items():
                semantic_name = self.ot_class_to_semantic.get(ot_class, "ATTACHMENT_0")
                
                for x, y in anchors:
                    self.ligatures[ligature].add_component_anchor(semantic_name, x, y)
                        
                        
    def parse_file(self, content: str):
        """Parse entire OpenType feature file"""
        lines = content.split('\n')
        i = 0
        
        print(f"Parsing {len(lines)} lines...", file=sys.stderr)
        
        while i < len(lines):
            line = lines[i].strip()
            
            if not line or line.startswith('#'):
                i += 1
                continue
            
            line = re.sub(r'#.*$', '', line).strip()
            
            if line.startswith('@') and '=' in line:
                if self.parse_class_definition(line):
                    i += 1
                    continue
            
            consumed = self.parse_lookup(lines, i)
            if consumed > 0:
                print(f"  Parsed lookup at line {i+1}", file=sys.stderr)
                i += consumed
                continue
            
            i += 1
        
        # Compute semantic groups from parsed data
        self.compute_semantic_groups()
        
        # Build structured data
        self.build_structured_data()
        
        # Print summary
        print(f"\nParsed content:", file=sys.stderr)
        print(f"  Global classes: {len(self.global_classes)}", file=sys.stderr)
        print(f"  OpenType mark classes: {len(self.ot_marks)}", file=sys.stderr)
        print(f"  Semantic groups: {len(self.semantic_groups)}", file=sys.stderr)
        print(f"  Bases: {len(self.bases)}", file=sys.stderr)
        print(f"  Mark-to-mark: {len(self.base_marks)}", file=sys.stderr)
        print(f"  Ligatures: {len(self.ligatures)}", file=sys.stderr)
        print(f"  Distance rules: {len(self.distance_rules)}", file=sys.stderr)
    
    def generate_output(self) -> str:
        """Generate ot2aat format"""
        output = []
        
        output.append("# " + "=" * 76)
        output.append("# Converted from OpenType GPOS format to ot2aat format")
        output.append("# Preserving OpenType mark class grouping")
        output.append("# " + "=" * 76)
        output.append("")
        
        # Global classes
        if self.global_classes:
            output.append("# " + "-" * 76)
            output.append("# GLOBAL CLASS DEFINITIONS")
            output.append("# " + "-" * 76)
            output.append("")
            
            for class_name in sorted(self.global_classes.keys()):
                glyphs = self.global_classes[class_name]
                output.append(f"@class {class_name} = {' '.join(glyphs)}")
            
            output.append("")
        
        # Mark groups
        if self.semantic_groups:
            output.append("# " + "-" * 76)
            output.append("# MARK GROUPS")
            output.append("# " + "-" * 76)
            output.append("#")
            output.append("# Groups derived from OpenType mark classes.")
            output.append("# In AAT, all marks use anchor index [0].")
            output.append("# Bases use different indices [0], [1], [2]... for each group.")
            output.append("# " + "-" * 76)
            output.append("")
            
            # Output in consistent order
            for group_name in sorted(self.semantic_groups.keys()):
                group = self.semantic_groups[group_name]
                if group.is_empty():
                    continue
                
                output.append(f"@mark_group {group_name}")
                
                for mark in group.marks:
                    output.append(f"    {mark.glyph} {mark.anchor_str()}")
                
                output.append("")
        
        # Distance rules
        if self.distance_rules:
            output.append("# " + "-" * 76)
            output.append("# DISTANCE ADJUSTMENTS")
            output.append("# " + "-" * 76)
            output.append("")
            
            by_context = defaultdict(list)
            for context, target, adjustment, direction in self.distance_rules:
                by_context[context].append((target, adjustment, direction))
            
            for context in sorted(by_context.keys()):
                rules = by_context[context]
                adjustments = set((adj, dir) for _, adj, dir in rules)
                
                if len(adjustments) == 1 and len(rules) > 1:
                    targets = [target for target, _, _ in rules]
                    adjustment, direction = list(adjustments)[0]
                    
                    class_name = f"TARGETS_{context.replace('.', '_')}"
                    output.append(f"@class {class_name} = {' '.join(sorted(targets))}")
                    output.append(f"@distance {context} @{class_name} {adjustment} {direction}")
                    output.append("")
                else:
                    for target, adjustment, direction in sorted(rules):
                        output.append(f"@distance {context} {target} {adjustment} {direction}")
                    output.append("")
        
        # Mark-to-base
        if self.bases:
            output.append("# " + "-" * 76)
            output.append("# MARK-TO-BASE")
            output.append("# " + "-" * 76)
            output.append("")
            
            for glyph in sorted(self.bases.keys()):
                base = self.bases[glyph]
                
                output.append(f"@base {glyph}")
                
                for group_name in sorted(base.attachments.keys()):
                    x, y = base.attachments[group_name]
                    output.append(f"    {group_name} <{x}, {y}>")
                
                output.append("")
        
        # Mark-to-mark
        if self.base_marks:
            output.append("# " + "-" * 76)
            output.append("# MARK-TO-MARK")
            output.append("# " + "-" * 76)
            output.append("")
            
            for mark in sorted(self.base_marks.keys()):
                base_mark = self.base_marks[mark]
                
                output.append(f"@mark2mark {mark}")
                
                for group_name in sorted(base_mark.attachments.keys()):
                    x, y = base_mark.attachments[group_name]
                    output.append(f"    {group_name} <{x}, {y}>")
                
                output.append("")
        
        # Mark-to-ligature
        if self.ligatures:
            output.append("# " + "-" * 76)
            output.append("# MARK-TO-LIGATURE")
            output.append("# " + "-" * 76)
            output.append("")
            
            for ligature in sorted(self.ligatures.keys()):
                lig = self.ligatures[ligature]
                
                output.append(f"@ligature {ligature}")
                
                for group_name in sorted(lig.component_anchors.keys()):
                    anchors = lig.component_anchors[group_name]
                    line = f"    {group_name}"
                    for x, y in anchors:
                        line += f" <{x}, {y}>"
                    output.append(line)
                
                output.append("")
        
        return '\n'.join(output)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 gposfea2kerxaar.py input.fea [output.aar]")
        print()
        print("Convert OpenType GPOS (positioning) features to ot2aat format")
        print()
        print("Scope: GPOS only (kerning, marks, distance)")
        print("       GSUB (substitution) is out of scope")
        print()
        print("Examples:")
        print("  python3 gposfea2kerxaar.py marks.fea")
        print("  python3 gposfea2kerxaar.py marks.fea converted.aar")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {input_file}")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)
    
    converter = OTToOT2AAT()
    converter.parse_file(content)
    output = converter.generate_output()
    
    if output_file:
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(output)
            print(f"\nSuccessfully converted to: {output_file}")
        except Exception as e:
            print(f"Error writing file: {e}")
            sys.exit(1)
    else:
        print(output)
    
    print(f"\nConversion complete!", file=sys.stderr)

if __name__ == '__main__':
    main()
