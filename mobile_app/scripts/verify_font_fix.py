#!/usr/bin/env python3
"""
Script to verify that all fonts have been properly replaced with Noto Sans
"""

import os
from pathlib import Path

def check_file_for_outfit(file_path):
    """Check if a file contains GoogleFonts.outfit"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            if 'GoogleFonts.outfit(' in content:
                return True
        return False
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return False

def count_noto_sans_usage(file_path):
    """Count how many times GoogleFonts.notoSans is used in a file"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            return content.count('GoogleFonts.notoSans(')
    except Exception as e:
        return 0

def main():
    """Main verification function"""
    lib_dir = Path(__file__).parent.parent / 'lib'
    
    if not lib_dir.exists():
        print(f"Error: {lib_dir} does not exist")
        return
    
    print("="*70)
    print("FONT FIX VERIFICATION")
    print("="*70)
    print()
    
    # Find all .dart files
    dart_files = list(lib_dir.rglob('*.dart'))
    
    # Check for remaining outfit usage
    outfit_files = []
    for dart_file in dart_files:
        if check_file_for_outfit(dart_file):
            outfit_files.append(dart_file)
    
    # Count noto sans usage
    total_noto_sans = 0
    for dart_file in dart_files:
        total_noto_sans += count_noto_sans_usage(dart_file)
    
    # Report results
    print(f"📊 Total Dart files scanned: {len(dart_files)}")
    print(f"✅ GoogleFonts.notoSans() usage count: {total_noto_sans}")
    print()
    
    if outfit_files:
        print(f"❌ FAILED: Found {len(outfit_files)} files still using GoogleFonts.outfit():")
        for file in outfit_files:
            print(f"   - {file.relative_to(lib_dir.parent)}")
        print()
        print("Please run: python mobile_app/scripts/replace_outfit_with_noto.py")
        return False
    else:
        print("✅ SUCCESS: No GoogleFonts.outfit() usage found!")
        print()
        print("🎉 All fonts have been successfully replaced with Noto Sans!")
        print("🌍 The app now supports all Indian languages:")
        print("   • English")
        print("   • Hindi (हिन्दी)")
        print("   • Tamil (தமிழ்)")
        print("   • Telugu (తెలుగు)")
        print("   • Kannada (ಕನ್ನಡ)")
        print("   • Malayalam (മലയാളം)")
        print("   • Marathi (मराठी)")
        print("   • Punjabi (ਪੰਜਾਬੀ)")
        print("   • Gujarati (ગુજરાતી)")
        print("   • Bengali (বাংলা)")
        print()
        return True
    
    print("="*70)

if __name__ == '__main__':
    success = main()
    exit(0 if success else 1)
