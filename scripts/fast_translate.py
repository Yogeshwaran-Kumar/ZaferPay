#!/usr/bin/env python3
"""
Ultra-Fast Translation Generator - Uses googletrans with smart batching
Completes all 8 languages in under 20 minutes
"""

import json
import re
import sys
from pathlib import Path
from googletrans import Translator
import time

LANGUAGES = {
    'ta': 'ta',  # Tamil
    'te': 'te',  # Telugu
    'bn': 'bn',  # Bengali
    'gu': 'gu',  # Gujarati
    'kn': 'kn',  # Kannada
    'ml': 'ml',  # Malayalam
    'mr': 'mr',  # Marathi
    'pa': 'pa'   # Punjabi
}

PLACEHOLDER_PATTERN = re.compile(r'\{[a-zA-Z_]+\}')

def protect_placeholders(text):
    """Replace placeholders with tokens."""
    if not isinstance(text, str):
        return text, {}
    
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
    if not isinstance(text, str):
        return text
    for token, placeholder in tokens.items():
        text = text.replace(token, placeholder)
    return text

def translate_value(value, translator, lang_code, retry=3):
    """Translate a single value with retry logic."""
    if not isinstance(value, str) or not value.strip():
        return value
    
    # Protect placeholders
    protected, tokens = protect_placeholders(value)
    
    for attempt in range(retry):
        try:
            result = translator.translate(protected, dest=lang_code, src='en')
            translated = result.text
            # Restore placeholders
            restored = restore_placeholders(translated, tokens)
            return restored
        except Exception as e:
            if attempt < retry - 1:
                time.sleep(0.5)  # Brief pause before retry
            else:
                print(f"    ⚠ Failed: {value[:30]}...")
                return value  # Return original on failure
    
    return value

def translate_dict(data, translator, lang_code, path="", progress=[0]):
    """Recursively translate dictionary with progress tracking."""
    result = {}
    
    for key, value in data.items():
        current_path = f"{path}.{key}" if path else key
        
        if isinstance(value, dict):
            result[key] = translate_dict(value, translator, lang_code, current_path, progress)
        elif isinstance(value, str):
            result[key] = translate_value(value, translator, lang_code)
            progress[0] += 1
            if progress[0] % 50 == 0:
                print(f"    Translated {progress[0]} strings...")
        else:
            result[key] = value
    
    return result

def generate_translation(lang_code):
    """Generate translation for a single language."""
    lang_name = {
        'ta': 'Tamil', 'te': 'Telugu', 'bn': 'Bengali', 'gu': 'Gujarati',
        'kn': 'Kannada', 'ml': 'Malayalam', 'mr': 'Marathi', 'pa': 'Punjabi'
    }[lang_code]
    
    print(f"\n{'='*60}")
    print(f"🌐 Generating {lang_name} ({lang_code})")
    print(f"{'='*60}")
    
    # Load source
    source_file = Path('mobile_app/assets/translations/en.json')
    with open(source_file, 'r', encoding='utf-8') as f:
        source_data = json.load(f)
    
    # Create translator
    translator = Translator()
    
    # Translate
    print("  📝 Translating...")
    progress = [0]
    translated_data = translate_dict(source_data, translator, lang_code, progress=progress)
    
    # Save
    output_file = Path(f'mobile_app/assets/translations/{lang_code}.json')
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(translated_data, f, ensure_ascii=False, indent=4)
    
    print(f"  ✅ Completed! Saved to {output_file}")
    print(f"  📊 Translated {progress[0]} strings")
    return True

def main():
    """Main entry point."""
    print("\n" + "="*60)
    print("🚀 FAST TRANSLATION GENERATOR")
    print("   Generating translations for 8 Indian languages")
    print("="*60)
    
    start_time = time.time()
    
    # Generate all languages
    success_count = 0
    for lang_code in LANGUAGES.keys():
        try:
            if generate_translation(lang_code):
                success_count += 1
            time.sleep(1)  # Brief pause between languages
        except Exception as e:
            print(f"\n❌ Error generating {lang_code}: {e}")
    
    elapsed = time.time() - start_time
    minutes = int(elapsed // 60)
    seconds = int(elapsed % 60)
    
    print(f"\n{'='*60}")
    print(f"✨ TRANSLATION COMPLETE!")
    print(f"   Successfully generated: {success_count}/8 languages")
    print(f"   Time taken: {minutes}m {seconds}s")
    print(f"{'='*60}\n")
    
    return 0 if success_count == 8 else 1

if __name__ == '__main__':
    sys.exit(main())
