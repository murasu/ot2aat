#!/usr/bin/env python3
"""
TTX to FEA Converter
Converts TTX font files to Adobe FEA (Feature File) format
"""

import argparse
import xml.etree.ElementTree as ET
from collections import defaultdict
from typing import Dict, List, Set, Optional, Tuple


class TTXtoFEA:
    def __init__(self, ttx_file: str, tables: List[str], scripts: List[str]):
        self.ttx_file = ttx_file
        self.tables = [t.upper() for t in tables]
        self.scripts = [s.lower() for s in scripts] if scripts else []
        self.tree = ET.parse(ttx_file)
        self.root = self.tree.getroot()
        
    def convert(self) -> str:
        """Main conversion method"""
        fea_output = []
        fea_output.append("# Generated from TTX file")
        fea_output.append(f"# Source: {self.ttx_file}\n")
        
        for table in self.tables:
            if table == 'GSUB':
                fea_output.append(self.convert_gsub())
            elif table == 'GPOS':
                fea_output.append(self.convert_gpos_placeholder())
            elif table == 'GDEF':
                fea_output.append(self.convert_gdef_placeholder())
            elif table == 'JSTF':
                fea_output.append(self.convert_jstf_placeholder())
            else:
                fea_output.append(f"# Table {table} not supported yet\n")
        
        return "\n".join(fea_output)
    
    def convert_gsub(self) -> str:
        """Convert GSUB table to FEA format"""
        gsub = self.root.find('.//GSUB')
        if gsub is None:
            return "# GSUB table not found\n"
        
        output = []
        output.append("# ========================================")
        output.append("# GSUB (Glyph Substitution) Table")
        output.append("# ========================================\n")
        
        # Parse GSUB structure
        script_list = gsub.find('ScriptList')
        feature_list = gsub.find('FeatureList')
        lookup_list = gsub.find('LookupList')
        
        if not all([script_list, feature_list, lookup_list]):
            return "# GSUB table incomplete\n"
        
        # Extract data
        scripts = self.parse_script_list(script_list)
        features = self.parse_feature_list(feature_list)
        lookups = self.parse_lookup_list(lookup_list)
        
        # Filter by requested scripts
        if self.scripts:
            scripts = {k: v for k, v in scripts.items() if k.lower() in self.scripts}
        
        # Generate lookup definitions
        output.append("# ----------------------------------------")
        output.append("# Lookup Definitions")
        output.append("# ----------------------------------------\n")
        
        for lookup_idx, lookup_data in sorted(lookups.items()):
            output.append(self.format_lookup(lookup_idx, lookup_data))
        
        # Generate feature definitions with script/language assignments
        output.append("\n# ----------------------------------------")
        output.append("# Feature Definitions")
        output.append("# ----------------------------------------\n")
        
        output.append(self.format_features(scripts, features, lookups))
        
        return "\n".join(output)
    
    def parse_script_list(self, script_list) -> Dict:
        """Parse ScriptList to map scripts -> languages -> features"""
        scripts = {}
        
        for script_record in script_list.findall('ScriptRecord'):
            script_tag = script_record.find('ScriptTag').get('value')
            script = script_record.find('Script')
            
            script_data = {'default': [], 'languages': {}}
            
            # Parse default language system
            default_lang = script.find('DefaultLangSys')
            if default_lang is not None:
                feature_indices = [int(fi.get('value'))
                                 for fi in default_lang.findall('FeatureIndex')]
                script_data['default'] = feature_indices
            
            # Parse specific language systems
            for lang_record in script.findall('LangSysRecord'):
                lang_tag = lang_record.find('LangSysTag').get('value')
                lang_sys = lang_record.find('LangSys')
                feature_indices = [int(fi.get('value'))
                                 for fi in lang_sys.findall('FeatureIndex')]
                script_data['languages'][lang_tag] = feature_indices
            
            scripts[script_tag] = script_data
        
        return scripts
    
    def parse_feature_list(self, feature_list) -> Dict:
        """Parse FeatureList to map feature indices to tags and lookups"""
        features = {}
        
        for idx, feature_record in enumerate(feature_list.findall('FeatureRecord')):
            feature_tag = feature_record.find('FeatureTag').get('value')
            feature = feature_record.find('Feature')
            
            lookup_indices = [int(li.get('value'))
                            for li in feature.findall('LookupListIndex')]
            
            # Check for feature parameters
            params = feature.find('FeatureParamsStylisticSet')
            ui_name_id = None
            if params is not None:
                ui_name_id = params.find('UINameID')
                if ui_name_id is not None:
                    ui_name_id = ui_name_id.get('value')
            
            features[idx] = {
                'tag': feature_tag,
                'lookups': lookup_indices,
                'ui_name_id': ui_name_id
            }
        
        return features
    
    def parse_lookup_list(self, lookup_list) -> Dict:
        """Parse LookupList and convert to FEA-ready format"""
        lookups = {}
        
        for lookup in lookup_list.findall('Lookup'):
            idx = int(lookup.get('index'))
            lookup_type = int(lookup.find('LookupType').get('value'))
            lookup_flag = int(lookup.find('LookupFlag').get('value'))
            
            # Get mark filtering set if present
            mark_filter = lookup.find('MarkFilteringSet')
            mark_filter_set = int(mark_filter.get('value')) if mark_filter is not None else None
            
            # Parse substitution rules
            rules = self.parse_lookup_subtables(lookup, lookup_type)
            
            lookups[idx] = {
                'type': lookup_type,
                'flag': lookup_flag,
                'mark_filter_set': mark_filter_set,
                'rules': rules
            }
        
        return lookups
    
    def parse_lookup_subtables(self, lookup, lookup_type: int) -> List:
        """Parse subtables based on lookup type"""
        rules = []
        
        # Check if this lookup uses ExtensionSubst (Type 7)
        ext_substs = lookup.findall('.//ExtensionSubst')
        
        if ext_substs:
            # Process extension lookups
            for ext_subst in ext_substs:
                actual_type = int(ext_subst.find('ExtensionLookupType').get('value'))
                # Find the actual substitution element (child with Format attribute)
                for child in ext_subst:
                    if child.tag != 'ExtensionLookupType' and child.get('Format'):
                        rules.append(self.parse_substitution(child, actual_type))
                        break
        else:
            # Handle non-extension lookups (direct children of Lookup)
            for subst_type in ['SingleSubst', 'MultipleSubst', 'AlternateSubst',
                              'LigatureSubst', 'ContextSubst', 'ChainContextSubst']:
                # Only get direct children, not descendants
                for subst in lookup.findall(f'./{subst_type}'):
                    rules.append(self.parse_substitution(subst, lookup_type))
        
        return rules
    
    def parse_substitution(self, subst, subst_type: int) -> Dict:
        """Parse individual substitution rule"""
        tag = subst.tag
        
        if tag == 'SingleSubst':
            return self.parse_single_subst(subst)
        elif tag == 'MultipleSubst':
            return self.parse_multiple_subst(subst)
        elif tag == 'AlternateSubst':
            return self.parse_alternate_subst(subst)
        elif tag == 'LigatureSubst':
            return self.parse_ligature_subst(subst)
        elif tag == 'ContextSubst':
            return self.parse_context_subst(subst)
        elif tag == 'ChainContextSubst':
            return self.parse_chain_context_subst(subst)
        
        return {'type': 'unknown', 'data': tag}
    
    def parse_single_subst(self, subst) -> Dict:
        """Parse single substitution (one-to-one)"""
        substitutions = []
        for sub in subst.findall('Substitution'):
            in_glyph = sub.get('in')
            out_glyph = sub.get('out')
            substitutions.append((in_glyph, out_glyph))
        return {'type': 'single', 'substitutions': substitutions}
    
    def parse_multiple_subst(self, subst) -> Dict:
        """Parse multiple substitution (one-to-many)"""
        substitutions = []
        for sub in subst.findall('Substitution'):
            in_glyph = sub.get('in')
            out_glyphs = sub.get('out').split(',')
            substitutions.append((in_glyph, out_glyphs))
        return {'type': 'multiple', 'substitutions': substitutions}
    
    def parse_alternate_subst(self, subst) -> Dict:
        """Parse alternate substitution"""
        alternates = {}
        for alt_set in subst.findall('AlternateSet'):
            glyph = alt_set.get('glyph')
            alts = [alt.get('glyph') for alt in alt_set.findall('Alternate')]
            alternates[glyph] = alts
        return {'type': 'alternate', 'alternates': alternates}
    
    def parse_ligature_subst(self, subst) -> Dict:
        """Parse ligature substitution"""
        ligatures = []
        for lig_set in subst.findall('LigatureSet'):
            first_glyph = lig_set.get('glyph')
            for lig in lig_set.findall('Ligature'):
                components = lig.get('components')
                out_glyph = lig.get('glyph')
                sequence = [first_glyph] + (components.split(',') if components else [])
                ligatures.append((sequence, out_glyph))
        return {'type': 'ligature', 'ligatures': ligatures}
    
    def parse_context_subst(self, subst) -> Dict:
        """Parse contextual substitution"""
        fmt = subst.get('Format')
        rules = []
        
        if fmt == '1':
            # Format 1: Simple context - rules grouped by first glyph
            coverage = self.parse_coverage(subst.find('Coverage'))
            
            for subrule_set_idx, subrule_set in enumerate(subst.findall('SubRuleSet')):
                first_glyph = coverage[subrule_set_idx]
                
                for subrule in subrule_set.findall('SubRule'):
                    # Build input sequence (first glyph + additional input glyphs)
                    input_glyphs = [first_glyph]
                    for input_elem in subrule.findall('Input'):
                        input_glyphs.append(input_elem.get('value'))
                    
                    # Get lookup applications
                    lookups = []
                    for record in subrule.findall('SubstLookupRecord'):
                        seq_idx = int(record.find('SequenceIndex').get('value'))
                        lookup_idx = int(record.find('LookupListIndex').get('value'))
                        lookups.append((seq_idx, lookup_idx))
                    
                    rules.append({
                        'input': input_glyphs,
                        'lookups': lookups
                    })
        
        elif fmt == '2':
            # Format 2: Class-based context
            # TODO: Implement if needed
            return {'type': 'context', 'format': fmt, 'data': 'TODO: Class-based context'}
        
        elif fmt == '3':
            # Format 3: Coverage-based context
            # TODO: Implement if needed
            return {'type': 'context', 'format': fmt, 'data': 'TODO: Coverage-based context'}
        
        return {'type': 'context', 'format': fmt, 'rules': rules}
    
    def parse_chain_context_subst(self, subst) -> Dict:
        """Parse chaining contextual substitution"""
        rules = []
        fmt = subst.get('Format')
        
        if fmt == '3':
            # Format 3: Coverage-based
            backtrack = [self.parse_coverage(cov)
                        for cov in subst.findall('BacktrackCoverage')]
            input_cov = [self.parse_coverage(cov)
                        for cov in subst.findall('InputCoverage')]
            lookahead = [self.parse_coverage(cov)
                        for cov in subst.findall('LookAheadCoverage')]
            
            lookups = []
            for record in subst.findall('SubstLookupRecord'):
                seq_idx = int(record.find('SequenceIndex').get('value'))
                lookup_idx = int(record.find('LookupListIndex').get('value'))
                lookups.append((seq_idx, lookup_idx))
            
            rules.append({
                'backtrack': backtrack,
                'input': input_cov,
                'lookahead': lookahead,
                'lookups': lookups
            })
        
        return {'type': 'chain_context', 'format': fmt, 'rules': rules}
    
    def parse_coverage(self, coverage) -> List[str]:
        """Parse coverage table to list of glyphs"""
        return [g.get('value') for g in coverage.findall('Glyph')]
    
    def format_lookup(self, idx: int, lookup_data: Dict) -> str:
        """Format a lookup as FEA code"""
        output = []
        output.append(f"lookup lookup_{idx} {{")
        
        # Add lookup flags
        if lookup_data['flag'] != 0:
            flag_str = self.format_lookup_flag(lookup_data['flag'],
                                               lookup_data['mark_filter_set'])
            output.append(f"  {flag_str}")
        
        # Add rules
        for rule in lookup_data['rules']:
            rule_str = self.format_rule(rule, indent="  ")
            if rule_str:
                output.append(rule_str)
        
        output.append(f"}} lookup_{idx};\n")
        return "\n".join(output)
    
    def format_lookup_flag(self, flag: int, mark_filter_set: Optional[int]) -> str:
        """Format lookup flags"""
        flags = []
        if flag & 0x0001:
            flags.append("RightToLeft")
        if flag & 0x0002:
            flags.append("IgnoreBaseGlyphs")
        if flag & 0x0004:
            flags.append("IgnoreLigatures")
        if flag & 0x0008:
            flags.append("IgnoreMarks")
        if flag & 0x0010 and mark_filter_set is not None:
            flags.append(f"MarkAttachmentType @MarkClass{mark_filter_set}")
        
        if flags:
            return "lookupflag " + " ".join(flags) + ";"
        return ""
    
    def format_rule(self, rule: Dict, indent: str = "") -> str:
        """Format a substitution rule as FEA"""
        rule_type = rule['type']
        
        if rule_type == 'single':
            lines = []
            for in_g, out_g in rule['substitutions']:
                lines.append(f"{indent}sub {in_g} by {out_g};")
            return "\n".join(lines)
        
        elif rule_type == 'multiple':
            lines = []
            for in_g, out_glyphs in rule['substitutions']:
                out_str = " ".join(out_glyphs)
                lines.append(f"{indent}sub {in_g} by {out_str};")
            return "\n".join(lines)
        
        elif rule_type == 'alternate':
            lines = []
            for glyph, alts in rule['alternates'].items():
                alt_str = " ".join(alts)
                lines.append(f"{indent}sub {glyph} from [{alt_str}];")
            return "\n".join(lines)
        
        elif rule_type == 'ligature':
            lines = []
            for sequence, out_glyph in rule['ligatures']:
                seq_str = " ".join(sequence)
                lines.append(f"{indent}sub {seq_str} by {out_glyph};")
            return "\n".join(lines)
        
        elif rule_type == 'chain_context':
            return self.format_chain_context(rule, indent)
        
        elif rule_type == 'context':
            return self.format_context(rule, indent)
        
        return f"{indent}# Unknown rule type: {rule_type}"
    
    def format_chain_context(self, rule: Dict, indent: str) -> str:
        """Format chaining contextual substitution"""
        lines = []
        for r in rule['rules']:
            parts = []
            
            # Backtrack context
            if r['backtrack']:
                backtrack_classes = []
                for glyphs in reversed(r['backtrack']):
                    if len(glyphs) == 1:
                        backtrack_classes.append(glyphs[0])
                    else:
                        backtrack_classes.append(f"[{' '.join(glyphs)}]")
                parts.extend(backtrack_classes)
            
            # Input sequence (mark positions that get substituted)
            input_parts = []
            for i, glyphs in enumerate(r['input']):
                # Check if this position has a lookup applied
                has_lookup = any(seq_idx == i for seq_idx, _ in r['lookups'])
                if len(glyphs) == 1:
                    glyph_str = glyphs[0]
                else:
                    glyph_str = f"[{' '.join(glyphs)}]"
                
                if has_lookup:
                    glyph_str += "'"
                input_parts.append(glyph_str)
            parts.extend(input_parts)
            
            # Lookahead context
            if r['lookahead']:
                lookahead_classes = []
                for glyphs in r['lookahead']:
                    if len(glyphs) == 1:
                        lookahead_classes.append(glyphs[0])
                    else:
                        lookahead_classes.append(f"[{' '.join(glyphs)}]")
                parts.extend(lookahead_classes)
            
            # Add lookup references
            lookup_refs = []
            for seq_idx, lookup_idx in r['lookups']:
                lookup_refs.append(f"lookup_{lookup_idx}")
            
            context_str = " ".join(parts)
            lookup_str = " ".join(lookup_refs)
            lines.append(f"{indent}sub {context_str} by {lookup_str};")
        
        return "\n".join(lines)
    
    def format_context(self, rule: Dict, indent: str) -> str:
        """Format contextual substitution (non-chaining)"""
        fmt = rule.get('format')
        
        if fmt == '1' and 'rules' in rule:
            lines = []
            for r in rule['rules']:
                # Build the sequence with marked positions
                parts = []
                for i, glyph in enumerate(r['input']):
                    # Check if this position has a lookup applied
                    has_lookup = any(seq_idx == i for seq_idx, _ in r['lookups'])
                    glyph_str = glyph
                    if has_lookup:
                        glyph_str += "'"
                    parts.append(glyph_str)
                
                # Add lookup references
                lookup_refs = []
                for seq_idx, lookup_idx in r['lookups']:
                    lookup_refs.append(f"lookup_{lookup_idx}")
                
                context_str = " ".join(parts)
                lookup_str = " ".join(lookup_refs)
                lines.append(f"{indent}sub {context_str} by {lookup_str};")
            
            return "\n".join(lines)
        else:
            return f"{indent}# TODO: Contextual substitution format {fmt}"
    
    def format_features(self, scripts: Dict, features: Dict, lookups: Dict) -> str:
        """Format feature definitions with script/language assignments"""
        output = []
        
        # Build mapping: feature_tag -> script -> lang -> feature_index
        feature_map = defaultdict(lambda: defaultdict(dict))
        
        for script_tag, script_data in scripts.items():
            # Default language
            for feat_idx in script_data['default']:
                feat_tag = features[feat_idx]['tag']
                if 'dflt' not in feature_map[feat_tag][script_tag]:
                    feature_map[feat_tag][script_tag]['dflt'] = feat_idx
            
            # Specific languages
            for lang_tag, feat_indices in script_data['languages'].items():
                for feat_idx in feat_indices:
                    feat_tag = features[feat_idx]['tag']
                    if lang_tag not in feature_map[feat_tag][script_tag]:
                        feature_map[feat_tag][script_tag][lang_tag] = feat_idx
        
        # Generate feature blocks
        for feat_tag in sorted(feature_map.keys()):
            output.append(f"\nfeature {feat_tag} {{")
            
            # Add UI name comment if present in any variant
            for feat_data in features.values():
                if feat_data['tag'] == feat_tag and feat_data['ui_name_id']:
                    output.append(f"  # UINameID: {feat_data['ui_name_id']}")
                    break
            
            # Process each script
            script_map = feature_map[feat_tag]
            for script_tag in sorted(script_map.keys()):
                lang_map = script_map[script_tag]
                
                # Check if all languages use the same feature index
                feat_indices = set(lang_map.values())
                
                if len(feat_indices) == 1:
                    # All languages use same feature definition
                    feat_idx = list(feat_indices)[0]
                    output.append(f"  script {script_tag};")
                    
                    # Add lookups once for this script
                    if features[feat_idx]['lookups']:
                        output.append("")
                        # Deduplicate lookups while preserving order
                        seen = set()
                        for lookup_idx in features[feat_idx]['lookups']:
                            if lookup_idx not in seen:
                                output.append(f"  lookup lookup_{lookup_idx};")
                                seen.add(lookup_idx)
                else:
                    # Different languages have different feature definitions
                    output.append(f"  script {script_tag};")
                    
                    # Handle default first
                    if 'dflt' in lang_map:
                        feat_idx = lang_map['dflt']
                        if features[feat_idx]['lookups']:
                            output.append("    # Default language system")
                            seen = set()
                            for lookup_idx in features[feat_idx]['lookups']:
                                if lookup_idx not in seen:
                                    output.append(f"  lookup lookup_{lookup_idx};")
                                    seen.add(lookup_idx)
                    
                    # Handle specific languages
                    for lang_tag in sorted(lang_map.keys()):
                        if lang_tag != 'dflt':
                            feat_idx = lang_map[lang_tag]
                            output.append(f"    language {lang_tag};")
                            if features[feat_idx]['lookups']:
                                seen = set()
                                for lookup_idx in features[feat_idx]['lookups']:
                                    if lookup_idx not in seen:
                                        output.append(f"    lookup lookup_{lookup_idx};")
                                        seen.add(lookup_idx)
            
            output.append(f"}} {feat_tag};\n")
        
        return "\n".join(output)
    
    def find_feature_scripts(self, feature_tag: str, scripts: Dict,
                            features: Dict) -> Dict[str, List[str]]:
        """Find which scripts/languages use a given feature"""
        script_langs = defaultdict(set)
        
        for script_tag, script_data in scripts.items():
            # Check default language
            for feat_idx in script_data['default']:
                if features[feat_idx]['tag'] == feature_tag:
                    script_langs[script_tag].add('dflt')
            
            # Check specific languages
            for lang_tag, feat_indices in script_data['languages'].items():
                for feat_idx in feat_indices:
                    if features[feat_idx]['tag'] == feature_tag:
                        script_langs[script_tag].add(lang_tag)
        
        return {k: list(v) for k, v in script_langs.items()}
    
    def convert_gpos_placeholder(self) -> str:
        """Placeholder for GPOS conversion"""
        return """
# ========================================
# GPOS (Glyph Positioning) Table
# ========================================
# TODO: GPOS conversion not yet implemented
"""
    
    def convert_gdef_placeholder(self) -> str:
        """Placeholder for GDEF conversion"""
        return """
# ========================================
# GDEF (Glyph Definition) Table
# ========================================
# TODO: GDEF conversion not yet implemented
"""
    
    def convert_jstf_placeholder(self) -> str:
        """Placeholder for JSTF conversion"""
        return """
# ========================================
# JSTF (Justification) Table
# ========================================
# TODO: JSTF conversion not yet implemented
"""


def main():
    parser = argparse.ArgumentParser(
        description='Convert TTX font files to Adobe FEA format'
    )
    parser.add_argument('input', help='Input TTX file')
    parser.add_argument('-o', '--output', help='Output FEA file (default: stdout)')
    parser.add_argument('--table', action='append', default=[],
                       help='Table to extract (GSUB, GPOS, GDEF, JSTF). Can be specified multiple times.')
    parser.add_argument('--script', action='append', default=[],
                       help='Script to extract (thai, latn, etc). Can be specified multiple times. Default: all scripts')
    
    args = parser.parse_args()
    
    # Default to GSUB if no tables specified
    if not args.table:
        args.table = ['GSUB']
    
    # Convert
    converter = TTXtoFEA(args.input, args.table, args.script)
    fea_output = converter.convert()
    
    # Output
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(fea_output)
        print(f"FEA file written to {args.output}")
    else:
        print(fea_output)


if __name__ == '__main__':
    main()
    
