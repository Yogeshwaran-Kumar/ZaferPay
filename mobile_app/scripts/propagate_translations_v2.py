import json
import os

langs = ['ta', 'hi', 'bn', 'gu', 'kn', 'ml', 'mr', 'te', 'pa']
base_path = 'assets/translations'
en_path = os.path.join(base_path, 'en.json')

with open(en_path, 'r', encoding='utf-8') as f:
    en_data = json.load(f)

def merge_dicts(source, target):
    for key, value in source.items():
        if isinstance(value, dict):
            if key not in target or not isinstance(target[key], dict):
                target[key] = {}
            merge_dicts(value, target[key])
        else:
            if key not in target:
                target[key] = value

for lang in langs:
    lang_path = os.path.join(base_path, f'{lang}.json')
    if os.path.exists(lang_path):
        with open(lang_path, 'r', encoding='utf-8') as f:
            lang_data = json.load(f)
    else:
        lang_data = {}
    
    merge_dicts(en_data, lang_data)
    
    with open(lang_path, 'w', encoding='utf-8') as f:
        json.dump(lang_data, f, indent=4, ensure_ascii=False)
    print(f'Propagated to {lang}.json')
