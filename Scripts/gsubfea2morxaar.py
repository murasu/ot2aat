#!/usr/bin/env python3
"""
Convert OpenType GSUB (substitution) features to ot2aat .aar format

SCOPE: GSUB features only (substitution, ligatures, contextual)
       GPOS (positioning) features are out of scope

Supports:
- Type 1: Single substitution → noncontextual .aar
- Type 2: Multiple substitution → .rules format (one-to-many)
- Type 4: Ligature substitution → ligature .aar
- Type 6: Contextual chaining substitution → contextual .aar
"""

import re
import sys
from collections import defaultdict
from typing import Dict, List, Tuple, Optional, Set

# MARK: - Data Structures

class SingleSubstitution:
    """Simple 1:1 glyph substitution"""
    def __init__(self, source: str, target: str):
        self.source = source
        self.target = target


class LigatureSubstitution:
    """Multiple glyphs → single ligature"""
    def __init__(self, target: str, components: List[str]):
        self.target = target
        self.components = components


class MultipleSubstitution:
    """Single glyph → multiple glyphs (decomposition)"""
    def __init__(self, source: str, targets: List[str]):
        self.source = source
        self.targets = targets


class ContextualSubstitution:
    """Context-based substitution"""
    def __init__(self, context: List[str], marked_indices: List[int], 
                 substitutions: Dict[int, str], lookup_refs: Dict[int, str]):
        self.context = context  # Full context pattern
        self.marked_indices = marked_indices  # Which positions have '
        self.substitutions = substitutions  # index -> replacement (unused now, will be inlined)
        self.lookup_refs = lookup_refs  # index -> lookup name to inline


# MARK: - Main Converter Class

