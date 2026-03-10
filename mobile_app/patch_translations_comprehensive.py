import json
import os

languages = ["bn", "en", "gu", "hi", "hi_en", "kn", "ml", "mr", "pa", "ta", "te"]
base_path = r"c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations"

# English base translations
base_keys = {
    "profile.bank_sbi": "State Bank of India",
    "profile.bank_axis": "Axis Bank",
    "profile.bank_icici": "ICICI Bank",
    "profile.bank_hdfc": "HDFC Bank",
    "profile.bank_unknown": "Unknown Bank",
    "profile.upi_id_label": "UPI ID",
    "profile.amount_label": "Amount",
    "profile.get_help": "Get help",
    "details.report_already_raised": "Complaint Already Raised",
    "details.report_already_msg": "You have already raised a complaint for this transaction. For further official action, please use the Cyber Crime portal.",
    "details.go_back": "Go Back",
    "details.continue_portal": "Continue to Cyber Crime Portal",
    "details.error_checking_complaint": "Error checking complaint status",
    "spending_limit.no_limit_title": "No Spending Limit Set",
    "spending_limit.no_limit_description": "Set a spending limit to track your expenses and stay on budget.",
    "spending_limit.set_limit_button": "Set Spending Limit",
    "spending_limit.cat_food": "Food & Drinks",
    "spending_limit.cat_shopping": "Shopping",
    "spending_limit.cat_transport": "Transport",
    "spending_limit.cat_bills": "Bills & Utilities",
    "spending_limit.cat_entertainment": "Entertainment",
    "spending_limit.cat_health": "Health",
    "spending_limit.cat_people": "People",
    "spending_limit.cat_education": "Education",
    "spending_limit.cat_investments": "Investments",
    "spending_limit.cat_others": "Others"
}

# Hindi translations
hi_keys = {
    "profile.bank_sbi": "भारतीय स्टेट बैंक",
    "profile.bank_axis": "एक्सिस बैंक",
    "profile.bank_icici": "आईसीआईसीआई बैंक",
    "profile.bank_hdfc": "एचडीएफसी बैंक",
    "profile.bank_unknown": "अज्ञात बैंक",
    "profile.upi_id_label": "UPI आईडी",
    "profile.amount_label": "राशि",
    "profile.get_help": "सहायता लें",
    "details.report_already_raised": "शिकायत पहले ही दर्ज की जा चुकी है",
    "details.report_already_msg": "आपने इस लेनदेन के लिए पहले ही शिकायत दर्ज कर दी है। आगे की आधिकारिक कार्रवाई के लिए, कृपया साइबर क्राइम पोर्टल का उपयोग करें।",
    "details.go_back": "वापस जाएं",
    "details.continue_portal": "साइबर क्राइम पोर्टल पर जारी रखें",
    "details.error_checking_complaint": "शिकायत की स्थिति जाँचने में त्रुटि",
    "spending_limit.no_limit_title": "कोई खर्च सीमा निर्धारित नहीं है",
    "spending_limit.no_limit_description": "अपने खर्चों को ट्रैक करने और बजट पर रहने के लिए एक खर्च सीमा निर्धारित करें।",
    "spending_limit.set_limit_button": "खर्च सीमा निर्धारित करें",
    "spending_limit.cat_food": "भोजन और पेय",
    "spending_limit.cat_shopping": "खरीदारी",
    "spending_limit.cat_transport": "परिवहन",
    "spending_limit.cat_bills": "बिल और उपयोगिताएँ",
    "spending_limit.cat_entertainment": "मनोरंजन",
    "spending_limit.cat_health": "स्वास्थ्य",
    "spending_limit.cat_people": "लोग",
    "spending_limit.cat_education": "शिक्षा",
    "spending_limit.cat_investments": "निवेश",
    "spending_limit.cat_others": "अन्य"
}

# Regional language overrides (optional, for quality)
# For others, we'll use original values from the previous script if available, 
# or fall back to English if totally missing.

for lang in languages:
    file_path = os.path.join(base_path, f"{lang}.json")
    if not os.path.exists(file_path):
        print(f"Skipping {lang}, file not found.")
        continue
    
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # Choose source for new keys
    source_keys = hi_keys if lang in ["hi", "hi_en"] else base_keys
    
    for key_path, value in source_keys.items():
        parts = key_path.split('.')
        curr = data
        for part in parts[:-1]:
            if part not in curr:
                curr[part] = {}
            curr = curr[part]
        
        # Only set if not already present or if it's one of our new keys
        curr[parts[-1]] = value
    
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    print(f"Patched {lang}.json")
