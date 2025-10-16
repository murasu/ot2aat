#!/usr/bin/env python3
"""
AAR to MIF Converter
====================

Converts OpenType GSUB rules in .aar format (unified rule format) to Apple Advanced
Typography (AAT) .mif format for morx table compilation.

Key Concepts:
-------------
1. AAR Format: A human-readable unified format representing OpenType GSUB rules
   - @simple: One-to-one glyph substitutions
   - @contextual: Context-dependent substitutions (before/after patterns)
   - @ligature: Multiple glyphs combining into one
   - @one2many: One glyph decomposing into multiple
   - @reorder: Glyph reordering

2. MIF Format: Apple's morx table input format with state machines
   - Noncontextual: Simple substitutions (Type table)
   - Contextual: State-based substitutions with mark/advance logic
   - Ligature: Multi-glyph to single-glyph substitutions
   - Rearrangement: Glyph reordering via state machine
   - Insertion: Glyph insertion/decomposition

3. AAT Constraint: Each glyph can only belong to ONE match class
   - Unlike OpenType where glyphs can be in multiple classes
   - Requires partitioning overlapping classes into non-overlapping sets
   - State machines must explicitly handle all class combinations

Author: Created for Thai script OpenType to AAT conversion
Date: 2025
"""

import re
from collections import defaultdict
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field


@dataclass
class GlyphClass:
    """Represents a glyph class definition from AAR format."""
    name: str
    glyphs: List[str]
    
    def __hash__(self):
        return hash(self.name)


@dataclass
class Lookup:
    """Represents a lookup block from AAR format."""
    name: str
    lookup_type: str  # simple, contextual, ligature, one2many, reorder
    feature: str
    rules: List[Dict] = field(default_factory=list)


