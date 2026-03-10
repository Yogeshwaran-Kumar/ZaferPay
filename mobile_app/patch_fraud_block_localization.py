import json
import os

languages = ["bn", "en", "gu", "hi", "hi_en", "kn", "ml", "mr", "pa", "ta", "te"]
base_path = r"c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations"

# Keys for the Fraud Block dialog
new_keys = {
    "transaction": {
        "fraud_blocked_desc": "Transaction blocked. This account has been flagged for fraudulent activity.",
        "error_generic": "Your transaction could not be completed."
    },
    "amount": {
        "done": "Done"
    }
}

# Regional translations for the fraud block description
regional_patches = {
    "ta": { # Tamil
        "transaction": {
            "fraud_blocked_desc": "பரிவர்த்தனை தடுக்கப்பட்டது. இந்த கணக்கு மோசடி நடவடிக்கைகளுக்காகக் குறிக்கப்பட்டுள்ளது.",
            "error_generic": "உங்கள் பரிவர்த்தனையை நிறைவு செய்ய முடியவில்லை."
        }
    },
    "hi": { # Hindi
        "transaction": {
            "fraud_blocked_desc": "लेनदेन अवरुद्ध। इस खाते को धोखाधड़ी वाली गतिविधि के लिए चिह्नित किया गया है।",
            "error_generic": "आपका लेनदेन पूरा नहीं हो सका।"
        }
    },
    "te": { # Telugu
        "transaction": {
            "fraud_blocked_desc": "లావాదేవీ నిరోధించబడింది. ఈ ఖాతా మోసపూరిత కార్యకలాపాల కోసం ఫ్లాగ్ చేయబడింది.",
            "error_generic": "మీ లావాదేవీని పూర్తి చేయడం సాధ్యపడలేదు."
        }
    },
    "hi_en": { # Hinglish
        "transaction": {
            "fraud_blocked_desc": "Transaction blocked. Is account ko fraudulent activity ke liye flag kiya gaya hai.",
            "error_generic": "Aapka transaction complete nahi ho saka."
        }
    }
}

for lang in languages:
    file_path = os.path.join(base_path, f"{lang}.json")
    if not os.path.exists(file_path):
        continue
    
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # 1. Apply baseline English for new keys
    for section, keys in new_keys.items():
        if section not in data:
            data[section] = {}
        for key, value in keys.items():
            if key not in data[section] or lang == 'en':
                data[section][key] = value
                
    # 2. Apply regional overrides if available
    if lang in regional_patches:
        for section, keys in regional_patches[lang].items():
            if section not in data:
                data[section] = {}
            for key, value in keys.items():
                data[section][key] = value

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    print(f"Patched fraud block keys for {lang}.json")

print("\nFraud Block Localization Patch Applied!")
