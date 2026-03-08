import json
import os

SOURCE_FILE = r'c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations\en.json'
TRANSLATIONS_DIR = r'c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations'
LANGUAGES = ['hi', 'bn', 'gu', 'kn', 'ml', 'mr', 'ta', 'te', 'pa']

def get_keys(d, parent_key=''):
    keys = set()
    for k, v in d.items():
        new_key = f"{parent_key}.{k}" if parent_key else k
        if isinstance(v, dict):
            keys.update(get_keys(v, new_key))
        else:
            keys.add(new_key)
    return keys

def main():
    with open(SOURCE_FILE, 'r', encoding='utf-8') as f:
        en_keys = get_keys(json.load(f))
    
    all_good = True
    for lang in LANGUAGES:
        file_path = os.path.join(TRANSLATIONS_DIR, f'{lang}.json')
        with open(file_path, 'r', encoding='utf-8') as f:
            lang_keys = get_keys(json.load(f))
        
        missing = en_keys - lang_keys
        if missing:
            print(f"Missing keys in {lang}.json: {len(missing)}")
            # print(list(missing)[:5]) # Show first 5
            all_good = False
        else:
            print(f"{lang}.json is fully synchronized.")
            
    if all_good:
        print("\nSUCCESS: All localization files are 100% synchronized with en.json.")
    else:
        print("\nFAILURE: Some files are missing keys.")

if __name__ == "__main__":
    main()
