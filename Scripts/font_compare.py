#!/usr/bin/env python3
"""
Font Shaping Comparison Tool
Compares shaping output between two fonts using HarfBuzz or CoreText
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import List, Dict, Tuple, Optional

# CoreText imports (macOS only)
try:
    from CoreText import (
        CTFontManagerCreateFontDescriptorFromData,
        CTFontCreateWithFontDescriptor,
        CTLineCreateWithAttributedString,
        CTLineGetGlyphRuns,
        CTRunGetGlyphCount,
        CTRunGetGlyphs,
        CTRunGetPositions,
        kCTFontAttributeName
    )
    from Foundation import NSData, NSMutableAttributedString, NSMakeRange
    from Quartz import CGPointMake
    CORETEXT_AVAILABLE = True
except ImportError:
    CORETEXT_AVAILABLE = False


class GlyphInfo:
    """Represents a shaped glyph with its properties"""
    def __init__(self, glyph_id: int, glyph_name: str, x_offset: float,
                 y_offset: float, x_advance: float, y_advance: float, cluster: int = 0):
        self.glyph_id = glyph_id
        self.glyph_name = glyph_name
        self.x_offset = round(x_offset, 2)
        self.y_offset = round(y_offset, 2)
        self.x_advance = round(x_advance, 2)
        self.y_advance = round(y_advance, 2)
        self.cluster = cluster
    
    def __eq__(self, other):
        if not isinstance(other, GlyphInfo):
            return False
        return (self.glyph_id == other.glyph_id and
                self.x_offset == other.x_offset and
                self.y_offset == other.y_offset and
                self.x_advance == other.x_advance and
                self.y_advance == other.y_advance)
    
    def __repr__(self):
        return f"Glyph({self.glyph_id}/{self.glyph_name}, pos=({self.x_offset},{self.y_offset}), adv=({self.x_advance},{self.y_advance}))"


def shape_with_harfbuzz(font_path: str, text: str, font_size: int = 12) -> List[GlyphInfo]:
    """Shape text using HarfBuzz"""
    cmd = [
        'hb-shape',
        f'--font-file={font_path}',
        f'--font-size={font_size}',
        '--output-format=json',
        '--no-clusters',
        text
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        glyphs_data = json.loads(result.stdout)
        
        shaped_glyphs = []
        for glyph in glyphs_data:
            shaped_glyphs.append(GlyphInfo(
                glyph_id=glyph['g'],
                glyph_name=glyph.get('gn', str(glyph['g'])),
                x_offset=glyph.get('dx', 0),
                y_offset=glyph.get('dy', 0),
                x_advance=glyph.get('ax', 0),
                y_advance=glyph.get('ay', 0),
                cluster=glyph.get('cl', 0)
            ))
        
        return shaped_glyphs
    except subprocess.CalledProcessError as e:
        print(f"Error running HarfBuzz: {e.stderr}", file=sys.stderr)
        return []
    except json.JSONDecodeError as e:
        print(f"Error parsing HarfBuzz output: {e}", file=sys.stderr)
        return []


def shape_with_coretext(font_path: str, text: str, font_size: float = 12.0) -> List[GlyphInfo]:
    """Shape text using CoreText (macOS only)"""
    if not CORETEXT_AVAILABLE:
        raise RuntimeError("CoreText is not available. This feature requires macOS and pyobjc-framework-Quartz.")
    
    try:
        # Load font
        font_data = NSData.dataWithContentsOfFile_(font_path)
        if not font_data:
            print(f"Error: Could not load font file: {font_path}", file=sys.stderr)
            return []
        
        font_descriptor = CTFontManagerCreateFontDescriptorFromData(font_data)
        if not font_descriptor:
            print(f"Error: Could not create font descriptor from: {font_path}", file=sys.stderr)
            return []
        
        font = CTFontCreateWithFontDescriptor(font_descriptor, font_size, None)
        if not font:
            print(f"Error: Could not create font from descriptor", file=sys.stderr)
            return []
        
        # Create attributed string
        attr_string = NSMutableAttributedString.alloc().initWithString_(text)
        attr_string.addAttribute_value_range_(
            kCTFontAttributeName,
            font,
            NSMakeRange(0, len(text))
        )
        
        # Create line and get glyph runs
        line = CTLineCreateWithAttributedString(attr_string)
        runs = CTLineGetGlyphRuns(line)
        
        shaped_glyphs = []
        
        for i in range(len(runs)):
            run = runs[i]
            glyph_count = CTRunGetGlyphCount(run)
            
            if glyph_count == 0:
                continue
            
            # Get glyphs and positions
            glyphs = CTRunGetGlyphs(run, NSMakeRange(0, glyph_count), None)
            positions = CTRunGetPositions(run, NSMakeRange(0, glyph_count), None)
            
            # Get advances for this run
            from CoreText import CTRunGetAdvances
            advances = CTRunGetAdvances(run, NSMakeRange(0, glyph_count), None)
            
            for j in range(glyph_count):
                glyph_id = glyphs[j]
                position = positions[j]
                
                # For complex scripts like Thai, we need to track actual positions
                # Calculate offset from expected position
                if j == 0:
                    # First glyph - no offset
                    x_offset = 0
                    y_offset = 0
                else:
                    # Calculate expected position based on previous glyph's position + advance
                    prev_position = positions[j - 1]
                    prev_advance = advances[j - 1] if advances and j - 1 < len(advances) else CGPointMake(0, 0)
                    expected_x = prev_position.x + prev_advance.width
                    expected_y = prev_position.y + prev_advance.height
                    
                    # Offset is difference from expected
                    x_offset = position.x - expected_x
                    y_offset = position.y - expected_y
                
                # Get advance for this glyph
                x_advance = advances[j].width if advances and j < len(advances) else 0
                y_advance = advances[j].height if advances and j < len(advances) else 0
                
                shaped_glyphs.append(GlyphInfo(
                    glyph_id=glyph_id,
                    glyph_name=str(glyph_id),  # CoreText doesn't easily provide glyph names
                    x_offset=x_offset,
                    y_offset=y_offset,
                    x_advance=x_advance,
                    y_advance=y_advance
                ))
        
        return shaped_glyphs
    
    except Exception as e:
        print(f"Error in CoreText shaping: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return []


def values_match_within_tolerance(val1: float, val2: float, tolerance: float) -> bool:
    """Check if two values match within tolerance"""
    return abs(val1 - val2) <= tolerance


def check_y_advance_cancellation(glyphs1: List[GlyphInfo], glyphs2: List[GlyphInfo], 
                                  tolerance: float = 3.0) -> bool:
    """
    Check if Y-advance differences cancel out (sum to near zero).
    This handles cases where AAT distributes Y-advances differently than GPOS
    but the final positioning is the same.
    """
    if len(glyphs1) != len(glyphs2):
        return False
    
    total_y_adv_diff = sum(g2.y_advance - g1.y_advance 
                           for g1, g2 in zip(glyphs1, glyphs2))
    
    return abs(total_y_adv_diff) <= tolerance


def compare_glyph_sequences(glyphs1: List[GlyphInfo], glyphs2: List[GlyphInfo],
                           tolerance: float = 0.01) -> Tuple[bool, List[str], str]:
    """
    Compare two glyph sequences with tolerance
    Returns: (is_match, list_of_differences, error_type)
    error_type: 'sub' (substitution), 'pos' (positioning), or None if match
    """
    differences = []
    has_substitution_error = False
    has_positioning_error = False
    y_advance_differences = []
    
    # Compare glyph count
    if len(glyphs1) != len(glyphs2):
        differences.append(f"Glyph count differs: {len(glyphs1)} vs {len(glyphs2)}")
        has_substitution_error = True
    
    # Compare each glyph
    for i, (g1, g2) in enumerate(zip(glyphs1, glyphs2)):
        # Check substitution first (glyph ID mismatch)
        if g1.glyph_id != g2.glyph_id:
            differences.append(f"Glyph[{i}] ID differs: {g1.glyph_id} vs {g2.glyph_id}")
            has_substitution_error = True
        
        # Check positioning with tolerance
        if not values_match_within_tolerance(g1.x_offset, g2.x_offset, tolerance) or \
           not values_match_within_tolerance(g1.y_offset, g2.y_offset, tolerance):
            differences.append(f"Glyph[{i}] offset differs: ({g1.x_offset},{g1.y_offset}) vs ({g2.x_offset},{g2.y_offset})")
            has_positioning_error = True
        
        # Check X-advance with tolerance
        if not values_match_within_tolerance(g1.x_advance, g2.x_advance, tolerance):
            differences.append(f"Glyph[{i}] X-advance differs: {g1.x_advance} vs {g2.x_advance}")
            has_positioning_error = True
        
        # Track Y-advance differences separately for cancellation check
        if not values_match_within_tolerance(g1.y_advance, g2.y_advance, tolerance):
            y_adv_diff = g2.y_advance - g1.y_advance
            y_advance_differences.append((i, g1.y_advance, g2.y_advance, y_adv_diff))
    
    # Special handling for Y-advance differences that cancel out
    if y_advance_differences and not has_substitution_error:
        # Check if Y-advances cancel out (AAT vs GPOS internal difference)
        if check_y_advance_cancellation(glyphs1, glyphs2, tolerance):
            # Remove Y-advance differences from error list since they cancel
            differences = [d for d in differences if 'Y-advance differs' not in d and 'advance differs' not in d or 'X-advance' in d]
            
            # Add informational note
            if y_advance_differences:
                total_diff = sum(d[3] for d in y_advance_differences)
                differences.append(f"ℹ️  Y-advances differ but cancel out (total: {total_diff:.2f}, within tolerance)")
                # This is acceptable, not an error
                if not differences or all('ℹ️' in d for d in differences):
                    has_positioning_error = False
        else:
            # Y-advances don't cancel - real error
            for i, y1, y2, diff in y_advance_differences:
                differences.append(f"Glyph[{i}] Y-advance differs: {y1} vs {y2} (diff: {diff:.2f})")
            has_positioning_error = True
    
    is_match = len([d for d in differences if not d.startswith('ℹ️')]) == 0
    
    # Determine error type (prioritize substitution errors)
    if has_substitution_error:
        error_type = 'sub'
    elif has_positioning_error:
        error_type = 'pos'
    else:
        error_type = None
    
    return is_match, differences, error_type


def compare_fonts(font1_path: str, font2_path: str, wordlist_path: str,
                  shaper: str = 'hb', output_file: Optional[str] = None,
                  max_errors: int = 100, tolerance: float = 0.01) -> Dict:
    """
    Compare shaping output between two fonts
    """
    # Read wordlist
    try:
        with open(wordlist_path, 'r', encoding='utf-8') as f:
            words = [line.strip() for line in f if line.strip()]
    except Exception as e:
        print(f"Error reading wordlist: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Select shaper function
    if shaper == 'coretext':
        if not CORETEXT_AVAILABLE:
            print("Error: CoreText shaper requires macOS and pyobjc-framework-Quartz", file=sys.stderr)
            print("Install with: pip install pyobjc-framework-Quartz", file=sys.stderr)
            sys.exit(1)
        shape_func = shape_with_coretext
    else:  # hb
        shape_func = shape_with_harfbuzz
    
    # Compare each word
    results = {
        'total_words': len(words),
        'words_processed': 0,
        'matches': 0,
        'mismatches': 0,
        'sub_errors': 0,
        'pos_errors': 0,
        'acceptable_differences': 0,
        'stopped_early': False,
        'mismatched_words': [],
        'details': []
    }
    
    print(f"\nComparing {len(words)} words using {shaper.upper()} shaper...")
    print(f"Font 1: {Path(font1_path).name}")
    print(f"Font 2: {Path(font2_path).name}")
    print(f"Tolerance: ±{tolerance}")
    print(f"Max errors: {max_errors}")
    print("\nError types:")
    print("  🔀 SUB = Substitution errors (glyph IDs differ)")
    print("  📍 POS = Positioning errors (positions/advances differ)")
    print("  ℹ️  INFO = Acceptable differences (e.g., Y-advances that cancel)")
    print("-" * 60)
    
    for word in words:
        # Check if we've hit max errors
        if results['mismatches'] >= max_errors:
            results['stopped_early'] = True
            break
        
        glyphs1 = shape_func(font1_path, word)
        glyphs2 = shape_func(font2_path, word)
        
        results['words_processed'] += 1
        
        is_match, differences, error_type = compare_glyph_sequences(glyphs1, glyphs2, tolerance)
        
        # Check if differences are all informational
        has_real_errors = any(not d.startswith('ℹ️') for d in differences)
        
        detail = {
            'word': word,
            'match': is_match,
            'error_type': error_type,
            'font1_glyphs': [{'id': g.glyph_id, 'name': g.glyph_name,
                             'offset': (g.x_offset, g.y_offset),
                             'advance': (g.x_advance, g.y_advance)} for g in glyphs1],
            'font2_glyphs': [{'id': g.glyph_id, 'name': g.glyph_name,
                             'offset': (g.x_offset, g.y_offset),
                             'advance': (g.x_advance, g.y_advance)} for g in glyphs2],
            'differences': differences
        }
        
        results['details'].append(detail)
        
        if is_match:
            results['matches'] += 1
            if differences:  # Has informational differences
                results['acceptable_differences'] += 1
        else:
            if has_real_errors:
                results['mismatches'] += 1
                if error_type == 'sub':
                    results['sub_errors'] += 1
                elif error_type == 'pos':
                    results['pos_errors'] += 1
                
                results['mismatched_words'].append({
                    'word': word,
                    'error_type': error_type,
                    'differences': differences
                })
            else:
                # Only informational differences
                results['matches'] += 1
                results['acceptable_differences'] += 1
    
    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total words in list:  {results['total_words']}")
    print(f"Words processed:      {results['words_processed']}")
    print(f"Matches:              {results['matches']}")
    if results['acceptable_differences'] > 0:
        print(f"  (with acceptable differences: {results['acceptable_differences']})")
    print(f"Mismatches:           {results['mismatches']}")
    print(f"  🔀 SUB errors:      {results['sub_errors']}")
    print(f"  📍 POS errors:      {results['pos_errors']}")
    
    if results['mismatched_words']:
        print(f"\nMismatched words ({len(results['mismatched_words'])}):")
        for item in results['mismatched_words']:
            # Choose emoji based on error type
            emoji = '🔀' if item['error_type'] == 'sub' else '📍'
            error_label = 'SUB' if item['error_type'] == 'sub' else 'POS'
            
            print(f"  {emoji} [{error_label}] {item['word']}")
            for diff in item['differences'][:3]:  # Show first 3 differences
                print(f"      - {diff}")
            if len(item['differences']) > 3:
                print(f"      ... and {len(item['differences']) - 3} more differences")
    
    if results['stopped_early']:
        print("\n" + "!" * 60)
        print(f"⚠️  STOPPED EARLY: Reached maximum error limit ({max_errors})")
        print(f"   Not all words were processed ({results['total_words'] - results['words_processed']} words remaining)")
        print("!" * 60)
    
    # Save detailed results
    if output_file:
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(results, f, indent=2, ensure_ascii=False)
            print(f"\nDetailed results saved to: {output_file}")
        except Exception as e:
            print(f"Error saving results: {e}", file=sys.stderr)
    
    return results


def main():
    parser = argparse.ArgumentParser(
        description='Compare font shaping output between two fonts',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Using HarfBuzz with default tolerance
  %(prog)s --shaper hb font1.otf font2.ttf wordlist.txt
  
  # Using CoreText with custom tolerance
  %(prog)s --shaper coretext font1.otf font2.ttf wordlist.txt --tolerance 5.0
  
  # Save results to file
  %(prog)s --shaper hb font1.otf font2.ttf wordlist.txt --output results.json
  
  # Stop after 50 mismatches
  %(prog)s --shaper hb font1.otf font2.ttf wordlist.txt --maxerrors 50
        """
    )
    
    parser.add_argument('font1', help='Path to first font file')
    parser.add_argument('font2', help='Path to second font file')
    parser.add_argument('wordlist', help='Path to wordlist file (one word per line)')
    parser.add_argument('--shaper', choices=['hb', 'coretext'], default='hb',
                       help='Shaper to use: hb (HarfBuzz) or coretext (CoreText on macOS)')
    parser.add_argument('--output', '-o', help='Output file for detailed results (JSON)')
    parser.add_argument('--maxerrors', type=int, default=100,
                       help='Maximum number of mismatches before stopping (default: 100)')
    parser.add_argument('--tolerance', type=float, default=0.01,
                       help='Tolerance for position/advance differences (default: 0.01)')
    
    args = parser.parse_args()
    
    # Validate files exist
    for filepath in [args.font1, args.font2, args.wordlist]:
        if not Path(filepath).exists():
            print(f"Error: File not found: {filepath}", file=sys.stderr)
            sys.exit(1)
    
    # Run comparison
    compare_fonts(args.font1, args.font2, args.wordlist, args.shaper, 
                 args.output, args.maxerrors, args.tolerance)


if __name__ == '__main__':
    main()
    