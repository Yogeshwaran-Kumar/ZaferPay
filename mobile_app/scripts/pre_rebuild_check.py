#!/usr/bin/env python3
"""
Pre-rebuild verification script
Checks if all font fixes are in place before rebuilding the app
"""

import os
from pathlib import Path

def check_main_dart():
    """Check if main.dart uses notoSans in theme"""
    main_file = Path(__file__).parent.parent / 'lib' / 'main.dart'
    with open(main_file, 'r', encoding='utf-8') as f:
        content = f.read()
        has_noto_theme = 'GoogleFonts.notoSansTextTheme()' in content
        has_no_outfit = 'GoogleFonts.outfit' not in content
        return has_noto_theme and has_no_outfit

def check_font_helper():
    """Check if font_helper.dart uses notoSans for all languages"""
    helper_file = Path(__file__).parent.parent / 'lib' / 'utils' / 'font_helper.dart'
    with open(helper_file, 'r', encoding='utf-8') as f:
        content = f.read()
        uses_noto_for_all = 'Use Noto Sans for ALL languages' in content
        has_no_outfit = 'GoogleFonts.outfit' not in content
        return uses_noto_for_all and has_no_outfit

def check_navigation_fix():
    """Check if main_navigation_screen.dart has Expanded widgets"""
    nav_file = Path(__file__).parent.parent / 'lib' / 'main_navigation_screen.dart'
    with open(nav_file, 'r', encoding='utf-8') as f:
        content = f.read()
        has_expanded = content.count('Expanded(') >= 4  # Should have 4 Expanded widgets
        has_flexible = 'Flexible(' in content
        return has_expanded and has_flexible

def count_outfit_usage():
    """Count remaining GoogleFonts.outfit usage"""
    lib_dir = Path(__file__).parent.parent / 'lib'
    count = 0
    for dart_file in lib_dir.rglob('*.dart'):
        with open(dart_file, 'r', encoding='utf-8') as f:
            content = f.read()
            count += content.count('GoogleFonts.outfit(')
    return count

def count_noto_usage():
    """Count GoogleFonts.notoSans usage"""
    lib_dir = Path(__file__).parent.parent / 'lib'
    count = 0
    for dart_file in lib_dir.rglob('*.dart'):
        with open(dart_file, 'r', encoding='utf-8') as f:
            content = f.read()
            count += content.count('GoogleFonts.notoSans(')
    return count

def main():
    print("="*70)
    print("PRE-REBUILD VERIFICATION CHECK")
    print("="*70)
    print()
    
    all_checks_passed = True
    
    # Check 1: main.dart
    print("1. Checking main.dart theme configuration...")
    if check_main_dart():
        print("   ✅ PASS: main.dart uses Noto Sans theme")
    else:
        print("   ❌ FAIL: main.dart still has issues")
        all_checks_passed = False
    print()
    
    # Check 2: font_helper.dart
    print("2. Checking font_helper.dart...")
    if check_font_helper():
        print("   ✅ PASS: font_helper.dart uses Noto Sans for all languages")
    else:
        print("   ❌ FAIL: font_helper.dart still has issues")
        all_checks_passed = False
    print()
    
    # Check 3: Navigation fix
    print("3. Checking main_navigation_screen.dart...")
    if check_navigation_fix():
        print("   ✅ PASS: Navigation overflow fix applied")
    else:
        print("   ❌ FAIL: Navigation fix not applied")
        all_checks_passed = False
    print()
    
    # Check 4: Outfit usage
    print("4. Checking for remaining GoogleFonts.outfit usage...")
    outfit_count = count_outfit_usage()
    if outfit_count == 0:
        print(f"   ✅ PASS: No GoogleFonts.outfit() found")
    else:
        print(f"   ❌ FAIL: Found {outfit_count} instances of GoogleFonts.outfit()")
        all_checks_passed = False
    print()
    
    # Check 5: Noto Sans usage
    print("5. Checking GoogleFonts.notoSans usage...")
    noto_count = count_noto_usage()
    if noto_count > 200:
        print(f"   ✅ PASS: Found {noto_count} instances of GoogleFonts.notoSans()")
    else:
        print(f"   ⚠️  WARNING: Only found {noto_count} instances (expected 240+)")
    print()
    
    print("="*70)
    if all_checks_passed:
        print("✅ ALL CHECKS PASSED!")
        print()
        print("🚀 Ready to rebuild! Run these commands:")
        print()
        print("   cd mobile_app")
        print("   flutter clean")
        print("   flutter pub get")
        print("   flutter run")
        print()
        print("After rebuild, test by:")
        print("1. Go to Settings → Language")
        print("2. Select Tamil/Telugu/Kannada")
        print("3. Check if text is readable (not garbled)")
        print()
    else:
        print("❌ SOME CHECKS FAILED!")
        print()
        print("Please review the failed checks above.")
        print("The font replacement script may need to be run again.")
        print()
    print("="*70)
    
    return all_checks_passed

if __name__ == '__main__':
    success = main()
    exit(0 if success else 1)