class GSUBToAAR:
    def __init__(self):
        # Store different substitution types
        self.single_subs: List[SingleSubstitution] = []
        self.ligatures: List[LigatureSubstitution] = []
        self.multiple_subs: List[MultipleSubstitution] = []
        self.contextual_subs: List[ContextualSubstitution] = []
        
        # Track lookups for inlining
        self.lookups: Dict[str, List[str]] = {}
        
        # Track classes
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
                print(f"  Defined class @{class_name} with {len(glyphs)} glyphs", 
                      file=sys.stderr)
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
    
    def detect_substitution_type(self, line: str) -> Optional[str]:
        """Detect GSUB lookup type from a substitution line"""
        line = line.strip()
        
        if not line.startswith('sub '):
            return None
        
        # Type 6: Contextual (has ')
        if "'" in line:
            return 'contextual'
        
        # Count elements on each side
        parts = line.split(' by ')
        if len(parts) != 2:
            return None
        
        left = parts[0].replace('sub ', '').strip()
        right = parts[1].rstrip(';').strip()
        
        left_elements = left.split()
        right_elements = right.split()
        
        # Type 2: Multiple substitution (1 → many)
        if len(left_elements) == 1 and len(right_elements) > 1:
            return 'multiple'
        
        # Type 4: Ligature (many → 1)
        if len(left_elements) > 1 and len(right_elements) == 1:
            return 'ligature'
        
        # Type 1: Single substitution (1 → 1)
        if len(left_elements) == 1 and len(right_elements) == 1:
            return 'single'
        
        return None
    
    def parse_single_substitution(self, line: str) -> bool:
        """Parse: sub glyph1 by glyph2;"""
        pattern = r'sub\s+(\S+)\s+by\s+(\S+);'
        match = re.match(pattern, line.strip())
        
        if match:
            source = match.group(1)
            target = match.group(2)
            self.single_subs.append(SingleSubstitution(source, target))
            return True
        return False
    
    def parse_ligature(self, line: str) -> bool:
        """Parse: sub glyph1 glyph2 glyph3 by ligature;"""
        pattern = r'sub\s+(.*?)\s+by\s+(\S+);'
        match = re.match(pattern, line.strip())
        
        if match:
            components_str = match.group(1)
            target = match.group(2)
            components = [c.strip() for c in components_str.split() if c.strip()]
            
            if len(components) > 1:
                self.ligatures.append(LigatureSubstitution(target, components))
                return True
        return False
    
    def parse_multiple_substitution(self, line: str) -> bool:
        """Parse: sub glyph by glyph1 glyph2 glyph3;"""
        pattern = r'sub\s+(\S+)\s+by\s+(.*?);'
        match = re.match(pattern, line.strip())
        
        if match:
            source = match.group(1)
            targets_str = match.group(2)
            targets = [t.strip() for t in targets_str.split() if t.strip()]
            
            if len(targets) > 1:
                self.multiple_subs.append(MultipleSubstitution(source, targets))
                return True
        return False
    
    def parse_contextual_substitution(self, line: str) -> bool:
        """Parse: sub glyph1' lookup LOOKUP context' lookup LOOKUP2;"""
        # Basic pattern for contextual with marks
        if "'" not in line:
            return False
        
        # Extract the pattern
        pattern = r'sub\s+(.*?);'
        match = re.match(pattern, line.strip())
        
        if not match:
            return False
        
        content = match.group(1)
        elements = content.split()
        
        context = []
        marked_indices = []
        lookup_refs = {}
        
        i = 0
        idx = 0
        while i < len(elements):
            elem = elements[i]
            
            if elem == 'lookup':
                # Next element is lookup name
                if i + 1 < len(elements):
                    lookup_name = elements[i + 1]
                    # Associate with previous marked position
                    if marked_indices:
                        lookup_refs[marked_indices[-1]] = lookup_name
                    i += 2
                    continue
            
            # Check if marked
            if elem.endswith("'"):
                clean_elem = elem.rstrip("'")
                context.append(clean_elem)
                marked_indices.append(idx)
                idx += 1
            else:
                context.append(elem)
                idx += 1
            
            i += 1
        
        if context and marked_indices:
            self.contextual_subs.append(
                ContextualSubstitution(context, marked_indices, {}, lookup_refs)
            )
            return True
        
        return False
    
    def parse_lookup(self, lines: List[str], start_idx: int) -> int:
        """Parse lookup definition"""
        line = lines[start_idx].strip()
        
        if not line.startswith('lookup '):
            return 0
        
        lookup_match = re.match(r'lookup\s+(\S+)', line)
        if not lookup_match:
            return 0
        
        lookup_name = lookup_match.group(1)
        lookup_contents = []
        
        lines_consumed = 1
        
        while start_idx + lines_consumed < len(lines):
            current_line = lines[start_idx + lines_consumed].strip()
            
            if current_line.startswith('}'):
                lines_consumed += 1
                break
            
            if not current_line or current_line.startswith('#'):
                lines_consumed += 1
                continue
            
            # Remove comments
            current_line = re.sub(r'#.*$', '', current_line).strip()
            
            # Class definition inside lookup
            if current_line.startswith('@') and '=' in current_line:
                self.parse_class_definition(current_line)
                lines_consumed += 1
                continue
            
            # Substitution rules
            if current_line.startswith('sub '):
                sub_type = self.detect_substitution_type(current_line)
                
                if sub_type == 'single':
                    self.parse_single_substitution(current_line)
                elif sub_type == 'ligature':
                    self.parse_ligature(current_line)
                elif sub_type == 'multiple':
                    self.parse_multiple_substitution(current_line)
                elif sub_type == 'contextual':
                    self.parse_contextual_substitution(current_line)
                
                # Store raw line in lookup for potential inlining
                lookup_contents.append(current_line)
            
            lines_consumed += 1
        
        self.lookups[lookup_name] = lookup_contents
        print(f"  Parsed lookup {lookup_name} with {len(lookup_contents)} rules", 
              file=sys.stderr)
        
        return lines_consumed
    
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
            
            # Remove comments
            line = re.sub(r'#.*$', '', line).strip()
            
            # Class definition
            if line.startswith('@') and '=' in line:
                if self.parse_class_definition(line):
                    i += 1
                    continue
            
            # Lookup definition
            consumed = self.parse_lookup(lines, i)
            if consumed > 0:
                i += consumed
                continue
            
            i += 1
        
        # Print summary
        print(f"\nParsed content:", file=sys.stderr)
        print(f"  Global classes: {len(self.global_classes)}", file=sys.stderr)
        print(f"  Single substitutions: {len(self.single_subs)}", file=sys.stderr)
        print(f"  Ligatures: {len(self.ligatures)}", file=sys.stderr)
        print(f"  Multiple substitutions: {len(self.multiple_subs)}", file=sys.stderr)
        print(f"  Contextual substitutions: {len(self.contextual_subs)}", file=sys.stderr)
    
    def inline_lookup_substitutions(self, lookup_name: str) -> Dict[str, str]:
        """
        Extract all single substitutions from a lookup.
        Returns dict of {source: target}.
        If same source appears multiple times, last one wins.
        """
        if lookup_name not in self.lookups:
            print(f"ERROR: Lookup '{lookup_name}' not found!", file=sys.stderr)
            return {}
        
        substitutions = {}
        lookup_rules = self.lookups[lookup_name]
        
        for rule in lookup_rules:
            # Only handle simple substitutions for now
            pattern = r'sub\s+(\S+)\s+by\s+(\S+);'
            match = re.match(pattern, rule.strip())
            if match:
                source = match.group(1)
                target = match.group(2)
                # Last one wins
                substitutions[source] = target
        
        return substitutions
    
    def generate_simple_context(self, ctx: ContextualSubstitution) -> str:
        """Generate after/before/between context rule"""
        marked_pos = ctx.marked_indices[0]
        pattern_length = len(ctx.context)
        
        # Get the target and replacement from lookup
        lookup_name = ctx.lookup_refs[marked_pos]
        substitutions = self.inline_lookup_substitutions(lookup_name)
        
        if not substitutions:
            return f"# ERROR: No substitutions found in lookup {lookup_name}"
        
        target_glyph = ctx.context[marked_pos]
        
        # Determine context type
        if marked_pos == 0 and pattern_length > 1:
            # BEFORE context (first position marked)
            context_after = ' '.join(ctx.context[1:])
            
            # Generate rules for each substitution
            rules = []
            for source, target in substitutions.items():
                rules.append(f"before {context_after}: {source} => {target}")
            return '\n'.join(rules)
        
        elif marked_pos == pattern_length - 1 and pattern_length > 1:
            # AFTER context (last position marked)
            context_before = ' '.join(ctx.context[:-1])
            
            rules = []
            for source, target in substitutions.items():
                rules.append(f"after {context_before}: {source} => {target}")
            return '\n'.join(rules)
        
        elif 0 < marked_pos < pattern_length - 1:
            # BETWEEN context (middle position marked)
            context_before = ' '.join(ctx.context[:marked_pos])
            context_after = ' '.join(ctx.context[marked_pos+1:])
            
            rules = []
            for source, target in substitutions.items():
                rules.append(f"between {context_before} and {context_after}: {source} => {target}")
            return '\n'.join(rules)
        
        else:
            return f"# ERROR: Cannot determine context type for pattern: {' '.join(ctx.context)}"
    
    def generate_when_context(self, ctx: ContextualSubstitution) -> str:
        """Generate when context rule with multiple substitutions"""
        pattern = ' '.join(ctx.context)
        
        # Check pattern length
        if len(ctx.context) > 10:
            return f"# ERROR: Pattern too long ({len(ctx.context)} elements, max 10): {pattern}"
        
        # Collect all substitutions from all marked positions
        all_subs = []
        
        for marked_pos in ctx.marked_indices:
            if marked_pos not in ctx.lookup_refs:
                continue
            
            lookup_name = ctx.lookup_refs[marked_pos]
            substitutions = self.inline_lookup_substitutions(lookup_name)
            
            if not substitutions:
                print(f"WARNING: No substitutions in lookup {lookup_name}", file=sys.stderr)
                continue
            
            # Get the target glyph from the pattern
            target_glyph = ctx.context[marked_pos]
            
            # For each substitution in the lookup
            for source, replacement in substitutions.items():
                # Only include if source matches the pattern element
                if source == target_glyph or target_glyph.startswith('@'):
                    all_subs.append(f"{source} => {replacement}")
        
        if not all_subs:
            return f"# ERROR: No valid substitutions for pattern: {pattern}"
        
        # Format the rule
        if len(all_subs) == 1:
            return f"when {pattern}: {all_subs[0]}"
        else:
            # Multiple substitutions - format nicely
            subs_str = ',\n    '.join(all_subs)
            return f"when {pattern}:\n    {subs_str}"
    
    def generate_contextual_section(self) -> str:
        """Generate the @contextual section of .aar output"""
        if not self.contextual_subs:
            return ""
        
        output = []
        output.append("# " + "-" * 76)
        output.append("# CONTEXTUAL SUBSTITUTIONS (Type 6)")
        output.append("# " + "-" * 76)
        output.append("")
        output.append("@contextual {")
        
        for ctx in self.contextual_subs:
            num_marked = len(ctx.marked_indices)
            
            if num_marked == 0:
                output.append("    # ERROR: No marked positions in pattern")
                continue
            
            # Check for lookupflag issues
            for lookup_name in ctx.lookup_refs.values():
                if lookup_name in self.lookups:
                    # Check if any line has lookupflag
                    for line in self.lookups[lookup_name]:
                        if 'lookupflag' in line.lower():
                            output.append(f"    # NOTE: Lookup {lookup_name} has lookupflag - may need manual adjustment")
                            break
            
            if num_marked == 1:
                # Simple context
                rule = self.generate_simple_context(ctx)
                output.append(f"    {rule}")
            else:
                # When context with multiple substitutions
                rule = self.generate_when_context(ctx)
                # Indent properly
                for line in rule.split('\n'):
                    output.append(f"    {line}")
            
            output.append("")
        
        output.append("}")
        output.append("")
        
        return '\n'.join(output)
    
    def generate_output(self) -> str:
        """Generate unified .aar format output"""
        output = []
        
        output.append("# " + "=" * 76)
        output.append("# Converted from OpenType GSUB format to unified .aar format")
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
        
        # Simple substitutions → @simple section
        if self.single_subs:
            output.append("# " + "-" * 76)
            output.append("# SIMPLE SUBSTITUTIONS (Type 1)")
            output.append("# " + "-" * 76)
            output.append("")
            output.append("@simple {")
            
            for sub in self.single_subs:
                output.append(f"    {sub.source} -> {sub.target}")
            
            output.append("}")
            output.append("")
        
        # Ligatures → @ligature section
        if self.ligatures:
            output.append("# " + "-" * 76)
            output.append("# LIGATURES (Type 4)")
            output.append("# " + "-" * 76)
            output.append("")
            output.append("@ligature {")
            
            for lig in self.ligatures:
                components = ' + '.join(lig.components)
                output.append(f"    {lig.target} := {components}")
            
            output.append("}")
            output.append("")
        
        # Multiple substitutions → @one2many section
        if self.multiple_subs:
            output.append("# " + "-" * 76)
            output.append("# MULTIPLE SUBSTITUTIONS (Type 2)")
            output.append("# " + "-" * 76)
            output.append("")
            output.append("@one2many {")
            
            for mult in self.multiple_subs:
                targets = ' '.join(mult.targets)
                output.append(f"    {mult.source} > {targets}")
            
            output.append("}")
            output.append("")
        
        # Contextual substitutions
        contextual_section = self.generate_contextual_section()
        if contextual_section:
            output.append(contextual_section)
        
        return '\n'.join(output)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 gsubfea2aar.py input.fea [output.aar]")
        print()
        print("Convert OpenType GSUB (substitution) features to .aar format")
        print()
        print("Scope: GSUB only (substitution, ligatures, contextual)")
        print("       GPOS (positioning) is out of scope")
        print()
        print("Examples:")
        print("  python3 gsubfea2aar.py subs.fea")
        print("  python3 gsubfea2aar.py subs.fea converted.aar")
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
    
    converter = GSUBToAAR()
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
    