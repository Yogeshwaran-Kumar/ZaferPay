import json
import os

languages = ["bn", "en", "gu", "hi", "hi_en", "kn", "ml", "mr", "pa", "ta", "te"]
base_path = r"c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations"

# English base translations (used as fallback for keys not specifically translated)
en_keys = {
    "app_name": "ZaferPay",
    "details.sender_name": "Sender Name",
    "details.sender_upi": "Sender UPI ID",
    "details.receiver_name": "Receiver Name",
    "details.receiver_upi": "Receiver UPI ID",
    "details.txn_id_label": "Transaction ID",
    "details.txn_date": "Transaction Date",
    "details.txn_time": "Transaction Time",
    "details.sender_bank": "Sender Bank name",
    "details.receiver_bank": "Receiver Bank name",
    "details.pay_through": "Pay Through",
    "details.reason_label": "Reason for complaint",
    "details.select_reason": "Select a reason",
    "details.description": "Description",
    "details.optional": "Optional",
    "details.required": "Required",
    "details.fraud_txn": "Fraudulent Transaction",
    "details.unauthorized_txn": "Unauthorized Transaction",
    "details.service_not_received": "Service not received",
    "details.wrongly_sent": "Sent to wrong person",
    "details.select_reason_error": "Please select a reason for the complaint.",
    "details.other_reason_error": "Please provide a description when selecting \"Other\".",
    "details.identify_account_error": "Unable to identify the reported account.",
    "details.complaint_warning": "If you fill this, it will not be filed as a complaint in cyber crime. You must file manually in the cyber crime website after clicking the Submit Complaint button.",
    "analysis.available_balance": "Available balance",
    "analysis.top_spends": "Top Spends",
    "analysis.no_spends": "No spends this month yet.",
    "analysis.spend_analysis_for_month": "Your spend analysis for {month}",
    "analysis.category_personal": "Personal",
    "analysis.category_upi_circle": "UPI Circle",
    "common.powered_by": "Powered by ZaferPay",
    "money.title": "Money",
    "money.available_balance": "Available Balance",
    "money.tap_view_balance": "Tap to view balance & spend analysis",
    "money.load_failed": "Failed to load data",
    "history.title": "Transaction History",
    "history.show_more": "Show More",
    "history.no_transactions": "No transactions yet",
    "profile.bank_sbi": "State Bank of India",
    "profile.bank_axis": "Axis Bank",
    "profile.bank_icici": "ICICI Bank",
    "profile.bank_hdfc": "HDFC Bank",
    "profile.bank_unknown": "Unknown Bank",
}

