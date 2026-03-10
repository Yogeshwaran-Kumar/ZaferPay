import json
import os

# Define the source of truth
SOURCE_FILE = r'c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations\en.json'
TRANSLATIONS_DIR = r'c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations'

LANGUAGES = ['hi', 'bn', 'gu', 'kn', 'ml', 'mr', 'ta', 'te', 'pa']

# Key translations for new/critical sections (Hindi example)
# Note: For brevity and to ensure accuracy, I'll focus on the most critical sections 
# like 'chatbot', 'analysis', and 'details' which were recently changed/added.
# In a real environment, I'd use an API, but here I'll provide curated translations for major ones.

def translate_content(lang, key_path, en_value):
    # This is a placeholder for specific translations I'll inject
    # Most keys will fall back to English if not explicitly handled here, 
    # but the script will ensure the KEY exists in the destination file.
    
    # Specific translations for 'chatbot' and critical 'details'
    translations = {
        'ta': { # Tamil
            'chatbot.title': 'சைபர் உதவி',
            'chatbot.subtitle': 'யுபிஐ மோசடி புகார் உதவியாளர்',
            'chatbot.welcome': 'வணக்கம்! 👋 நான் உங்கள் **சைபர் புகார் உதவியாளர்**.\n\nநான் உங்களுக்கு உதவ முடியும்:\n• யுபிஐ மோசடி புகார்களைப் பதிவு செய்தல்\n• அங்கீகரிக்கப்படாத பரிவர்த்தனைகளைப் புகாரளித்தல்\n• சைபர் கிரைம் உதவி எண்ணைத் தொடர்புகொள்ளுதல்\n• உங்கள் உரிமைகளைப் புரிந்துகொள்ளுதல்\n\nஇன்று நான் உங்களுக்கு எப்படி உதவ முடியும்?',
            'chatbot.hint': 'யுபிஐ மோசடி புகார்கள் பற்றி கேளுங்கள்...',
            'chatbot.suggest_fraud': '🚨 யுபிஐ மோசடி புகாரை எப்படி பதிவு செய்வது?',
            'chatbot.suggest_helpline': '📞 உதவி எண் 1930 என்றால் என்ன?',
            'chatbot.suggest_unauthorized': '🏦 அங்கீகரிக்கப்படாத பரிவர்த்தனையைப் புகாரளிக்கவும்',
            'chatbot.suggest_docs': '📋 புகாருக்குத் தேவையான ஆவணங்கள்',
            'details.complaint_success': 'புகார் வெற்றிகரமாக சமர்ப்பிக்கப்பட்டது!',
            'details.complaint_success_msg': 'உங்கள் புகார் ZaferPay-க்கு சமர்ப்பிக்கப்பட்டது. அதிகாரப்பூர்வ அறிக்கையைப் பதிவு செய்ய நீங்கள் இப்போது சைபர் கிரைம் போர்ட்டலுக்கு அழைத்துச் செல்லப்படுவீர்கள்.',
            'details.continue_portal': 'சைபர் கிரைம் போர்ட்டலுக்குத் தொடரவும்',
            'details.go_back': 'திரும்பிச் செல்லவும்',
            'details.submit_complaint': 'புகார் அளிக்கவும்',
            'analysis.spend_analysis_for_month': '{month}-க்கான உங்கள் செலவு பகுப்பாய்வு',
            'analysis.no_spends': 'இந்த மாதம் இன்னும் செலவுகள் இல்லை.',
            'analysis.top_spends': 'முக்கிய செலவுகள்',
        },
        'hi': { # Hindi
            'chatbot.title': 'साइबर सहायता',
            'chatbot.subtitle': 'UPI धोखाधड़ी शिकायत सहायक',
            'chatbot.welcome': 'नमस्ते! 👋 मैं आपका **साइபர் शिकायत सहायक** हूँ।\n\nमैं आपकी मदद कर सकता हूँ:\n• UPI धोखाधड़ी की शिकायत दर्ज करना\n• अनधिकृत लेनदेन की रिपोर्ट करना\n• साइबर क्राइम हेल्पलाइन से संपर्क करना\n• अपने अधिकारों को समझना\n\nआज मैं आपकी कैसे मदद कर सकता हूँ?',
            'chatbot.hint': 'UPI धोखाधड़ी शिकायतों के बारे में पूछें...',
            'chatbot.suggest_fraud': '🚨 UPI धोखाधड़ी की शिकायत कैसे दर्ज करें?',
            'chatbot.suggest_helpline': '📞 हेल्पलाइन 1930 क्या है?',
            'chatbot.suggest_unauthorized': '🏦 अनधिकृत लेनदेन की रिपोर्ट करें',
            'chatbot.suggest_docs': '📋 शिकायत के लिए आवश्यक दस्तावेज',
            'details.complaint_success': 'शिकायत सफलतापूर्वक सबमिट की गई!',
            'details.complaint_success_msg': 'आपकी शिकायत ZaferPay को भेज दी गई है। अब आपको आधिकारिक रिपोर्ट दर्ज करने के लिए साइबर क्राइम पोर्टल पर निर्देशित किया जाएगा।',
            'details.continue_portal': 'साइபர் क्राइम पोर्टल पर जाएँ',
            'details.go_back': 'वापस जाएँ',
            'details.submit_complaint': 'शिकायत दर्ज करें',
            'analysis.spend_analysis_for_month': '{month} के लिए आपका खर्च विश्लेषण',
            'analysis.no_spends': 'इस महीने अभी तक कोई खर्च नहीं हुआ है।',
            'analysis.top_spends': 'शीर्ष खर्च',
        },
        'te': { # Telugu
            'chatbot.title': 'సైబర్ సహాయం',
            'chatbot.subtitle': 'UPI మోసం ఫిర్యాదు సహాయకుడు',
            'chatbot.welcome': 'నమస్కారం! 👋 నేను మీ **సైబర్ ఫిర్యాదు సహాయకుడిని**.\n\nనేను మీకు సహాయం చేయగలను:\n• UPI మోసం ఫిర్యాదులను నమోదు చేయడం\n• అనధికార లావాదేవీలను నివేదించడం\n• సైబర్ క్రైమ్ హెల్ప్‌లైన్‌ను సంప్రదించడం\n• మీ హక్కులను అర్థం చేసుకోవడం\n\nఈరోజు నేను మీకు ఎలా సహాయపడగలను?',
            'chatbot.hint': 'UPI మోసం ఫిర్యాదుల గురించి అడగండి...',
            'details.complaint_success': 'ఫిర్యాదు విజయవంతంగా సమర్పించబడింది!',
            'details.submit_complaint': 'ఫిర్యాదు చేయండి',
            'analysis.spend_analysis_for_month': '{month} కోసం మీ ఖర్చు విశ్లేషణ',
        }
        # Add more languages as needed, but ensuring keys exist is priority 1
    }
    
    return translations.get(lang, {}).get(key_path, en_value)

def merge_dicts(source, target, lang, path=""):
    for key, value in source.items():
        current_path = f"{path}.{key}" if path else key
        if isinstance(value, dict):
            if key not in target or not isinstance(target[key], dict):
                target[key] = {}
            merge_dicts(value, target[key], lang, current_path)
        else:
            if key not in target or target[key] == key or target[key] == value:
                # If target key is missing, or is same as key (fallback behavior), 
                # or is same as English value, try to get a better translation
                target[key] = translate_content(lang, current_path, value)

def main():
    with open(SOURCE_FILE, 'r', encoding='utf-8') as f:
        en_data = json.load(f)

    for lang in LANGUAGES:
        file_path = os.path.join(TRANSLATIONS_DIR, f'{lang}.json')
        print(f"Processing {lang}.json...")
        
        if os.path.exists(file_path):
            with open(file_path, 'r', encoding='utf-8') as f:
                try:
                    lang_data = json.load(f)
                except json.JSONDecodeError:
                    lang_data = {}
        else:
            lang_data = {}

        merge_dicts(en_data, lang_data, lang)

        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(lang_data, f, ensure_ascii=False, indent=4)
            
    print("Localization synchronization complete.")

if __name__ == "__main__":
    main()
