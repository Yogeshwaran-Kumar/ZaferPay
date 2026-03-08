import json
import os

languages = ["bn", "en", "gu", "hi", "hi_en", "kn", "ml", "mr", "pa", "ta", "te"]
base_path = r"c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations"

# Comprehensive list of keys needed for the Payment/Shield/Result flow
critical_keys = {
    "processing": {
        "verifying_integrity": "Verifying Integrity...",
        "securing_processing": "Securing & Processing...",
        "processing_payment": "Processing Payment...",
        "processing_approval": "Processing Approval...",
        "waiting_parent": "Waiting for Parent Approval...",
        "txn_processed_after": "Transaction will be processed once approved",
        "cancel_request": "Cancel Request"
    },
    "results": {
        "payment_successful": "Payment Successful",
        "security_risk_detected": "Security Risk Detected",
        "transaction_blocked": "Transaction Blocked",
        "payment_failed": "Payment Failed",
        "approval_required": "Approval Required",
        "safe_and_secure": "Safe & Secure",
        "unusual_activity_warn": "Warning: Unusual Activity",
        "result_unsafe": "Result: Unsafe",
        "done": "Done",
        "ok": "OK",
        "close_retry": "Close / Retry",
        "parent_approved": "Parent approved your payment.",
        "parent_declined": "Parent declined the request.",
        "request_cancelled": "Request was cancelled.",
        "device_integrity_failed": "Device Integrity Failed",
        "security_check": "Security Check"
    },
    "details": {
        "to": "To",
        "txn_id": "Transaction ID"
    },
    "security_alerts": {
        "on_call_title": "Security Block",
        "on_call_desc": "For your safety, payments are disabled while you are on an active phone call to prevent potential scams.",
        "got_it": "Got it",
        "permission_required": "Security Permission Required",
        "permission_desc": "To protect you from fraudulent calls, Safe Pay needs permission to detect if you are on a call during payments.\n\nPlease grant the Phone permission to proceed.",
        "open_settings": "Open Settings"
    }
}

# Regional translations for the most visible strings
regional_patches = {
    "ta": { # Tamil
        "processing": {
            "verifying_integrity": "ஒருமைப்பாட்டைச் சரிபார்க்கிறது...",
            "securing_processing": "பாதுகாத்தல் மற்றும் செயலாக்குதல்...",
            "processing_payment": "பணம் செலுத்துதல் செயலாக்கப்படுகிறது...",
            "processing_approval": "அங்கீகாரம் செயலாக்கப்படுகிறது...",
            "waiting_parent": "பெற்றோரின் அங்கீகாரத்திற்காக காத்திருக்கிறது...",
            "txn_processed_after": "அங்கீகரிக்கப்பட்டதும் பரிவர்த்தனை செயலாக்கப்படும்",
            "cancel_request": "கோரிக்கையை ரத்துசெய்"
        },
        "results": {
            "payment_successful": "பணம் செலுத்துதல் வெற்றி",
            "security_risk_detected": "பாதுகாப்பு ஆபத்து கண்டறியப்பட்டது",
            "transaction_blocked": "பரிவர்த்தனை தடுக்கப்பட்டது",
            "payment_failed": "பணம் செலுத்துதல் தோல்வி",
            "approval_required": "அங்கீகாரம் தேவை",
            "safe_and_secure": "பாதுகாப்பானது",
            "security_check": "பாதுகாப்பு சோதனை",
            "done": "முடிந்தது",
            "ok": "சரி"
        },
        "details": {
            "to": "பெறுநர்"
        }
    },
    "hi": { # Hindi
        "processing": {
            "verifying_integrity": "सत्यनिष्ठा की जाँच की जा रही है...",
            "securing_processing": "सुरक्षित और प्रसंस्करण...",
            "processing_payment": "भुगतान संसाधित किया जा रहा है...",
            "processing_approval": "अनुमोदन संसाधित किया जा रहा है...",
            "waiting_parent": "अभिभावक की स्वीकृति का इंतज़ार है...",
            "txn_processed_after": "अनुमोदित होने के बाद लेनदेन संसाधित किया जाएगा",
            "cancel_request": "अनुरोध रद्द करें"
        },
        "results": {
            "payment_successful": "भुगतान सफल रहा",
            "security_risk_detected": "सुरक्षा जोखिम का पता चला",
            "transaction_blocked": "लेनदेन अवरुद्ध",
            "payment_failed": "भुगतान विफल",
            "approval_required": "अनुमोदन आवश्यक",
            "safe_and_secure": "सुरक्षित",
            "security_check": "सुरक्षा जाँच",
            "done": "हो गया",
            "ok": "ठीक"
        },
        "details": {
            "to": "को"
        }
    },
    "te": { # Telugu
        "processing": {
            "verifying_integrity": "సమగ్రతను తనిఖీ చేస్తోంది...",
            "securing_processing": "భద్రపరచడం మరియు ప్రాసెస్ చేయడం...",
            "processing_payment": "చెల్లింపు ప్రాసెస్ చేయబడుతోంది...",
            "cancel_request": "అభ్యర్థనను రద్దు చేయండి"
        },
        "results": {
            "payment_successful": "చెల్లింపు విజయవంతమైంది",
            "security_risk_detected": "భద్రతా ప్రమాదం కనుగొనబడింది",
            "transaction_blocked": "లావాదేవీ నిరోధించబడింది",
            "payment_failed": "చెల్లింపు విఫలమైంది",
            "security_check": "భద్రతా తనిఖీ",
            "done": "పూర్తయింది"
        },
        "details": {
            "to": "కు"
        }
    }
}

for lang in languages:
    file_path = os.path.join(base_path, f"{lang}.json")
    if not os.path.exists(file_path):
        continue
    
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # 1. Apply baseline English for all critical keys
    for section, keys in critical_keys.items():
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
    print(f"Propagated critical keys to {lang}.json")

print("\nFinal Localization Patch Applied!")
