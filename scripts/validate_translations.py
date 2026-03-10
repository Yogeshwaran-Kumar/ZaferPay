#!/usr/bin/env python3
"""
Translation Validator for ZaferPay Mobile App
Validates translation files for structure, encoding, and completeness.
"""

import json
import re
import sys
import argparse
from pathlib import Path
from typing import Dict, Any, List, Set, Tuple


class TranslationValidator:
    """Validates translation files against source file."""
    
    PLACEHOLDER_PATTERN = re.compile(r'\{[a-zA-Z_]+\}')
    
    def __init__(self, source_file: str):
        """Initialize validator with source file."""
        self.source_file = Path(source_file)
        self.source_data = None
        self.errors = []
        self.warnings = []
        
        # Load source file
        try:
            with open(self.source_file, 'r', encoding='utf-8') as f:
                self.source_data = json.load(f)
        except Exception as e:
            print(f"Error loading source file: {e}")
            sys.exit(1)
    
    def get_all_keys(self, obj: Any, prefix: str = "") -> Set[str]:
        """Recursively get all keys from nested JSON."""
        keys = set()
        
        if isinstance(obj, dict):
            for key, value in obj.items():
                current_path = f"{prefix}.{key}" if prefix else key
                keys.add(current_path)
                keys.update(self.get_all_keys(value, current_path))
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                keys.update(self.get_all_keys(item, f"{prefix}[{i}]"))
        
        return keys
    
    def get_value_at_path(self, obj: Any, path: str) -> Any:
        """Get value at a specific path in nested JSON."""
        parts = path.split('.')
        current = obj
        
        for part in parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                return None
        
        return current
    
    def extract_placeholders(self, text: str) -> Set[str]:
        """Extract all placeholders from a string."""
        if not isinstance(text, str):
            return set()
        return set(self.PLACEHOLDER_PATTERN.findall(text))
    
    def validate_structure(self, target_data: Dict, target_file: str) -> bool:
        """Validate JSON structure matches source."""
        print(f"\n  Validating structure...")
        
        source_keys = self.get_all_keys(self.source_data)
        target_keys = self.get_all_keys(target_data)
        
        missing_keys = source_keys - target_keys
        extra_keys = target_keys - source_keys
        
        if missing_keys:
            self.errors.append(f"Missing keys: {', '.join(sorted(list(missing_keys)[:5]))}")
            if len(missing_keys) > 5:
                self.errors.append(f"  ... and {len(missing_keys) - 5} more")
        
        if extra_keys:
            self.warnings.append(f"Extra keys: {', '.join(sorted(list(extra_keys)[:5]))}")
            if len(extra_keys) > 5:
                self.warnings.append(f"  ... and {len(extra_keys) - 5} more")
        
        if not missing_keys and not extra_keys:
            print(f"    ✓ Structure matches source ({len(source_keys)} keys)")
            return True
        else:
            print(f"    ✗ Structure mismatch")
            return False
    
    def validate_placeholders(self, target_data: Dict) -> bool:
        """Validate placeholders are preserved."""
        print(f"\n  Validating placeholders...")
        
        issues = []
        
        def check_recursive(source_obj: Any, target_obj: Any, path: str = ""):
            if isinstance(source_obj, dict) and isinstance(target_obj, dict):
                for key in source_obj:
                    if key in target_obj:
                        current_path = f"{path}.{key}" if path else key
                        check_recursive(source_obj[key], target_obj[key], current_path)
            elif isinstance(source_obj, str) and isinstance(target_obj, str):
                source_placeholders = self.extract_placeholders(source_obj)
                target_placeholders = self.extract_placeholders(target_obj)
                
                if source_placeholders != target_placeholders:
                    issues.append(f"{path}: {source_placeholders} → {target_placeholders}")
        
        check_recursive(self.source_data, target_data)
        
        if issues:
            self.errors.extend([f"Placeholder mismatch: {issue}" for issue in issues[:5]])
            if len(issues) > 5:
                self.errors.append(f"  ... and {len(issues) - 5} more")
            print(f"    ✗ Found {len(issues)} placeholder mismatches")
            return False
        else:
            print(f"    ✓ All placeholders preserved")
            return True
    
    def validate_encoding(self, target_file: str) -> bool:
        """Validate UTF-8 encoding."""
        print(f"\n  Validating encoding...")
        
        try:
            with open(target_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Check for BOM
            if content.startswith('\ufeff'):
                self.warnings.append("File contains BOM (should be BOM-less UTF-8)")
            
            # Try to encode/decode to verify
            content.encode('utf-8').decode('utf-8')
            
            print(f"    ✓ Valid UTF-8 encoding")
            return True
        except UnicodeDecodeError as e:
            self.errors.append(f"Encoding error: {e}")
            print(f"    ✗ Invalid UTF-8 encoding")
            return False
    
    def validate_json_syntax(self, target_file: str) -> Tuple[bool, Dict]:
        """Validate JSON syntax."""
        print(f"\n  Validating JSON syntax...")
        
        try:
            with open(target_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            print(f"    ✓ Valid JSON syntax")
            return True, data
        except json.JSONDecodeError as e:
            self.errors.append(f"JSON syntax error: {e}")
            print(f"    ✗ Invalid JSON syntax")
            return False, None
    
    def validate_file(self, target_file: str) -> bool:
        """Validate a single translation file."""
        print(f"\n{'='*60}")
        print(f"Validating: {target_file}")
        print(f"{'='*60}")
        
        self.errors = []
        self.warnings = []
        
        # Check file exists
        if not Path(target_file).exists():
            print(f"  ✗ File does not exist")
            return False
        
        # Validate JSON syntax
        valid_json, target_data = self.validate_json_syntax(target_file)
        if not valid_json:
            return False
        
        # Validate encoding
        valid_encoding = self.validate_encoding(target_file)
        
        # Validate structure
        valid_structure = self.validate_structure(target_data, target_file)
        
        # Validate placeholders
        valid_placeholders = self.validate_placeholders(target_data)
        
        # Print results
        print(f"\n  Results:")
        if self.errors:
            print(f"    Errors ({len(self.errors)}):")
            for error in self.errors:
                print(f"      - {error}")
        
        if self.warnings:
            print(f"    Warnings ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"      - {warning}")
        
        all_valid = valid_json and valid_encoding and valid_structure and valid_placeholders
        
        if all_valid:
            print(f"\n  ✓ All validations passed")
        else:
            print(f"\n  ✗ Validation failed")
        
        return all_valid


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Validate translation files for ZaferPay mobile app'
    )
    parser.add_argument(
        'files',
        nargs='+',
        help='Translation files to validate'
    )
    parser.add_argument(
        '--source',
        default='mobile_app/assets/translations/en.json',
        help='Source English translation file'
    )
    
    args = parser.parse_args()
    
    validator = TranslationValidator(args.source)
    
    all_valid = True
    for file in args.files:
        if not validator.validate_file(file):
            all_valid = False
    
    print(f"\n{'='*60}")
    if all_valid:
        print(f"✓ All files validated successfully")
    else:
        print(f"✗ Some files failed validation")
    print(f"{'='*60}\n")
    
    return 0 if all_valid else 1


if __name__ == '__main__':
    sys.exit(main())
