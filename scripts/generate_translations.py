#!/usr/bin/env python3
"""
Translation Generator for ZaferPay Mobile App
Generates accurate translations for 8 Indian languages from English source file.
"""

import json
import re
import sys
import argparse
from pathlib import Path
from typing import Dict, Any, List, Tuple

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("Error: deep_translator not installed. Install with: pip install deep-translator")
    sys.exit(1)


class TranslationGenerator:
    """Generates translations while preserving placeholders and special characters."""
    
    # Language codes and names
    LANGUAGES = {
        'ta': 'Tamil',
        'te': 'Telugu',
        'bn': 'Bengali',
        'gu': 'Gujarati',
        'kn': 'Kannada',
        'ml': 'Malayalam',
        'mr': 'Marathi',
        'pa': 'Punjabi'
    }
    
    # Patterns to protect during translation
    PLACEHOLDER_PATTERN = re.compile(r'\{[a-zA-Z_]+\}')
    SPECIAL_CHARS = ['₹', '•', '→', '←', '↑', '↓']
    
    def __init__(self, source_file: str, target_lang: str):
        """Initialize translator with source file and target language."""
        self.source_file = Path(source_file)
        self.target_lang = target_lang
        self.translator = GoogleTranslator(source='en', target=target_lang)
        self.placeholder_map = {}
        self.placeholder_counter = 0
        
    def protect_placeholders(self, text: str) -> Tuple[str, Dict[str, str]]:
        """Replace placeholders with unique tokens to protect during translation."""
        protected_text = text
        local_map = {}
        
        # Protect placeholders like {amount}, {name}, etc.
        for match in self.PLACEHOLDER_PATTERN.finditer(text):
            placeholder = match.group(0)
            token = f"__PH{self.placeholder_counter}__"
            self.placeholder_counter += 1
            protected_text = protected_text.replace(placeholder, token, 1)
            local_map[token] = placeholder
            
        return protected_text, local_map
    
    def restore_placeholders(self, text: str, placeholder_map: Dict[str, str]) -> str:
        """Restore original placeholders after translation."""
        restored_text = text
        for token, placeholder in placeholder_map.items():
            restored_text = restored_text.replace(token, placeholder)
        return restored_text
    
    def translate_text(self, text: str) -> str:
        """Translate a single text string while preserving placeholders."""
        if not text or not isinstance(text, str):
            return text
            
        # Protect placeholders
        protected_text, local_map = self.protect_placeholders(text)
        
        try:
            # Translate
            translated = self.translator.translate(protected_text)
            
            # Restore placeholders
            restored = self.restore_placeholders(translated, local_map)
            
            return restored
        except Exception as e:
            print(f"Warning: Translation failed for '{text[:50]}...': {e}")
            return text  # Return original on failure
    
    def translate_json_recursive(self, obj: Any, path: str = "") -> Any:
        """Recursively translate JSON structure."""
        if isinstance(obj, dict):
            result = {}
            for key, value in obj.items():
                current_path = f"{path}.{key}" if path else key
                result[key] = self.translate_json_recursive(value, current_path)
            return result
        elif isinstance(obj, list):
            return [self.translate_json_recursive(item, f"{path}[{i}]") 
                    for i, item in enumerate(obj)]
        elif isinstance(obj, str):
            translated = self.translate_text(obj)
            print(f"  {path}: {obj[:50]}... → {translated[:50]}...")
            return translated
        else:
            return obj
    
    def generate_translation(self, output_file: str) -> bool:
        """Generate complete translation file."""
        print(f"\n{'='*60}")
        print(f"Generating {self.LANGUAGES[self.target_lang]} translation")
        print(f"Source: {self.source_file}")
        print(f"Target: {output_file}")
        print(f"{'='*60}\n")
        
        # Load source file
        try:
            with open(self.source_file, 'r', encoding='utf-8') as f:
                source_data = json.load(f)
        except Exception as e:
            print(f"Error loading source file: {e}")
            return False
        
        # Translate
        print("Translating...")
        translated_data = self.translate_json_recursive(source_data)
        
        # Save with UTF-8 encoding
        try:
            output_path = Path(output_file)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(translated_data, f, ensure_ascii=False, indent=4)
            
            print(f"\n✓ Successfully generated {output_file}")
            return True
        except Exception as e:
            print(f"Error saving translation file: {e}")
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Generate translations for ZaferPay mobile app'
    )
    parser.add_argument(
        'language',
        choices=list(TranslationGenerator.LANGUAGES.keys()) + ['all'],
        help='Target language code or "all" for all languages'
    )
    parser.add_argument(
        '--source',
        default='mobile_app/assets/translations/en.json',
        help='Source English translation file'
    )
    parser.add_argument(
        '--output-dir',
        default='mobile_app/assets/translations',
        help='Output directory for translation files'
    )
    
    args = parser.parse_args()
    
    # Determine which languages to process
    if args.language == 'all':
        languages = list(TranslationGenerator.LANGUAGES.keys())
    else:
        languages = [args.language]
    
    # Generate translations
    success_count = 0
    for lang in languages:
        generator = TranslationGenerator(args.source, lang)
        output_file = f"{args.output_dir}/{lang}.json"
        
        if generator.generate_translation(output_file):
            success_count += 1
    
    # Summary
    print(f"\n{'='*60}")
    print(f"Translation generation complete!")
    print(f"Successfully generated {success_count}/{len(languages)} files")
    print(f"{'='*60}\n")
    
    return 0 if success_count == len(languages) else 1


if __name__ == '__main__':
    sys.exit(main())
