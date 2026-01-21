#!/usr/bin/env python3
"""
MERGEFIELD Diagnostic Tool
Analyzes a Word document to show exactly how MERGEFIELDs are structured
"""

import zipfile
import re
import sys
from pathlib import Path


def diagnose_mergefields(docx_path: str):
    """
    Analyze a Word document and show detailed MERGEFIELD structure

    This helps understand why fields might not be getting replaced
    """
    print(f"\n{'='*70}")
    print(f"MERGEFIELD Diagnostic Report: {Path(docx_path).name}")
    print(f"{'='*70}\n")

    try:
        with zipfile.ZipFile(docx_path, 'r') as zip_ref:
            xml_content = zip_ref.read('word/document.xml').decode('utf-8')
    except Exception as e:
        print(f"❌ Error reading document: {e}")
        return

    # Analysis 1: Find all MERGEFIELD references
    print("📋 MERGEFIELD References Found:")
    print("-" * 70)

    mergefield_pattern = r'MERGEFIELD\s+([^\s\\<]+)'
    mergefields = re.findall(mergefield_pattern, xml_content, re.IGNORECASE)

    if mergefields:
        unique_fields = list(set(mergefields))
        print(f"Found {len(mergefields)} MERGEFIELD references ({len(unique_fields)} unique)")
        print("\nUnique field names:")
        for i, field in enumerate(sorted(unique_fields), 1):
            count = mergefields.count(field)
            print(f"  {i}. {field} (appears {count} time{'s' if count > 1 else ''})")
    else:
        print("⚠️  No MERGEFIELD references found!")

    # Analysis 2: Check field structure types
    print(f"\n📐 Field Structure Analysis:")
    print("-" * 70)

    # Type 1: Complete fields with begin/separate/end
    complete_fields = re.findall(
        r'<w:fldChar\s+w:fldCharType="begin"[^>]*/>.*?<w:fldChar\s+w:fldCharType="end"[^>]*/>',
        xml_content,
        re.DOTALL
    )
    print(f"Complete field structures (begin→end): {len(complete_fields)}")

    # Type 2: instrText tags
    instr_text_fields = re.findall(
        r'<w:instrText[^>]*>.*?MERGEFIELD.*?</w:instrText>',
        xml_content,
        re.IGNORECASE | re.DOTALL
    )
    print(f"Fields in <w:instrText> tags: {len(instr_text_fields)}")

    # Type 3: Split across runs
    split_pattern = r'<w:t[^>]*>.*?MERGE.*?</w:t>.*?<w:t[^>]*>.*?FIELD.*?</w:t>'
    split_fields = re.findall(split_pattern, xml_content, re.DOTALL | re.IGNORECASE)
    if split_fields:
        print(f"⚠️  Fields split across runs: {len(split_fields)}")
        print("   (These are harder to replace and may be causing issues)")

    # Analysis 3: Show sample field structures
    print(f"\n🔍 Sample Field Structures:")
    print("-" * 70)

    # Extract and show first 3 complete field examples
    if complete_fields:
        print("\nExample of complete field structure:")
        sample = complete_fields[0][:500]  # First 500 chars
        # Pretty print
        sample = sample.replace('><', '>\n<')
        print(f"\n{sample}\n...")

    if instr_text_fields:
        print("\nExample of instrText field:")
        print(f"{instr_text_fields[0][:200]}")

    # Analysis 4: Check for problematic patterns
    print(f"\n⚠️  Potential Issues:")
    print("-" * 70)

    issues_found = False

    # Check for fields without proper markers
    orphan_instrs = re.findall(
        r'<w:instrText[^>]*>.*?MERGEFIELD.*?</w:instrText>',
        xml_content,
        re.IGNORECASE
    )
    orphan_count = 0
    for instr in orphan_instrs:
        # Check if there's a nearby fldChar
        context_start = xml_content.find(instr) - 200
        context_end = xml_content.find(instr) + len(instr) + 200
        context = xml_content[max(0, context_start):context_end]

        if 'fldChar' not in context:
            orphan_count += 1

    if orphan_count > 0:
        print(f"• {orphan_count} fields without proper begin/end markers")
        print("  → These fields may not be replaced correctly")
        issues_found = True

    # Check for complex field codes
    complex_fields = [f for f in instr_text_fields if '\\' in f or '@' in f]
    if complex_fields:
        print(f"• {len(complex_fields)} fields with complex formatting codes (\\, @, etc.)")
        print("  → These may need special handling")
        issues_found = True

    # Check for nested fields
    if xml_content.count('fldChar') > len(complete_fields) * 2:
        print("• Possible nested or overlapping fields detected")
        print("  → Nested fields can cause replacement issues")
        issues_found = True

    if not issues_found:
        print("✓ No obvious issues detected")

    # Analysis 5: Replacement readiness
    print(f"\n✅ Replacement Readiness:")
    print("-" * 70)

    total_fields = len(unique_fields)
    complete_field_names = []

    for field_struct in complete_fields:
        match = re.search(r'MERGEFIELD\s+([^\s\\<]+)', field_struct, re.IGNORECASE)
        if match:
            complete_field_names.append(match.group(1))

    complete_unique = len(set(complete_field_names))

    print(f"Total unique fields: {total_fields}")
    print(f"Fields in complete structures: {complete_unique}")

    if complete_unique == total_fields:
        print("✓ All fields have complete structures - should replace well")
    else:
        missing = total_fields - complete_unique
        print(f"⚠️  {missing} fields may not have complete structures")
        print("   → These may require manual review or improved replacement logic")

    # Analysis 6: Recommendations
    print(f"\n💡 Recommendations:")
    print("-" * 70)

    if split_fields:
        print("• Enable split-field detection in converter")
        print("  → Use improved regex patterns to handle fields split across runs")

    if orphan_count > 0:
        print("• Some fields lack proper markers")
        print("  → Consider using instrText-only replacement for these")

    if complete_fields:
        print("• Use complete field structure replacement first")
        print("  → This is the most reliable method")

    print("\n" + "="*70)
    print("End of diagnostic report")
    print("="*70 + "\n")


def main():
    if len(sys.argv) < 2:
        print("MERGEFIELD Diagnostic Tool")
        print("\nUsage:")
        print("  python diagnose_mergefields.py <template.docx>")
        print("\nExample:")
        print("  python diagnose_mergefields.py old_template.docx")
        sys.exit(1)

    docx_path = sys.argv[1]

    if not Path(docx_path).exists():
        print(f"❌ Error: File not found: {docx_path}")
        sys.exit(1)

    diagnose_mergefields(docx_path)


if __name__ == '__main__':
    main()
