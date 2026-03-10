import json
import os

translations_dir = r"c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations"

new_spending_limit_keys = {
    "cat_hospital": "Hospital",
    "cat_tea_snacks": "Tea & Snacks",
    "cat_school": "School"
}

new_categories_keys = {
    "hospital": "Hospital",
    "tea_snacks": "Tea & Snacks",
    "school": "School"
}

for filename in os.listdir(translations_dir):
    if filename.endswith(".json"):
        filepath = os.path.join(translations_dir, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Update spending_limit
        if "spending_limit" in data:
            for key, val in new_spending_limit_keys.items():
                if key not in data["spending_limit"]:
                    data["spending_limit"][key] = val
        
        # Update categories
        if "categories" in data:
            for key, val in new_categories_keys.items():
                if key not in data["categories"]:
                    data["categories"][key] = val
                    
        with open(filepath, 'w', encoding='utf-8') as f:
             json.dump(data, f, ensure_ascii=False, indent=4)
             
print("Successfully updated all translation files.")