class AARParser:
    """
    Parser for .aar format files.
    
    The AAR format structure:
    - Class definitions: @class CLASS_NAME = glyph1 glyph2 ...
    - Feature blocks: # ============= Feature: feature_name =============
    - Lookup blocks: # ------------- Lookup: lookup_name -------------
    - Rule blocks: @ruletype { rules }
    """
    
    def __init__(self, aar_content: str):
        self.content = aar_content
        self.classes: Dict[str, GlyphClass] = {}
        self.lookups: List[Lookup] = []
        
    def parse(self):
        """Main parsing entry point."""
        self._parse_classes()
        self._parse_lookups()
        return self.classes, self.lookups
    
    def _parse_classes(self):
        """
        Parse class definitions.
        
        Format: @class CLASS_NAME = glyph1 glyph2 glyph3
        """
        class_pattern = r'@class\s+(\w+)\s*=\s*([^\n]+)'
        
        for match in re.finditer(class_pattern, self.content):
            class_name = match.group(1)
            glyphs_str = match.group(2).strip()
            glyphs = glyphs_str.split()
            
            self.classes[class_name] = GlyphClass(name=class_name, glyphs=glyphs)
    
    def _parse_lookups(self):
        """
        Parse lookup blocks and their rules.
        
        Each lookup contains:
        - A type indicator (@simple, @contextual, etc.)
        - Rules in a specific format depending on type
        """
        # Find all lookup sections
        lookup_pattern = r'# -{10,}\n# Lookup: (\w+)\n# Features?: ([^\n]+)\n# Scripts?: ([^\n]+)\n# -{10,}\n(@\w+)\s*\{([^}]+)\}'
        
        for match in re.finditer(lookup_pattern, self.content, re.MULTILINE | re.DOTALL):
            lookup_name = match.group(1)
            features = match.group(2).strip()
            scripts = match.group(3).strip()
            rule_type = match.group(4).strip('@')
            rules_content = match.group(5)
            
            lookup = Lookup(
                name=lookup_name,
                lookup_type=rule_type,
                feature=features.split()[0]  # Take first feature
            )
            
            # Parse rules based on type
            if rule_type == 'simple':
                lookup.rules = self._parse_simple_rules(rules_content)
            elif rule_type == 'contextual':
                lookup.rules = self._parse_contextual_rules(rules_content)
            elif rule_type == 'ligature':
                lookup.rules = self._parse_ligature_rules(rules_content)
            elif rule_type == 'one2many':
                lookup.rules = self._parse_one2many_rules(rules_content)
            elif rule_type == 'reorder':
                lookup.rules = self._parse_reorder_rules(rules_content)
            
            self.lookups.append(lookup)
    
    def _parse_simple_rules(self, content: str) -> List[Dict]:
        """Parse simple substitution rules: glyph1 -> glyph2"""
        rules = []
        for line in content.strip().split('\n'):
            line = line.strip()
            if '->' in line:
                parts = line.split('->')
                source = parts[0].strip()
                target = parts[1].strip()
                rules.append({'type': 'simple', 'source': source, 'target': target})
        return rules
    
    def _parse_contextual_rules(self, content: str) -> List[Dict]:
        """
        Parse contextual rules.
        
        Formats:
        - before @CLASS: glyph => replacement
        - after @CLASS: glyph => replacement
        - after @CLASS1 @CLASS2: glyph => replacement
        """
        rules = []
        for line in content.strip().split('\n'):
            line = line.strip()
            if '=>' in line:
                # Split on '=>'
                left, right = line.split('=>')
                left = left.strip()
                right = right.strip()
                
                # Parse context (before/after)
                if left.startswith('before'):
                    context_type = 'before'
                    rest = left[6:].strip()
                elif left.startswith('after'):
                    context_type = 'after'
                    rest = left[5:].strip()
                else:
                    continue
                
                # Parse context classes and target glyph
                parts = rest.split(':')
                if len(parts) == 2:
                    context_classes = parts[0].strip().split()
                    target_glyph = parts[1].strip()
                    
                    rules.append({
                        'type': 'contextual',
                        'context_type': context_type,
                        'context_classes': context_classes,
                        'source': target_glyph,
                        'target': right
                    })
        
        return rules
    
    def _parse_ligature_rules(self, content: str) -> List[Dict]:
        """Parse ligature rules: result := component1 + component2"""
        rules = []
        for line in content.strip().split('\n'):
            line = line.strip()
            if ':=' in line:
                parts = line.split(':=')
                result = parts[0].strip()
                components = [c.strip() for c in parts[1].split('+')]
                rules.append({'type': 'ligature', 'result': result, 'components': components})
        return rules
    
    def _parse_one2many_rules(self, content: str) -> List[Dict]:
        """Parse one-to-many decomposition rules: source > target1 target2"""
        rules = []
        for line in content.strip().split('\n'):
            line = line.strip()
            if '>' in line and '=>' not in line:  # Avoid contextual rules
                parts = line.split('>')
                source = parts[0].strip()
                targets = parts[1].strip().split()
                rules.append({'type': 'one2many', 'source': source, 'targets': targets})
        return rules
    
    def _parse_reorder_rules(self, content: str) -> List[Dict]:
        """Parse reorder rules: glyph1 glyph2 => glyph2 glyph1"""
        rules = []
        for line in content.strip().split('\n'):
            line = line.strip()
            if '=>' in line:
                parts = line.split('=>')
                before = parts[0].strip().split()
                after = parts[1].strip().split()
                rules.append({'type': 'reorder', 'before': before, 'after': after})
        return rules


class ClassPartitioner:
    """
    Partitions overlapping glyph classes into non-overlapping sets.
    
    Critical for AAT conversion because AAT requires each glyph to belong
    to exactly ONE match class, unlike OpenType where glyphs can be in
    multiple classes.
    
    Algorithm:
    1. Map each glyph to all classes it belongs to
    2. Create unique "membership signatures" (combinations of classes)
    3. Each signature becomes a separate match class
    4. State machines must explicitly handle all signature combinations
    """
    
    def __init__(self, classes: Dict[str, GlyphClass]):
        self.classes = classes
        self.glyph_memberships: Dict[str, Set[str]] = defaultdict(set)
        self.partitions: Dict[str, List[str]] = {}
        
    def partition(self) -> Dict[str, List[str]]:
        """
        Create non-overlapping partitions.
        
        Returns:
            Dict mapping "signature" (e.g., "CLASS_001+CLASS_003") to list of glyphs
        """
        # Build glyph membership map
        for class_name, glyph_class in self.classes.items():
            for glyph in glyph_class.glyphs:
                self.glyph_memberships[glyph].add(class_name)
        
        # Create partitions based on membership signatures
        for glyph, memberships in self.glyph_memberships.items():
            signature = '+'.join(sorted(memberships))
            if signature not in self.partitions:
                self.partitions[signature] = []
            self.partitions[signature].append(glyph)
        
        return self.partitions
    
    def get_partition_info(self, signature: str) -> Dict[str, any]:
        """Get detailed information about a partition."""
        classes = signature.split('+')
        glyphs = self.partitions.get(signature, [])
        
        return {
            'signature': signature,
            'classes': classes,
            'glyphs': glyphs,
            'count': len(glyphs),
            'is_predecessor': any('PRED_' in c for c in classes),
            'is_target': any('TARGET_' in c for c in classes),
            'is_dual_role': (any('PRED_' in c for c in classes) and 
                           any('TARGET_' in c for c in classes))
        }


