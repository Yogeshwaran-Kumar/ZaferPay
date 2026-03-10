import json
import os

langs = ['bn', 'en', 'gu', 'hi', 'hi_en', 'kn', 'ml', 'mr', 'ta', 'te']
base_path = r'c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations'

new_keys = {
    "common": {
        "powered_by": {
            "en": "Powered by ZaferPay",
            "ta": "ZaferPay மூலம் இயக்கப்படுகிறது",
            "hi": "ZaferPay द्वारा संचालित",
            "bn": "ZaferPay দ্বারা চালিত",
            "gu": "ZaferPay દ્વારા સંચાલિત",
            "kn": "ZaferPay ನಿಂದ ನಡೆಸಲ್ಪಡುತ್ತದೆ",
            "ml": "ZaferPay നിയന്ത്രിക്കുന്നത്",
            "mr": "ZaferPay द्वारे समर्थित",
            "te": "ZaferPay ద్వారా ఆధారితం",
            "hi_en": "Powered by ZaferPay"
        }
    },
    "history": {
        "title": { "en": "Transaction History", "ta": "பரிவர்த்தனை வரலாறு", "hi": "लेनदेन का इतिहास" },
        "search_hint": { "en": "Search here...", "ta": "இங்கே தேடுங்கள்...", "hi": "यहाँ खोजें..." },
        "show_more": { "en": "Show More", "ta": "மேலும் காண்க", "hi": "और देखें" },
        "no_transactions": { "en": "No transactions yet", "ta": "இன்னும் பரிவர்த்தனைகள் இல்லை", "hi": "अभी तक कोई लेनदेन नहीं" },
        "status_filter": { "en": "Status", "ta": "நிலை", "hi": "स्थिति" },
        "payment_type_filter": { "en": "Payment type", "ta": "கட்டண வகை", "hi": "भुगतान का प्रकार" },
        "amount_filter": { "en": "Amount", "ta": "தொகை", "hi": "राशि" },
        "apply": { "en": "Apply", "ta": "விண்ணப்பிக்கவும்", "hi": "लाங்கு करें" },
        "reset": { "en": "Reset", "ta": "மீட்டமை", "hi": "रीसेट" },
        "processing": { "en": "Processing", "ta": "செயலாக்கம்", "hi": "प्रसंस्करण" },
        "money_sent": { "en": "Money sent", "ta": "பணம் அனுப்பப்பட்டது", "hi": "पैसे भेजे गए" },
        "money_received": { "en": "Money received", "ta": "பணம் பெறப்பட்டது", "hi": "पैसे प्राप्त हुए" },
        "up_to": { "en": "Up to ₹{amount}", "ta": "₹{amount} வரை", "hi": "₹{amount} तक" },
        "above": { "en": "Above ₹{amount}", "ta": "₹{amount} க்கு மேல்", "hi": "₹{amount} से ऊपर" }
    },
    "money": {
        "title": { "en": "Money", "ta": "பணம்", "hi": "पैसा" },
        "available_balance": { "en": "Available Balance", "ta": "கிடைக்கக்கூடிய இருப்பு", "hi": "उपलब्ध शेष राशि" },
        "tap_view_balance": { "en": "Tap to view balance & spend analysis", "ta": "இருப்பு மற்றும் செலவு பகுப்பாய்வைப் பார்க்க தட்டவும்", "hi": "शेष राशि और व्यय विश्लेषण देखने के लिए टैप करें" },
        "load_failed": { "en": "Failed to load data", "ta": "தரவை ஏற்றுவதில் தோல்வி", "hi": "डेटा लोड करने में विफल" }
    },
    "analysis": {
        "comparison_more": { "en": "Spent {amount} more vs {month} this time", "ta": "இந்த முறை {month} ஐ விட ₹{amount} அதிகம் செலவிடப்பட்டுள்ளது", "hi": "इस बार {month} की तुलना में ₹{amount} अधिक खर्च हुए" },
        "comparison_less": { "en": "Spent {amount} less vs {month} this time", "ta": "இந்த முறை {month} ஐ விட ₹{amount} குறைவு செலவிடப்பட்டுள்ளது", "hi": "इस बार {month} की तुलना में ₹{amount} कम खर्च हुए" }
    },
    "spending_limit": {
        "title": { "en": "Spending Limit", "ta": "செலவு வரம்பு", "hi": "व्यय सीमा" },
        "daily": { "en": "Daily Limit", "ta": "தினசரி வரம்பு", "hi": "दैनिक सीमा" },
        "weekly": { "en": "Weekly Limit", "ta": "வாராந்திர வரம்பு", "hi": "साप्ताहिक सीमा" },
        "biweekly": { "en": "Bi-Weekly Limit", "ta": "இருவார வரம்பு", "hi": "पखवाड़ा सीमा" },
        "monthly": { "en": "Monthly Limit", "ta": "மாதாந்திர வரம்பு", "hi": "मासिक सीमा" },
        "on_track": { "en": "On Track", "ta": "சரியான பாதையில்", "hi": "सही रास्ते पर" },
        "nearing_limit": { "en": "Nearing Limit", "ta": "வரம்பை நெருங்குகிறது", "hi": "सीमा के करीब" },
        "almost_full": { "en": "Almost Full", "ta": "கிட்டத்தட்ட நிறைந்தது", "hi": "लगभग पूर्ण" },
        "limit_reached": { "en": "Limit Reached", "ta": "வரம்பு எட்டப்பட்டது", "hi": "सीमा समाप्त" },
        "set_spending_limit": { "en": "Set Spending Limit", "ta": "செலவு வரம்பை அமைக்கவும்", "hi": "व्यय सीमा निर्धारित करें" },
        "no_limit_set": { "en": "No Spending Limit Set", "ta": "செலவு வரம்பு எதுவும் அமைக்கப்படவில்லை", "hi": "कोई व्यय सीमा निर्धारित नहीं है" },
        "no_limit_desc": { "en": "Set a spending limit to track your expenses and stay on budget.", "ta": "உங்கள் செலவுகளைக் கண்காணிக்கவும் பட்ஜெட்டில் இருக்கவும் செலவு வரம்பை அமைக்கவும்.", "hi": "अपने खर्चों को ट्रैक करने और बजट में रहने के लिए व्यय सीमा निर्धारित करें।" },
        "enable_limit": { "en": "Enable Limit", "ta": "வரம்பைச் செயல்படுத்து", "hi": "सीमा सक्षम करें" },
        "amount_label": { "en": "Amount (₹)", "ta": "தொகை (₹)", "hi": "राशि (₹)" },
        "period": { "en": "Period", "ta": "காலம்", "hi": "अवधि" },
        "custom": { "en": "Custom...", "ta": "தனிப்பயன்...", "hi": "कस्टम..." },
        "custom_days_label": { "en": "Number of days (1 – 365)", "ta": "நாட்களின் எண்ணிக்கை (1 – 365)", "hi": "दिनों की संख्या (1 – 365)" },
        "days_suffix": { "en": "days", "ta": "நாட்கள்", "hi": "दिन" },
        "enter_amount_error": { "en": "Please enter a valid amount", "ta": "தயவுசெய்து செல்லுபடியாகும் தொகையை உள்ளிடவும்", "hi": "कृपया एक वैध राशि दर्ज करें" },
        "enter_period_error": { "en": "Please enter a valid period between 1 and 365 days", "ta": "தயவுசெய்து 1 முதல் 365 நாட்களுக்குள் செல்லுபடியாகும் காலத்தை உள்ளிடவும்", "hi": "कृपया 1 से 365 दिनों के बीच एक वैध अवधि दर्ज करें" },
        "limit_updated": { "en": "Spending limit updated!", "ta": "செலவு வரம்பு புதுப்பிக்கப்பட்டது!", "hi": "व्यय सीमा अपडेट की गई!" },
        "limit_removed": { "en": "Spending limit removed.", "ta": "செலவு வரம்பு நீக்கப்பட்டது.", "hi": "व्यय सीमा हटा दी गई।" },
        "spent": { "en": "Spent", "ta": "செலவிடப்பட்டது", "hi": "खर्च किया" },
        "remaining": { "en": "Remaining", "ta": "மீதமுள்ளது", "hi": "शेष" },
        "limit": { "en": "Limit", "ta": "வரம்பு", "hi": "सीमा" }
    },
    "profile": {
        "upi_circle_subtitle": { "en": "Manage shared limits & circle payments", "ta": "பகிரப்பட்ட வரம்புகள் மற்றும் வட்டக் கட்டணங்களை நிர்வகிக்கவும்", "hi": "साझा सीमाओं और सर्कल भुगतानों का प्रबंधन करें" },
        "kyc_details": { "en": "KYC Details", "ta": "KYC விவரங்கள்", "hi": "केवाईसी विवरण" },
        "kyc_details_subtitle": { "en": "Profile details & verification status", "ta": "சுயவிவர விவரங்கள் மற்றும் சரிபார்ப்பு நிலை", "hi": "प्रोफ़ाइल विवरण और सत्यापन स्थिति" }
    },
    "settings": {
        "summary_notifications": { "en": "Summary Notifications", "ta": "சுருக்க அறிவிப்புகள்", "hi": "सारांश सूचनाएं" },
        "frequency_daily": { "en": "Frequency: Daily", "ta": "அதிர்வெண்: தினசரி", "hi": "आवृत्ति: दैनिक" }
    }
}

# Simple translation helper for other languages (using English as fallback)
def get_val(section, key, lang):
    if lang in new_keys[section][key]:
        return new_keys[section][key][lang]
    return new_keys[section][key]['en']

for lang in langs:
    file_path = os.path.join(base_path, f'{lang}.json')
    if not os.path.exists(file_path):
        continue
        
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    for section, keys in new_keys.items():
        if section not in data:
            data[section] = {}
        for key in keys:
            data[section][key] = get_val(section, key, lang)
            
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)

print("Patch v8 applied successfully.")
