#!/usr/bin/env python3
"""
Convert OpenType GSUB (substitution) features to ot2aat .aar format

SCOPE: GSUB features only (substitution, ligatures, contextual)
       GPOS (positioning) features are out of scope

INPUT: OpenType feature file (.fea) converted from TTX
       Use: ttx -t GSUB font.otf to extract, then convert to FEA

Supports:
- Type 1: Single substitution → @simple
- Type 2: Multiple substitution → @one2many
- Type 4: Ligature substitution → @ligature
- Type 6: Contextual chaining substitution → @contextual

Features:
- Preserves feature order from original FEA
- Filters by script (--script option)
- Automatically inlines prefix lookups into contextual rules
- Uses "when" context for multi-element patterns
- Generates named classes for inline class patterns
- Skips empty lookups
"""

import re
import sys
import argparse
from typing import Dict, List, Tuple, Optional

# MARK: - Data Structures

class LookupInfo:
    """Metadata about a lookup"""
    def __init__(self, name: str):
        self.name = name
        self.scripts = []
        self.features = []
        self.is_prefix = False


class SingleSubstitution:
    def __init__(self, source: str, target: str):
        self.source = source
        self.target = target


class LigatureSubstitution:
    def __init__(self, target: str, components: List[str]):
        self.target = target
        self.components = components


class MultipleSubstitution:
    def __init__(self, source: str, targets: List[str]):
        self.source = source
        self.targets = targets


class ContextualSubstitution:
    def __init__(self, context: List[str], marked_indices: List[int],
                 substitutions: Dict[int, str], lookup_refs: Dict[int, str]):
        self.context = context
        self.marked_indices = marked_indices
        self.substitutions = substitutions
        self.lookup_refs = lookup_refs


class RearrangementRule:
    def __init__(self, input_sequence: List[str], output_sequence: List[str]):
        self.input_sequence = input_sequence
        self.output_sequence = output_sequence


class RearrangementPattern:
    """Stores unresolved rearrangement pattern with lookup references"""
    def __init__(self, glyphs: List[str], lookup_refs: List[str]):
        self.glyphs = glyphs
        self.lookup_refs = lookup_refs


class ParsedLookup:
    def __init__(self, info: LookupInfo):
        self.info = info
        self.single_subs: List[SingleSubstitution] = []
        self.ligatures: List[LigatureSubstitution] = []
        self.multiple_subs: List[MultipleSubstitution] = []
        self.contextual_subs: List[ContextualSubstitution] = []
        self.rearrangement_rules: List[RearrangementRule] = []
        self.rearrangement_patterns: List[RearrangementPattern] = []
        self.local_classes: Dict[str, List[str]] = {}
        self.raw_lines: List[str] = []
    
    def is_empty(self) -> bool:
        """Check if lookup has any content"""
        return not (self.single_subs or self.ligatures or
                   self.multiple_subs or self.contextual_subs or
                   self.rearrangement_rules or self.rearrangement_patterns)


# MARK: - Main Converter Class

