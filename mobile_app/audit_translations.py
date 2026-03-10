import os
import json
import re

def get_translation_keys(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    keys = set()
    def extract_keys(d, prefix=''):
        for k, v in d.items():
            full_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                extract_keys(v, full_key)
            else:
                keys.add(full_key)
    extract_keys(data)
    return keys

def audit_json_files(directory):
    files = [f for f in os.listdir(directory) if f.endswith('.json')]
    all_keys = {}
    for f in files:
        all_keys[f] = get_translation_keys(os.path.join(directory, f))
    
    union_keys = set().union(*all_keys.values())
    
    print(f"Total unique keys: {len(union_keys)}")
    for f, keys in all_keys.items():
        missing = union_keys - keys
        if missing:
            print(f"--- {f} is missing {len(missing)} keys ---")
            for k in sorted(list(missing)):
                print(f"  {k}")
        else:
            print(f"--- {f} has all {len(union_keys)} keys ---")

if __name__ == "__main__":
    audit_json_files(r'c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations')
