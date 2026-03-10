#!/usr/bin/env python3
"""
Parallel Translation - Runs all 8 languages simultaneously
Completes in ~3-5 minutes
"""

import json
import re
import sys
from pathlib import Path
from translate import Translator
import multiprocessing as mp
import time

LANGUAGES = {
    'ta': 'Tamil', 'te': 'Telugu', 'bn': 'Bengali', 'gu': 'Gujarati',
    'kn': 'Kannada', 'ml': 'Malayalam', 'mr': 'Marathi', 'pa': 'Punjabi'
}

PLACEHOLDER_PATTERN = re.compile(r'\{[a-zA-Z_]+\}')

def protect_placeholders(text):
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
    if not isinstance(text, str):
        return text
    for token, placeholder in tokens.items():
        text = text.replace(token, placeholder)
    return text

def translate_value(value, translator):
    if not isinstance(value, str) or not value.strip():
        return value
    protected, tokens = protect_placeholders(value)
    try:
        translated = translator.translate(protected)
        return restore_placeholders(translated, tokens)
    except:
        return value

def translate_dict(data, translator):
    result = {}
    for key, value in data.items():
        if isinstance(value, dict):
            result[key] = translate_dict(value, translator)
        elif isinstance(value, str):
            result[key] = translate_value(value, translator)
        else:
            result[key] = value
    return result

def generate_translation(lang_code):
    """Worker function for parallel translation."""
    try:
        print(f"[{lang_code}] Starting {LANGUAGES[lang_code]}...")
        
        # Load source
        with open('mobile_app/assets/translations/en.json', 'r', encoding='utf-8') as f:
            source_data = json.load(f)
        
        # Translate
        translator = Translator(from_lang='en', to_lang=lang_code)
        translated_data = translate_dict(source_data, translator)
        
        # Save
        output_file = f'mobile_app/assets/translations/{lang_code}.json'
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(translated_data, f, ensure_ascii=False, indent=4)
        
        print(f"[{lang_code}] ✅ Completed {LANGUAGES[lang_code]}!")
        return True
    except Exception as e:
        print(f"[{lang_code}] ❌ Error: {e}")
        return False

def main():
    print("\n" + "="*60)
    print("🚀 PARALLEL TRANSLATION GENERATOR")
    print("   Running 8 languages simultaneously")
    print("="*60 + "\n")
    
    start_time = time.time()
    
    # Run all languages in parallel
    with mp.Pool(processes=8) as pool:
        results = pool.map(generate_translation, LANGUAGES.keys())
    
    success_count = sum(results)
    elapsed = time.time() - start_time
    minutes = int(elapsed // 60)
    seconds = int(elapsed % 60)
    
    print(f"\n{'='*60}")
    print(f"✨ COMPLETE! {success_count}/8 languages in {minutes}m {seconds}s")
    print(f"{'='*60}\n")
    
    return 0 if success_count == 8 else 1

if __name__ == '__main__':
    mp.freeze_support()
    sys.exit(main())