class GSUBToAAR:
    def __init__(self, script_filter: Optional[List[str]] = None):
        self.script_filter = script_filter
        self.all_lookups: Dict[str, ParsedLookup] = {}
        self.feature_order: List[Tuple[str, str, str]] = []
        self.global_classes: Dict[str, List[str]] = {}
        self.inline_classes: Dict[str, List[str]] = {}  # Generated classes
        self.class_counter = 0
    
    def parse_class_definition(self, line: str, class_dict: Dict[str, List[str]]) -> bool:
        pattern = r'@(\w+)\s*=\s*\[([^\]]+)\];'
        match = re.match(pattern, line.strip())
        if match:
            class_name = match.group(1)
            glyphs = [g.strip() for g in match.group(2).split() if g.strip()]
            if glyphs:
                class_dict[class_name] = glyphs
            return True
        return False
    
    def expand_class_reference(self, element: str) -> List[str]:
        if element.startswith('@'):
            class_name = element[1:]
            if class_name in self.global_classes:
                return self.global_classes[class_name]
            for lookup in self.all_lookups.values():
                if class_name in lookup.local_classes:
                    return lookup.local_classes[class_name]
            print(f"Warning: Undefined class @{class_name}", file=sys.stderr)
            return []
        return [element]
    
    def register_inline_class(self, glyphs: List[str]) -> str:
        """Register an inline class and return a unique class name"""
        # Check if this exact class already exists
        glyphs_tuple = tuple(glyphs)
        for class_name, existing_glyphs in self.inline_classes.items():
            if tuple(existing_glyphs) == glyphs_tuple:
                return f"@{class_name}"
        
        # Generate new class name
        self.class_counter += 1
        class_name = f"CLASS_{self.class_counter:03d}"
        self.inline_classes[class_name] = glyphs
        return f"@{class_name}"
    
    def process_pattern_element(self, element: str) -> str:
        """
        Process a pattern element: if it's an inline class, register it and return class reference.
        Otherwise return the element as-is.
        """
        if element.startswith('[') and element.endswith(']'):
            # Extract glyphs from inline class
            glyphs = [g.strip() for g in element[1:-1].split() if g.strip()]
            if glyphs:
                return self.register_inline_class(glyphs)
        return element
    
    def detect_substitution_type(self, line: str) -> Optional[str]:
        line = line.strip()
        if not line.startswith('sub '):
            return None
        # Check for contextual with "by lookup" syntax
        if 'by lookup' in line:
            return 'contextual'
        # If it has ' and lookup_ (inline lookup references), it's rearrangement
        if "'" in line and 'lookup_' in line and 'by lookup' not in line:
            return None  # Let parse_inline_lookup_contextual handle it
        # Regular substitution patterns
        parts = line.split(' by ')
        if len(parts) != 2:
            return None
        left = parts[0].replace('sub ', '').strip().split()
        right = parts[1].rstrip(';').strip().split()
        if len(left) == 1 and len(right) > 1:
            return 'multiple'
        if len(left) > 1 and len(right) == 1:
            return 'ligature'
        if len(left) == 1 and len(right) == 1:
            return 'single'
        return None
    
    def parse_single_substitution(self, line: str, lookup: ParsedLookup) -> bool:
        pattern = r'sub\s+(\S+)\s+by\s+(\S+);'
        match = re.match(pattern, line.strip())
        if match:
            lookup.single_subs.append(SingleSubstitution(match.group(1), match.group(2)))
            return True
        return False
    
    def parse_ligature(self, line: str, lookup: ParsedLookup) -> bool:
        pattern = r'sub\s+(.*?)\s+by\s+(\S+);'
        match = re.match(pattern, line.strip())
        if match:
            components = [c.strip() for c in match.group(1).split() if c.strip()]
            if len(components) > 1:
                lookup.ligatures.append(LigatureSubstitution(match.group(2), components))
                return True
        return False
    
    def parse_multiple_substitution(self, line: str, lookup: ParsedLookup) -> bool:
        pattern = r'sub\s+(\S+)\s+by\s+(.*?);'
        match = re.match(pattern, line.strip())
        if match:
            targets = [t.strip() for t in match.group(2).split() if t.strip()]
            if len(targets) > 1:
                lookup.multiple_subs.append(MultipleSubstitution(match.group(1), targets))
                return True
        return False
    
    def parse_contextual_substitution(self, line: str, lookup: ParsedLookup) -> bool:
        if 'by lookup' not in line:
            return False
        
        pattern = r'sub\s+(.*?)\s+by\s+(lookup_\d+);'
        match = re.match(pattern, line.strip())
        if not match:
            return False
        
        pattern_part = match.group(1).strip()
        lookup_name = match.group(2).strip()
        
        elements = []
        marked_indices = []
        idx = 0
        i = 0
        
        while i < len(pattern_part):
            while i < len(pattern_part) and pattern_part[i].isspace():
                i += 1
            if i >= len(pattern_part):
                break
            
            if pattern_part[i] == '[':
                end = pattern_part.find(']', i)
                if end == -1:
                    break
                class_content = pattern_part[i+1:end]
                is_marked = (end + 1 < len(pattern_part) and pattern_part[end + 1] == "'")
                elements.append('[' + class_content + ']')
                if is_marked:
                    marked_indices.append(idx)
                    i = end + 2
                else:
                    i = end + 1
                idx += 1
            else:
                start = i
                while i < len(pattern_part) and not pattern_part[i].isspace() and pattern_part[i] not in '[]':
                    i += 1
                token = pattern_part[start:i]
                if token.endswith("'"):
                    elements.append(token[:-1])
                    marked_indices.append(idx)
                else:
                    elements.append(token)
                idx += 1
        
        if not elements or not marked_indices:
            return False
        
        lookup_refs = {marked_idx: lookup_name for marked_idx in marked_indices}
        lookup.contextual_subs.append(
            ContextualSubstitution(elements, marked_indices, {}, lookup_refs)
        )
        return True
    
    def parse_inline_lookup_contextual(self, line: str, lookup: ParsedLookup) -> bool:
        """Parse multi-marked contextual with inline lookup references (rearrangement)"""
        # Pattern: sub glyph1' lookup_X glyph2' lookup_Y;
        if "'" not in line or 'lookup_' not in line:
            return False
        
        # Match pattern with multiple marked positions and inline lookups
        pattern = r'sub\s+(.*?);'
        match = re.match(pattern, line.strip())
        if not match:
            return False
        
        pattern_part = match.group(1).strip()
        
        # Parse tokens: glyph', lookup_X, glyph', lookup_Y
        tokens = pattern_part.split()
        
        glyphs = []
        lookups = []
        
        i = 0
        while i < len(tokens):
            token = tokens[i]
            if token.endswith("'"):
                # Marked glyph
                glyph = token[:-1]
                glyphs.append(glyph)
                
                # Next token should be lookup reference
                if i + 1 < len(tokens) and tokens[i + 1].startswith('lookup_'):
                    lookups.append(tokens[i + 1])
                    i += 2
                else:
                    return False
            else:
                return False
        
        if len(glyphs) < 2 or len(glyphs) != len(lookups):
            return False
        
        # Store the pattern to be resolved later
        lookup.rearrangement_patterns.append(
            RearrangementPattern(glyphs, lookups)
        )
        return True
    
    def parse_lookup_body(self, lines: List[str], start_idx: int, lookup: ParsedLookup) -> int:
        lines_consumed = 0
        while start_idx + lines_consumed < len(lines):
            current_line = lines[start_idx + lines_consumed].strip()
            if current_line.startswith('}'):
                lines_consumed += 1
                break
            if not current_line or current_line.startswith('#'):
                lines_consumed += 1
                continue
            current_line = re.sub(r'#.*$', '', current_line).strip()
            if current_line.startswith('lookupflag'):
                lookup.raw_lines.append(current_line)
                lines_consumed += 1
                continue
            if current_line.startswith('@') and '=' in current_line:
                self.parse_class_definition(current_line, lookup.local_classes)
                lines_consumed += 1
                continue
            if current_line.startswith('sub '):
                sub_type = self.detect_substitution_type(current_line)
                if sub_type == 'single':
                    self.parse_single_substitution(current_line, lookup)
                elif sub_type == 'ligature':
                    self.parse_ligature(current_line, lookup)
                elif sub_type == 'multiple':
                    self.parse_multiple_substitution(current_line, lookup)
                elif sub_type == 'contextual':
                    self.parse_contextual_substitution(current_line, lookup)
                else:
                    # Try parsing as inline lookup contextual (rearrangement)
                    self.parse_inline_lookup_contextual(current_line, lookup)
                lookup.raw_lines.append(current_line)
            lines_consumed += 1
        return lines_consumed
    
    def parse_feature_block(self, lines: List[str], start_idx: int) -> int:
        line = lines[start_idx].strip()
        feature_match = re.match(r'feature\s+(\w+)', line)
        if not feature_match:
            return 0
        
        feature_name = feature_match.group(1)
        lines_consumed = 1
        current_script = None
        
        while start_idx + lines_consumed < len(lines):
            current_line = lines[start_idx + lines_consumed].strip()
            if current_line.startswith('}'):
                lines_consumed += 1
                break
            script_match = re.match(r'script\s+(\w+);', current_line)
            if script_match:
                current_script = script_match.group(1)
                lines_consumed += 1
                continue
            lookup_match = re.match(r'lookup\s+(\S+);', current_line)
            if lookup_match:
                lookup_name = lookup_match.group(1)
                self.feature_order.append((feature_name, current_script or 'DFLT', lookup_name))
            lines_consumed += 1
        return lines_consumed
    
    def parse_file(self, content: str):
        lines = content.split('\n')
        i = 0
        print(f"Parsing {len(lines)} lines...", file=sys.stderr)
        
        while i < len(lines):
            line = lines[i].strip()
            if not line or line.startswith('#'):
                i += 1
                continue
            
            if line.startswith('lookup '):
                lookup_match = re.match(r'lookup\s+(\S+)\s*\{', line)
                if lookup_match:
                    lookup_name = lookup_match.group(1)
                    info = LookupInfo(lookup_name)
                    parsed_lookup = ParsedLookup(info)
                    i += 1
                    consumed = self.parse_lookup_body(lines, i, parsed_lookup)
                    i += consumed
                    self.all_lookups[lookup_name] = parsed_lookup
                    print(f"  Parsed lookup {lookup_name}: single={len(parsed_lookup.single_subs)}, lig={len(parsed_lookup.ligatures)}, mult={len(parsed_lookup.multiple_subs)}, ctx={len(parsed_lookup.contextual_subs)}, reorder_pat={len(parsed_lookup.rearrangement_patterns)}", file=sys.stderr)
                    continue
            
            if line.startswith('@') and '=' in line:
                self.parse_class_definition(line, self.global_classes)
                i += 1
                continue
            
            if line.startswith('feature '):
                consumed = self.parse_feature_block(lines, i)
                if consumed > 0:
                    i += consumed
                    continue
            i += 1
        
        # Mark prefix lookups and assign scripts
        referenced_lookups = set()
        for feature_name, script, lookup_name in self.feature_order:
            referenced_lookups.add(lookup_name)
            if lookup_name in self.all_lookups:
                lookup = self.all_lookups[lookup_name]
                if feature_name not in lookup.info.features:
                    lookup.info.features.append(feature_name)
                if script and script not in lookup.info.scripts:
                    lookup.info.scripts.append(script)
                print(f"  Assigned feature={feature_name}, script={script} to {lookup_name}", file=sys.stderr)
            else:
                print(f"  WARNING: {lookup_name} referenced in features but not found!", file=sys.stderr)
        
        for lookup_name, lookup in self.all_lookups.items():
            if lookup_name not in referenced_lookups:
                lookup.info.is_prefix = True
        
        print(f"\nParsed content:", file=sys.stderr)
        print(f"  Total lookups: {len(self.all_lookups)}", file=sys.stderr)
        print(f"  Prefix lookups: {sum(1 for l in self.all_lookups.values() if l.info.is_prefix)}", file=sys.stderr)
        print(f"  Feature lookups: {sum(1 for l in self.all_lookups.values() if not l.info.is_prefix)}", file=sys.stderr)
        print(f"  Feature order entries: {len(self.feature_order)}", file=sys.stderr)
        print(f"  Rearrangement patterns found: {sum(len(l.rearrangement_patterns) for l in self.all_lookups.values())}", file=sys.stderr)
    
    def should_include_lookup(self, lookup: ParsedLookup) -> bool:
        if lookup.info.is_prefix:
            print(f"  Skipping {lookup.info.name}: is_prefix", file=sys.stderr)
            return False
        if lookup.is_empty():
            print(f"  Skipping {lookup.info.name}: is_empty", file=sys.stderr)
            return False
        if not self.script_filter:
            return True
        has_script = any(script in lookup.info.scripts for script in self.script_filter)
        if not has_script:
            print(f"  Skipping {lookup.info.name}: no matching script (has: {lookup.info.scripts})", file=sys.stderr)
        return has_script
    
    def inline_lookup_substitutions(self, lookup_name: str) -> Dict[str, str]:
        if lookup_name not in self.all_lookups:
            print(f"ERROR: Lookup '{lookup_name}' not found!", file=sys.stderr)
            return {}
        lookup = self.all_lookups[lookup_name]
        return {sub.source: sub.target for sub in lookup.single_subs}
    
    def resolve_rearrangement_pattern(self, pattern: RearrangementPattern) -> Optional[RearrangementRule]:
        """Resolve a rearrangement pattern by looking up the substitutions"""
        glyphs = pattern.glyphs
        lookups = pattern.lookup_refs
        
        # Get substitutions from each lookup
        substitutions = []
        for i, lookup_name in enumerate(lookups):
            if lookup_name not in self.all_lookups:
                print(f"Warning: Lookup {lookup_name} not found for rearrangement", file=sys.stderr)
                return None
            
            lookup_subs = self.inline_lookup_substitutions(lookup_name)
            glyph = glyphs[i]
            
            if glyph not in lookup_subs:
                print(f"Warning: Glyph {glyph} not found in {lookup_name}", file=sys.stderr)
                return None
            
            substitutions.append(lookup_subs[glyph])
        
        # Check if output differs from input
        if substitutions != glyphs:
            return RearrangementRule(glyphs, substitutions)
        
        return None
    
    def generate_contextual_rules(self, ctx: ContextualSubstitution) -> List[str]:
        """Generate contextual rules - preserving multi-element patterns with named classes"""
        
        # Get marked position
        marked_pos = ctx.marked_indices[0]
        
        # Check for lookup reference
        if marked_pos not in ctx.lookup_refs:
            return [f"# ERROR: No lookup reference for marked position {marked_pos}"]
        
        # Get target element at marked position and expand it to individual glyphs
        target_element = ctx.context[marked_pos]
        if target_element.startswith('[') and target_element.endswith(']'):
            # It's an inline class - extract individual glyphs
            valid_sources = [g.strip() for g in target_element[1:-1].split() if g.strip()]
        else:
            # It's a glyph or class reference - expand it
            valid_sources = self.expand_class_reference(target_element)
        
        if not valid_sources:
            return [f"# ERROR: Cannot expand: {target_element}"]
        
        # Get substitutions from referenced lookup
        lookup_name = ctx.lookup_refs[marked_pos]
        all_subs = self.inline_lookup_substitutions(lookup_name)
        if not all_subs:
            return [f"# ERROR: No substitutions in {lookup_name}"]
        
        # Filter substitutions to only those matching valid sources
        filtered_subs = {src: tgt for src, tgt in all_subs.items() if src in valid_sources}
        if not filtered_subs:
            return [f"# ERROR: No matching substitutions for {target_element}"]
        
        # Generate rules - one per marked glyph substitution
        rules = []
        pattern_length = len(ctx.context)
        
        if pattern_length == 1:
            # Single element pattern - shouldn't happen in contextual
            return [f"# ERROR: Single element context pattern: {' '.join(ctx.context)}"]
        
        # Multi-element pattern - determine context type based on marked position
        if marked_pos == 0:
            # Marked at beginning - use "before" context
            # Pattern: marked_glyph following_context
            # Build the following context (everything after marked position)
            context_parts = []
            for i in range(1, pattern_length):
                context_parts.append(self.process_pattern_element(ctx.context[i]))
            context_str = ' '.join(context_parts)
            
            for source, target in filtered_subs.items():
                rules.append(f"before {context_str}: {source} => {target}")
        
        elif marked_pos == pattern_length - 1:
            # Marked at end - use "after" context
            # Pattern: preceding_context marked_glyph
            # Build the preceding context (everything before marked position)
            context_parts = []
            for i in range(0, marked_pos):
                context_parts.append(self.process_pattern_element(ctx.context[i]))
            context_str = ' '.join(context_parts)
            
            for source, target in filtered_subs.items():
                rules.append(f"after {context_str}: {source} => {target}")
        
        else:
            # Marked in middle - use "between" context
            # Pattern: before_context marked_glyph after_context
            # Build before context
            before_parts = []
            for i in range(0, marked_pos):
                before_parts.append(self.process_pattern_element(ctx.context[i]))
            before_str = ' '.join(before_parts)
            
            # Build after context
            after_parts = []
            for i in range(marked_pos + 1, pattern_length):
                after_parts.append(self.process_pattern_element(ctx.context[i]))
            after_str = ' '.join(after_parts)
            
            for source, target in filtered_subs.items():
                rules.append(f"between {before_str} and {after_str}: {source} => {target}")
        
        return rules
    
    def generate_lookup_output(self, lookup: ParsedLookup) -> List[str]:
        # Resolve rearrangement patterns first
        for pattern in lookup.rearrangement_patterns:
            rule = self.resolve_rearrangement_pattern(pattern)
            if rule:
                lookup.rearrangement_rules.append(rule)
        
        output = []
        output.append("# " + "-" * 76)
        output.append(f"# Lookup: {lookup.info.name}")
        if lookup.info.features:
            output.append(f"# Features: {', '.join(lookup.info.features)}")
        if lookup.info.scripts:
            output.append(f"# Scripts: {', '.join(lookup.info.scripts)}")
        output.append("# " + "-" * 76)
        
        has_lookupflag = any('lookupflag' in line.lower() for line in lookup.raw_lines)
        if has_lookupflag:
            output.append("# NOTE: Original lookup has lookupflag - AAT uses exact sequential matching")
        
        if lookup.single_subs:
            output.append("@simple {")
            for sub in lookup.single_subs:
                output.append(f"    {sub.source} -> {sub.target}")
            output.append("}")
        
        if lookup.ligatures:
            output.append("@ligature {")
            for lig in lookup.ligatures:
                components = ' + '.join(lig.components)
                output.append(f"    {lig.target} := {components}")
            output.append("}")
        
        if lookup.multiple_subs:
            output.append("@one2many {")
            for mult in lookup.multiple_subs:
                targets = ' '.join(mult.targets)
                output.append(f"    {mult.source} > {targets}")
            output.append("}")
        
        if lookup.rearrangement_rules:
            output.append("@reorder {")
            for reorder in lookup.rearrangement_rules:
                input_seq = ' '.join(reorder.input_sequence)
                output_seq = ' '.join(reorder.output_sequence)
                output.append(f"    {input_seq} > {output_seq}")
            output.append("}")
        
        if lookup.contextual_subs:
            output.append("@contextual {")
            
            # Group rules by context
            from collections import OrderedDict
            grouped_rules = OrderedDict()
            
            for ctx in lookup.contextual_subs:
                rules_with_keys = self.generate_contextual_rules(ctx)
                for item in rules_with_keys:
                    if len(item) == 2:
                        context_key, rule = item
                        if context_key not in grouped_rules:
                            grouped_rules[context_key] = []
                        grouped_rules[context_key].append(rule)
                    else:
                        # Error case - just append the rule directly
                        if "error" not in grouped_rules:
                            grouped_rules["error"] = []
                        grouped_rules["error"].append(str(item))
            
            # Output grouped rules with comments
            for context_key, rules in grouped_rules.items():
                if context_key.startswith('error'):
                    # Error case
                    for rule in rules:
                        output.append(f"    {rule}")
                else:
                    # Add descriptive comment for each context group
                    output.append(f"    # Pattern: {context_key}")
                    for rule in rules:
                        output.append(f"    {rule}")
                    output.append("")  # Blank line between groups
            
            output.append("}")
        
        output.append("")
        return output
    
    def preprocess_inline_classes(self):
        """Pre-process all contextual rules to collect inline classes before output generation"""
        print("Pre-processing inline classes...", file=sys.stderr)
        
        for feature_name, script, lookup_name in self.feature_order:
            if lookup_name not in self.all_lookups:
                continue
            
            lookup = self.all_lookups[lookup_name]
            if not self.should_include_lookup(lookup):
                continue
            
            # Process all contextual substitutions to register inline classes
            for ctx in lookup.contextual_subs:
                # Process each element in the context pattern
                for i, elem in enumerate(ctx.context):
                    # Only process non-marked positions (marked positions become individual glyphs)
                    if i not in ctx.marked_indices:
                        self.process_pattern_element(elem)
        
        print(f"  Collected {len(self.inline_classes)} inline classes", file=sys.stderr)
    
    def generate_output(self) -> str:
        # Pre-process to collect all inline classes first
        self.preprocess_inline_classes()
        
        output = []
        output.append("# " + "=" * 76)
        output.append("# Converted from OpenType GSUB to unified .aar format")
        output.append("# Source: FEA converted from TTX (ttx -t GSUB font.otf)")
        if self.script_filter:
            output.append(f"# Script filter: {', '.join(self.script_filter)}")
        output.append("# " + "=" * 76)
        output.append("")
        
        # Output global classes (from FEA file)
        if self.global_classes:
            output.append("# " + "-" * 76)
            output.append("# GLOBAL CLASS DEFINITIONS (from source)")
            output.append("# " + "-" * 76)
            output.append("")
            for class_name in sorted(self.global_classes.keys()):
                glyphs = self.global_classes[class_name]
                output.append(f"@class {class_name} = {' '.join(glyphs)}")
            output.append("")
        
        # Output generated inline classes
        if self.inline_classes:
            output.append("# " + "-" * 76)
            output.append("# GENERATED CLASS DEFINITIONS (from inline classes)")
            output.append("# " + "-" * 76)
            output.append("")
            for class_name in sorted(self.inline_classes.keys()):
                glyphs = self.inline_classes[class_name]
                output.append(f"@class {class_name} = {' '.join(glyphs)}")
            output.append("")
        
        current_feature = None
        processed_lookups = set()
        
        print(f"\nGenerating output...", file=sys.stderr)
        
        for feature_name, script, lookup_name in self.feature_order:
            if lookup_name not in self.all_lookups:
                print(f"  Lookup {lookup_name} not in all_lookups", file=sys.stderr)
                continue
            
            lookup = self.all_lookups[lookup_name]
            if not self.should_include_lookup(lookup) or lookup_name in processed_lookups:
                continue
            
            if feature_name != current_feature:
                current_feature = feature_name
                output.append("")
                output.append("# " + "=" * 76)
                output.append(f"# Feature: {feature_name}")
                if lookup.info.scripts:
                    output.append(f"# Scripts: {', '.join(set(lookup.info.scripts))}")
                output.append("# " + "=" * 76)
                output.append("")
            
            print(f"  Generating output for {lookup_name}", file=sys.stderr)
            lookup_output = self.generate_lookup_output(lookup)
            output.extend(lookup_output)
            processed_lookups.add(lookup_name)
        
        return '\n'.join(output)


def main():
    parser = argparse.ArgumentParser(
        description='Convert OpenType GSUB features to .aar format',
        epilog='Input: FEA file converted from TTX (ttx -t GSUB font.otf)'
    )
    parser.add_argument('input', help='Input .fea file')
    parser.add_argument('output', nargs='?', help='Output .aar file (default: stdout)')
    parser.add_argument('--script', '-s', help='Filter by script(s), comma-separated')
    
    args = parser.parse_args()
    
    script_filter = None
    if args.script:
        script_filter = [s.strip() for s in args.script.split(',')]
        print(f"Filtering by scripts: {', '.join(script_filter)}", file=sys.stderr)
    
    try:
        with open(args.input, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {args.input}")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)
    
    converter = GSUBToAAR(script_filter=script_filter)
    converter.parse_file(content)
    output = converter.generate_output()
    
    if args.output:
        try:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(output)
            print(f"\nSuccessfully converted to: {args.output}", file=sys.stderr)
        except Exception as e:
            print(f"Error writing file: {e}")
            sys.exit(1)
    else:
        print(output)
    
    print(f"\nConversion complete!", file=sys.stderr)

if __name__ == '__main__':
    main()
    