class MIFGenerator:
    """
    Generates MIF (morx table input) format from parsed AAR lookups.
    
    MIF Structure:
    - Type: Noncontextual, Contextual, Ligature, Rearrangement, Insertion
    - Name: Human-readable name
    - Namecode: Feature code (8 for contextual features, etc.)
    - Setting/Settingcode: Feature setting
    - Default: yes/no - whether feature is on by default
    - Orientation: HV (horizontal and vertical)
    - Forward: yes/no - processing direction
    - Exclusive: yes/no - whether mutually exclusive with other features
    
    State Machine Components (for Contextual):
    - Match classes: Non-overlapping glyph sets
    - States: Named states in the state machine
    - Transitions: State table defining next state based on current state + input
    - Actions: Mark, Advance, Substitute operations
    """
    
    def __init__(self, classes: Dict[str, GlyphClass], lookups: List[Lookup]):
        self.classes = classes
        self.lookups = lookups
        self.partitioner = ClassPartitioner(classes)
        self.output = []
        
    def generate(self) -> str:
        """Generate complete MIF output."""
        self.output = []
        
        # Generate header comment
        self._write_header()
        
        # Process each lookup
        for lookup in self.lookups:
            if lookup.lookup_type == 'simple':
                self._generate_noncontextual(lookup)
            elif lookup.lookup_type == 'contextual':
                self._generate_contextual(lookup)
            elif lookup.lookup_type == 'ligature':
                self._generate_ligature(lookup)
            elif lookup.lookup_type == 'one2many':
                self._generate_insertion(lookup)
            elif lookup.lookup_type == 'reorder':
                self._generate_rearrangement(lookup)
        
        return '\n'.join(self.output)
    
    def _write_header(self):
        """Write file header."""
        self.output.extend([
            '// -------------------------------------------------------------------------------',
            '//',
            '//  MIF file generated from AAR format',
            '//  Generated by aar_to_mif_converter.py',
            '//',
            '// -------------------------------------------------------------------------------',
            ''
        ])
    
    def _write_section_header(self, lookup: Lookup):
        """Write section header for a lookup."""
        self.output.extend([
            '',
            '// -------------------------------------------------------------------------------',
            f'// LOOKUP: {lookup.name}',
            f'// Feature: {lookup.feature}',
            f'// Type: {lookup.lookup_type}',
            '// -------------------------------------------------------------------------------',
            ''
        ])
    
    def _generate_noncontextual(self, lookup: Lookup):
        """
        Generate noncontextual substitution table.
        
        Used for simple one-to-one substitutions like:
        - Stylistic alternates
        - Access all alternates
        - Simple variant selection
        """
        self._write_section_header(lookup)
        
        self.output.extend([
            'Type            Noncontextual',
            f'Name            {lookup.name}',
            'Namecode        8',
            f'Setting         {lookup.name}',
            'Settingcode     1',
            'Default         no',
            'Orientation     HV',
            'Forward         yes',
            'Exclusive       yes',
            ''
        ])
        
        # Write substitution rules
        for rule in lookup.rules:
            if rule['type'] == 'simple':
                self.output.append(f"{rule['source']:<20}{rule['target']}")
        
        self.output.append('')
    
    def _generate_contextual(self, lookup: Lookup):
        """
        Generate contextual substitution state machine.
        
        This is the most complex conversion as it requires:
        1. Partitioning overlapping classes
        2. Building state machine with proper transitions
        3. Handling dual-role glyphs (both predecessors and targets)
        4. Managing mark/advance semantics
        
        State Machine Logic:
        - Each state represents "what we've seen so far"
        - Transitions depend on current state + input match class
        - Actions: Mark (remember position), Advance (move forward), Substitute
        """
        self._write_section_header(lookup)
        
        # Analyze rules to determine what classes we need
        predecessor_classes, target_classes = self._analyze_contextual_rules(lookup.rules)
        
        # Partition classes
        partitions = self._create_contextual_partitions(predecessor_classes, target_classes)
        
        self.output.extend([
            'Type            Contextual',
            f'Name            {lookup.name}',
            'Namecode        8',
            f'Setting         {lookup.name}',
            'Settingcode     1',
            'Default         yes',
            'Orientation     HV',
            'Forward         yes',
            'Exclusive       no',
            ''
        ])
        
        # Write match classes
        for i, (sig, glyphs) in enumerate(partitions.items(), 1):
            self._write_match_class(i, glyphs, f"// {sig}")
        
        # Generate state machine
        self._generate_state_machine(lookup.rules, partitions)
        
        self.output.append('')
    
    def _analyze_contextual_rules(self, rules: List[Dict]) -> Tuple[Set[str], Set[str]]:
        """Analyze rules to determine predecessor and target classes."""
        predecessors = set()
        targets = set()
        
        for rule in rules:
            if rule['type'] == 'contextual':
                # Context classes are predecessors
                for ctx_class in rule['context_classes']:
                    if ctx_class.startswith('@'):
                        predecessors.add(ctx_class)
                
                # Source glyph might be in target classes
                targets.add(rule['source'])
        
        return predecessors, targets
    
    def _create_contextual_partitions(self, predecessors: Set[str], 
                                     targets: Set[str]) -> Dict[str, List[str]]:
        """
        Create non-overlapping partitions for contextual rules.
        
        This handles the AAT constraint that each glyph belongs to one class.
        """
        # For now, return a simplified partition
        # In a full implementation, this would use ClassPartitioner
        partitions = {}
        
        # Expand class references to actual glyphs
        for pred in predecessors:
            class_name = pred.lstrip('@')
            if class_name in self.classes:
                sig = f"PRED_{class_name}"
                partitions[sig] = self.classes[class_name].glyphs
        
        return partitions
    
    def _write_match_class(self, num: int, glyphs: List[str], comment: str = ''):
        """Write a match class definition."""
        # Split long lines with continuation
        line = f"Match{num}          {' '.join(glyphs[:10])}"
        if len(glyphs) > 10:
            self.output.append(line)
            remaining = glyphs[10:]
            while remaining:
                chunk = remaining[:10]
                self.output.append(f"+               {' '.join(chunk)}")
                remaining = remaining[10:]
        else:
            self.output.append(line)
        
        if comment:
            self.output[-1] += f"  {comment}"
        self.output.append('')
    
    def _generate_state_machine(self, rules: List[Dict], partitions: Dict[str, List[str]]):
        """
        Generate the state transition table.
        
        State Table Format:
        - Header row: EOT OOB DEL EOL Match1 Match2 Match3 ...
        - Each state row: state_name followed by next state for each column
        - Action table: GoTo, Mark?, Advance?, SubstMark, SubstCurrent
        
        State Types:
        - StartText: Initial state
        - SawMatch*: Tracking which match class was seen
        """
        num_matches = len(partitions)
        
        # Write state table header
        header = "                EOT OOB DEL EOL"
        for i in range(1, num_matches + 1):
            header += f" Match{i}"
        self.output.append(header)
        
        # Write state rows (simplified for demonstration)
        states = ['StartText', 'SawMatch1']
        
        for state in states:
            if state == 'StartText':
                row = f"{state:<16}1   1   1   1  "
                row += " ".join(['2' if i == 1 else '1' for i in range(1, num_matches + 1)])
            else:
                row = f"{state:<16}1   1   3   1  "
                row += " ".join(['2' if i == 1 else '4' if i == num_matches else '1' 
                               for i in range(1, num_matches + 1)])
            self.output.append(row)
        
        self.output.extend(['', '    GoTo            Mark?   Advance?    SubstMark   SubstCurrent'])
        self.output.append('1   StartText       no      yes         none        none')
        self.output.append('2   SawMatch1       yes     yes         none        none')
        self.output.append('3   SawMatch1       no      yes         none        none')
        self.output.append('4   StartText       no      yes         none        doSubst')
        self.output.append('')
        
        # Write substitution rules
        self.output.append('doSubst')
        for rule in rules:
            if rule['type'] == 'contextual':
                self.output.append(f"    {rule['source']:<16}{rule['target']}")
    
    def _generate_ligature(self, lookup: Lookup):
        """
        Generate ligature table.
        
        Ligature formation in AAT:
        - Type: Ligature
        - Rules: result := component1 component2 ...
        """
        self._write_section_header(lookup)
        
        self.output.extend([
            'Type            Ligature',
            f'Name            {lookup.name}',
            'Namecode        8',
            f'Setting         {lookup.name}',
            'Settingcode     1',
            'Default         yes',
            'Orientation     HV',
            'Forward         yes',
            'Exclusive       no',
            ''
        ])
        
        for rule in lookup.rules:
            if rule['type'] == 'ligature':
                components = ' '.join(rule['components'])
                self.output.append(f"{rule['result']:<20}{components}")
        
        self.output.append('')
    
    def _generate_insertion(self, lookup: Lookup):
        """
        Generate insertion table for one-to-many decomposition.
        
        Insertion in AAT:
        - Used to decompose one glyph into multiple
        - Specifies whether to insert before or after
        - Can mark glyphs as kashida-like (for justification)
        """
        self._write_section_header(lookup)
        
        self.output.extend([
            'Type            Insertion',
            f'Name            {lookup.name}',
            'Namecode        8',
            f'Setting         {lookup.name}',
            'Settingcode     1',
            'Default         yes',
            'Orientation     HV',
            'Forward         yes',
            'Exclusive       no',
            ''
        ])
        
        # Create match class for source glyphs
        sources = [rule['source'] for rule in lookup.rules if rule['type'] == 'one2many']
        self.output.append(f"Match1          {' '.join(sources)}")
        self.output.append('')
        
        # State machine for insertion
        self.output.extend([
            '                EOT OOB DEL EOL Match1',
            'StartText       1   1   1   1   2',
            'StartLine       1   1   1   1   2',
            '',
            '    GoTo            Mark?   Advance?    InsertMark  InsertCurrent',
            '1   StartText       no      yes         none        none',
            '2   StartText       no      yes         none        doInsert',
            '',
            'doInsert',
            '    IsKashidaLike   yes',
            '    InsertBefore    no',
            '    Glyphs          ' + ' '.join(lookup.rules[0]['targets']) if lookup.rules else '',
            ''
        ])
    
    def _generate_rearrangement(self, lookup: Lookup):
        """
        Generate rearrangement table.
        
        Rearrangement in AAT:
        - Used to reorder glyphs
        - Marks first and last glyphs of sequence to swap
        - Actions: xD->Dx (swap order), Dx->xD (reverse swap), etc.
        """
        self._write_section_header(lookup)
        
        self.output.extend([
            'Type            Rearrangement',
            f'Name            {lookup.name}',
            'Namecode        8',
            f'Setting         {lookup.name}',
            'Settingcode     1',
            'Default         yes',
            'Orientation     HV',
            'Forward         yes',
            'Exclusive       no',
            ''
        ])
        
        # Extract glyphs from reorder rules
        if lookup.rules:
            rule = lookup.rules[0]
            match1 = rule['before'][0] if rule['before'] else ''
            match2 = rule['before'][1] if len(rule['before']) > 1 else ''
            
            self.output.extend([
                f"Match1          {match1}",
                f"Match2          {match2}",
                '',
                '                EOT OOB DEL EOL Match1  Match2',
                'StartText       1   1   1   1   2       1',
                'StartLine       1   1   1   1   2       1',
                'SawMatch1       1   1   3   1   2       4',
                '',
                '    GoTo        MarkFirst?  MarkLast?   Advance?    DoThis',
                '1   StartText   no          no          yes         none',
                '2   SawMatch1   yes         no          yes         none',
                '3   SawMatch1   no          no          yes         none',
                '4   StartText   no          yes         yes         xD->Dx',
                ''
            ])


def convert_aar_to_mif(aar_file: str, output_file: str):
    """
    Main conversion function.
    
    Args:
        aar_file: Path to input .aar file
        output_file: Path to output .mif file
    """
    # Read AAR file
    with open(aar_file, 'r', encoding='utf-8') as f:
        aar_content = f.read()
    
    # Parse AAR
    parser = AARParser(aar_content)
    classes, lookups = parser.parse()
    
    print(f"Parsed {len(classes)} classes and {len(lookups)} lookups")
    
    # Generate MIF
    generator = MIFGenerator(classes, lookups)
    mif_content = generator.generate()
    
    # Write MIF file
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(mif_content)
    
    print(f"Generated MIF file: {output_file}")


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) != 3:
        print("Usage: python aar_to_mif_converter.py <input.aar> <output.mif>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        convert_aar_to_mif(input_file, output_file)
        print("Conversion completed successfully!")
    except Exception as e:
        print(f"Error during conversion: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