# Regional Translations (focused on critical fraud/banking terms)
translations = {
    "ta": { # Tamil
        "details.fraud_txn": "மோசடி பரிவர்த்தனை",
        "details.unauthorized_txn": "அங்கீகரிக்கப்படாத பரிவர்த்தனை",
        "details.service_not_received": "சேவை கிடைக்கவில்லை",
        "details.wrongly_sent": "தவறான நபருக்கு அனுப்பப்பட்டது",
        "details.select_reason": "காரணத்தைத் தேர்ந்தெடுக்கவும்",
        "analysis.available_balance": "கிடைக்கக்கூடிய இருப்பு",
        "money.available_balance": "கிடைக்கக்கூடிய இருப்பு",
        "history.title": "பரிவர்த்தனை வரலாறு",
        "history.show_more": "மேலும் காண்க",
        "profile.bank_sbi": "ஸ்டேட் பேங்க் ஆஃப் இந்தியா",
        "profile.bank_hdfc": "எச்.டி.எஃப்.சி வங்கி",
        "profile.bank_icici": "ஐ.சி.ஐ.சி.ஐ வங்கி",
        "profile.bank_axis": "ஆக்சிஸ் வங்கி",
    },
    "hi": { # Hindi
        "details.fraud_txn": "धोखाधड़ी वाला लेनदेन",
        "details.unauthorized_txn": "अनधिकृत लेनदेन",
        "details.service_not_received": "सेवा प्राप्त नहीं हुई",
        "details.wrongly_sent": "गलत व्यक्ति को भेजा गया",
        "details.select_reason": "कारण चुनें",
        "analysis.available_balance": "उपलब्ध शेष राशि",
        "money.available_balance": "उपलब्ध शेष राशि",
        "history.title": "लेनदेन का इतिहास",
        "history.show_more": "अधिक दिखाएं",
        "profile.bank_sbi": "भारतीय स्टेट बैंक",
        "profile.bank_hdfc": "एचडीएफसी बैंक",
        "profile.bank_icici": "आईसीआईसीआई बैंक",
        "profile.bank_axis": "एक्सिस बैंक",
    },
    "te": { # Telugu
        "details.fraud_txn": "మోసపూరిత లావాదేవీ",
        "details.unauthorized_txn": "అనధికారిక లావాదేవీ",
        "details.service_not_received": "సేవ అందలేదు",
        "details.wrongly_sent": "తప్పు వ్యక్తికి పంపబడింది",
        "analysis.available_balance": "అందుబాటులో ఉన్న నిల్వ",
        "money.available_balance": "అందుబాటులో ఉన్న నిల్వ",
        "history.title": "లావాదేవీల చరిత్ర",
    },
    "kn": { # Kannada
        "details.fraud_txn": "ಮೋಸದ ವಹಿವಾಟು",
        "details.unauthorized_txn": "ಅನಧಿಕೃತ ವಹಿವಾಟು",
        "details.service_not_received": "ಸೇವೆ ಸ್ವೀಕರಿಸಿಲ್ಲ",
        "analysis.available_balance": "ಲಭ್ಯವಿರುವ ಬಾಕಿ",
        "money.available_balance": "ಲಭ್ಯವಿರುವ ಬಾಕಿ",
        "history.title": "ವಹಿವಾಟಿನ ಇತಿಹಾಸ",
    },
    "ml": { # Malayalam
        "details.fraud_txn": "വ്യാജ ഇടപാട്",
        "details.unauthorized_txn": "അനധികൃത ഇടപാട്",
        "details.service_not_received": "സേവനം ലഭിച്ചില്ല",
        "analysis.available_balance": "ലഭ്യമായ ബാലൻസ്",
        "money.available_balance": "ലഭ്യമായ ബാലൻസ്",
        "history.title": "ഇടപാട് ചരിത്രം",
    },
    "gu": { # Gujarati
        "details.fraud_txn": "છેતરપિંડીભર્યો વ્યવહાર",
        "details.unauthorized_txn": "અનધિકૃત વ્યવહાર",
        "details.service_not_received": "સેવા મળી નથી",
        "analysis.available_balance": "ઉપલબ્ધ બેલેન્સ",
        "money.available_balance": "ઉપલબ્ધ બેલેన్స్",
        "history.title": "વ્યવહારોનો ઇતિહાસ",
    },
    "mr": { # Marathi
        "details.fraud_txn": "फसवे व्यवहार",
        "details.unauthorized_txn": "अनधिकृत व्यवहार",
        "details.service_not_received": "सेवा मिळाली नाही",
        "analysis.available_balance": "उपलब्ध शिल्लक",
        "money.available_balance": "उपलब्ध शिल्लक",
        "history.title": "व्यवहारांचा इतिहास",
    },
    "bn": { # Bengali
        "details.fraud_txn": "প্রতারণামূলক লেনদেন",
        "details.unauthorized_txn": "অননুমোদিত লেনদেন",
        "details.service_not_received": "সেবা গ্রহণ করা হয়নি",
        "analysis.available_balance": "বর্তমান স্থিতিশীলতা",
        "money.available_balance": "বর্তমান স্থিতিশীলता",
        "history.title": "লেনদেনের ইতিহাস",
    },
    "pa": { # Punjabi
        "details.fraud_txn": "ਧੋਖਾਧੜੀ ਵਾਲਾ ਲੈਣ-ਦੇਣ",
        "details.unauthorized_txn": "ਅਣਅਧਿਕਾਰਤ ਲੈਣ-ਦੇਣ",
        "details.service_not_received": "ਸੇਵਾ ਪ੍ਰਾਪਤ ਨਹੀਂ ਹੋਈ",
        "analysis.available_balance": "ਉਪਲਬਧ ਬਕਾਇਆ",
        "money.available_balance": "ਉਪਲਬਧ ਬਕਾਇਆ",
        "history.title": "ਲੈਣ-ਦੇਣ ਦਾ ਇਤਿਹਾਸ",
    }
}

for lang in languages:
    file_path = os.path.join(base_path, f"{lang}.json")
    if not os.path.exists(file_path):
        print(f"Skipping {lang}, file not found.")
        continue
    
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # Apply English base first for all missing keys
    for key_path, value in en_keys.items():
        parts = key_path.split('.')
        curr = data
        for part in parts[:-1]:
            if part not in curr:
                curr[part] = {}
            curr = curr[part]
        
        # Only set if not already present or if it's one of our target keys (forcing update)
        if parts[-1] not in curr or lang == 'en':
            curr[parts[-1]] = value
            
    # Apply specific regional translations if available
    if lang in translations:
        for key_path, value in translations[lang].items():
            parts = key_path.split('.')
            curr = data
            for part in parts[:-1]:
                if part not in curr:
                    curr[part] = {}
                curr = curr[part]
            curr[parts[-1]] = value
            
    # For hi_en (Hinglish), use Hindi translations but keep numbers/keys recognizable
    if lang == "hi_en":
         # Optionally copy hi keys to hi_en if they don't exist
         pass

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    print(f"Patched {lang}.json")

print("\nLocalization Update Complete!")
