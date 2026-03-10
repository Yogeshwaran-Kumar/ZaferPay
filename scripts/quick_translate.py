#!/usr/bin/env python3
"""
Quick Translation Generator - Generates translations in batches to avoid timeouts
"""

import json
import re
import sys
from pathlib import Path
from deep_translator import GoogleTranslator
import time

# Language mappings
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

PLACEHOLDER_PATTERN = re.compile(r'\{[a-zA-Z_]+\}')

def protect_placeholders(text):
    """Replace placeholders with tokens."""
    tokens = {}
    counter = [0]
    
    def replacer(match):
        token = f"__PH{counter[0]}__"
        counter[0] += 1
        tokens[token] = match.group(0)
        return token
    
    protected = PLACEHOLDER_PATTERN.sub(replacer, text)
    return protected, tokens

def restore_placeholders(text, tokens):
    """Restore original placeholders."""
    for token, placeholder in tokens.items():
        text = text.replace(token, placeholder)
    return text

def translate_text(text, translator):
    """Translate a single string."""
    if not text or not isinstance(text, str) or len(text.strip()) == 0:
        return text
    
    # Protect placeholders
    protected, tokens = protect_placeholders(text)
    
    try:
        # Translate
        translated = translator.translate(protected)
        # Restore placeholders
        restored = restore_placeholders(translated, tokens)
        return restored
    except Exception as e:
        print(f"  Warning: {str(e)[:50]}")
        return text

def translate_dict(data, translator, path=""):
    """Recursively translate dictionary."""
    result = {}
    for key, value in data.items():
        current_path = f"{path}.{key}" if path else key
        
        if isinstance(value, dict):
            result[key] = translate_dict(value, translator, current_path)
        elif isinstance(value, str):
            result[key] = translate_text(value, translator)
            if len(current_path) < 30:
                print(f"  {current_path}")
        else:
            result[key] = value
    
    return result

def generate_translation(lang_code):
    """Generate translation for a single language."""
    print(f"\n{'='*60}")
    print(f"Generating {LANGUAGES[lang_code]} ({lang_code})")
    print(f"{'='*60}\n")
    
    # Load source
    source_file = Path('mobile_app/assets/translations/en.json')
    with open(source_file, 'r', encoding='utf-8') as f:
        source_data = json.load(f)
    
    # Create translator
    translator = GoogleTranslator(source='en', target=lang_code)
    
    # Translate
    print("Translating...")
    translated_data = translate_dict(source_data, translator)
    
    # Save
    output_file = Path(f'mobile_app/assets/translations/{lang_code}.json')
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(translated_data, f, ensure_ascii=False, indent=4)
    
    print(f"\n✓ Saved to {output_file}")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python quick_translate.py <lang_code|all>")
        sys.exit(1)
    
    arg = sys.argv[1]
    
    if arg == 'all':
        langs = list(LANGUAGES.keys())
    else:
        langs = [arg]
    
    for lang in langs:
        try:
            generate_translation(lang)
            time.sleep(2)  # Brief pause between languages
        except Exception as e:
            print(f"\n✗ Error generating {lang}: {e}")
    
    print(f"\n{'='*60}")
    print("Translation generation complete!")
    print(f"{'='*60}\n")
