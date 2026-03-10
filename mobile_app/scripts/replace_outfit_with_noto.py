#!/usr/bin/env python3
"""
Script to replace all GoogleFonts.outfit() with GoogleFonts.notoSans() in Dart files
to fix font rendering issues for all Indian languages.
"""

import os
import re
from pathlib import Path

def replace_outfit_with_noto(file_path):
    """Replace GoogleFonts.outfit with GoogleFonts.notoSans in a file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        # Replace GoogleFonts.outfit( with GoogleFonts.notoSans(
        content = content.replace('GoogleFonts.outfit(', 'GoogleFonts.notoSans(')
        
        # Also replace GoogleFonts.outfitTextTheme with GoogleFonts.notoSansTextTheme
        content = content.replace('GoogleFonts.outfitTextTheme', 'GoogleFonts.notoSansTextTheme')
        
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return True
        return False
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
        return False

def main():
    """Main function to process all Dart files."""
    # Get the mobile_app/lib directory
    lib_dir = Path(__file__).parent.parent / 'lib'
    
    if not lib_dir.exists():
        print(f"Error: {lib_dir} does not exist")
        return
    
    print(f"Searching for Dart files in {lib_dir}...")
    
    # Find all .dart files recursively
    dart_files = list(lib_dir.rglob('*.dart'))
    
    print(f"Found {len(dart_files)} Dart files")
    
    modified_count = 0
    for dart_file in dart_files:
        if replace_outfit_with_noto(dart_file):
            modified_count += 1
            print(f"✓ Modified: {dart_file.relative_to(lib_dir.parent)}")
    
    print(f"\n{'='*60}")
    print(f"Replacement complete!")
    print(f"Modified {modified_count} out of {len(dart_files)} files")
    print(f"{'='*60}")

if __name__ == '__main__':
    main()
