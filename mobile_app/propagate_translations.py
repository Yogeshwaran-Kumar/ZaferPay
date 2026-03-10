import os
import json
import copy

def propagate_translations():
    base_dir = r"c:\Users\dhanu\Downloads\Safe Pay\mobile_app\assets\translations"
    en_path = os.path.join(base_dir, "en.json")
    
    with open(en_path, 'r', encoding='utf-8') as f:
        en_data = json.load(f)

    # New translations mapping (as defined in the implementation plan)
    translations = {
        "hi": {
            "home.cannot_pay_self": "खुद को पैसे नहीं भेज सकते",
            "scan.my_qr_tab": "मेरा QR",
            "scan.upload_gallery": "गैलरी से अपलोड करें",
            "scan.open_scanner_btn": "स्कैनर खोलें",
            "scan.share_qr_btn": "QR कोड साझा करें",
            "scan.low_light": "कम रोशनी मिली",
            "contacts.pay_btn": "भुगतान करें",
            "contacts.invite_btn": "आमंत्रित करें",
            "contacts.grant_permission_msg": "संपर्क देखने के लिए अनुमति दें",
            "contacts.grant_permission_btn": "अनुमति दें",
            "contacts.no_contacts": "कोई संपर्क नहीं मिला",
            "contacts.no_phone": "कोई फोन नहीं",
            "details.request_withdrawn": "अनुरोध वापस लिया गया",
            "details.withdraw_failed": "अनुरोध वापस लेने में विफल",
            "details.sender_name": "भेजने वाले का नाम",
            "details.sender_upi": "भेजने वाले की UPI ID",
            "details.receiver_name": "प्राप्तकर्ता का नाम",
            "details.receiver_upi": "प्राप्तकर्ता की UPI ID",
            "details.txn_id_label": "लेनदेन ID",
            "details.txn_date": "लेनदेन की तिथि",
            "details.txn_time": "लेनदेन का समय",
            "details.sender_bank": "भेजने वाले का बैंक",
            "details.receiver_bank": "प्राप्तकर्ता का बैंक",
            "details.pay_through": "भुगतान का माध्यम",
            "details.reason_label": "शिकायत का कारण",
            "details.select_reason": "कारण चुनें",
            "details.description": "विवरण",
            "details.optional": "वैकल्पিক",
            "details.required": "अनिवार्य",
            "details.complaint_warning": "यदि आप इसे भरতে हैं, तो इसे साइबर अपराध में शिकायत के रूप में दर्ज नहीं किया जाएगा। आपको सबमिट शिकायत बटन पर क्लिक करने के बाद साइबर अपराध वेबसाइट पर मैन्युअल रूप से दर्ज करना होगा।",
            "details.submit_complaint": "शिकायत दर्ज करें",
            "details.complaint_success": "शिकायत सफलतापूर्वक\nदर्ज की गई!",
            "details.complaint_success_msg": "आपकी शिकायत ZaferPay को भेज दी गई है। अब आपको आधिकारिक रिपोर्ट दर्ज करने के लिए साइबर अपराध पोर्टल पर भेज दिया जाएगा।",
            "details.error_generic": "एक त्रुटि हुई। कृपया पुन: प्रयास करें।",
            "details.select_reason_error": "कृपया शिकायत का कारण चुनें।",
            "details.other_reason_error": "कृपया 'अन्य' चुनते समय एक विवरण प्रदान करें।",
            "details.identify_account_error": "रिपोर्ट किए गए खाते की पहचान करने में असमर्थ।"
        },
        "ta": {
            "home.cannot_pay_self": "உங்களுக்கு நீங்களே பணம் அனுப்ப முடியாது",
            "scan.my_qr_tab": "எனது QR",
            "scan.upload_gallery": "கேலரியில் இருந்து பதிવેற்றவும்",
            "scan.open_scanner_btn": "ஸ்கேனரைத் திற",
            "scan.share_qr_btn": "QR குறியீட்டைப் பகிர்க",
            "scan.low_light": "குறைந்த ஒளி கண்டறியப்பட்டது",
            "contacts.pay_btn": "செலுத்து",
            "contacts.invite_btn": "அழைப்பு",
            "contacts.grant_permission_msg": "தொடர்புகளைப் பார்க்க அனுமதி வழங்கவும்",
            "contacts.grant_permission_btn": "அனுமதி வழங்கு",
            "contacts.no_contacts": "தொடர்புகள் எதுவும் இல்லை",
            "contacts.no_phone": "தொலைபேசி எண் இல்லை",
            "details.request_withdrawn": "கோரிக்கை திரும்பப் பெறப்பட்டது",
            "details.withdraw_failed": "கோரிக்கையைத் திரும்பப் பெறுவதில் தோல்வி",
            "details.sender_name": "அनुப்புநர் பெயர்",
            "details.sender_upi": "அనుப்புநர் UPI ID",
            "details.receiver_name": "பெறுநர் பெயர்",
            "details.receiver_upi": "பெறுநர் UPI ID",
            "details.txn_id_label": "பரிவர்த்தனை ID",
            "details.txn_date": "பரிவர்த்தனை தேதி",
            "details.txn_time": "பரிவர்த்தனை நேரம்",
            "details.sender_bank": "அனுப்புநர் வங்கி பெயர்",
            "details.receiver_bank": "பெறுநர் வங்கி பெயர்",
            "details.pay_through": "இதன் மூலம் செலுத்தவும்",
            "details.reason_label": "புகாருக்கான காரணம்",
            "details.select_reason": "ஒரு காரணத்தைத் தேர்ந்தெடுக்கவும்",
            "details.description": "விளக்கம்",
            "details.optional": "விருப்பமானது",
            "details.required": "கட்டாயமானது",
            "details.complaint_warning": "இதை நீங்கள் நிரப்பினால், அது சைபர் குற்றத்தில் புகாராக பதிவு செய்யப்படாது. புகார் சமர்ப்பி பொத்தானைக் கிளிக் செய்த பிறகு சைபர் குற்ற இணையதளத்தில் கைமுறையாக பதிவு செய்ய வேண்டும்.",
            "details.submit_complaint": "புகாரைச் சமர்ப்பிக்கவும்",
            "details.complaint_success": "புகார் வெற்றிகரமாக\nசமர்ப்பிக்கப்பட்டது!",
            "details.complaint_success_msg": "உங்கள் புகார் ZaferPay இல் சமர்ப்பிக்கப்பட்டுள்ளது. அதிகாரப்பூர்வ அறிக்கையைத் தாக்கல் செய்ய நீங்கள் இப்போது சைபர் குற்றப் போர்ட்டலுக்குத் திருப்பி விடப்படுவீர்கள்.",
            "details.error_generic": "பிழை ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.",
            "details.select_reason_error": "புகாருக்கான காரணத்தைத் தேர்ந்தெடுக்கவும்.",
            "details.other_reason_error": " 'இதர' என்பதைத் தேர்ந்தெடுக்கும்போது விளக்கத்தை வழங்கவும்.",
            "details.identify_account_error": "புகாரளிக்கப்பட்ட கணக்கை அடையாளம் காண முடியவில்லை."
        },
        "pa": {
            "home.cannot_pay_self": "ਆਪਣੇ ਆਪ ਨੂੰ ਪੈਸੇ ਨਹੀਂ ਭੇਜ ਸਕਦੇ",
            "scan.my_qr_tab": "ਮੇਰਾ QR",
            "scan.upload_gallery": "ਗੈਲਰੀ ਤੋਂ ਅਪਲੋਡ ਕਰੋ",
            "scan.open_scanner_btn": "ਸਕੈਨਰ ਖੋਲ੍ਹੋ",
            "scan.share_qr_btn": "QR ਕੋਡ ਸਾਂਝਾ ਕਰੋ",
            "scan.low_light": "ਘੱਟ ਰੋਸ਼ਨੀ ਮਿਲੀ",
            "contacts.pay_btn": "ਭੁਗਤਾਨ ਕਰੋ",
            "contacts.invite_btn": "ਸੱਦਾ ਦਿਓ",
            "contacts.grant_permission_msg": "ਸੰਪਰਕ ਦੇਖਣ ਲਈ ਕਿਰਪਾ ਕਰਕੇ ਇਜਾਜ਼ਤ ਦਿਓ",
            "contacts.grant_permission_btn": "ਇਜਾਜ਼ਤ ਦਿਓ",
            "contacts.no_contacts": "ਕੋਈ ਸੰਪਰਕ ਨਹੀਂ ਮਿਲਿਆ",
            "contacts.no_phone": "ਕੋਈ ਫ਼ੋਨ ਨਹੀਂ",
            "details.request_withdrawn": "ਬੇਨਤੀ ਵਾਪਸ ਲੈ ਲਈ ਗਈ",
            "details.withdraw_failed": "ਬੇਨਤੀ ਵਾਪਸ ਲੈਣ ਵਿੱਚ ਅਸਫਲ",
            "details.sender_name": "ਭੇਜਣ ਵਾਲੇ ਦਾ ਨਾਮ",
            "details.sender_upi": "ਭੇਜਣ ਵਾਲੇ ਦੀ UPI ID",
            "details.receiver_name": "ਪ੍ਰਾਪਤਕਰਤਾ ਦਾ ਨਾਮ",
            "details.receiver_upi": "ਪ੍ਰਾਪਤਕਰਤਾ ਦੀ UPI ID",
            "details.txn_id_label": "ਲੈਣ-ਦੇਣ ID",
            "details.txn_date": "ਲੈਣ-ਦੇਣ ਦੀ ਮਿਤੀ",
            "details.txn_time": "ਲੈਣ-ਦੇਣ ਦਾ ਸਮਾਂ",
            "details.sender_bank": "ਭੇਜਣ ਵਾਲੇ ਦਾ ਬੈਂਕ",
            "details.receiver_bank": "ਪ੍ਰਾਪਤਕਰਤਾ ਦਾ ਬੈਂਕ",
            "details.pay_through": "ਭੁਗਤਾਨ ਦਾ ਮਾਧਿਅਮ",
            "details.reason_label": "ਸ਼ਿਕਾਇਤ ਦਾ ਕਾਰਨ",
            "details.select_reason": "ਕਾਰਨ ਚੁਣੋ",
            "details.description": "ਵੇਰਵਾ",
            "details.optional": "ਵਿਕਲਪਿਕ",
            "details.required": "ਜ਼ਰੂਰੀ",
            "details.complaint_warning": "ਜੇਕਰ ਤੁਸੀਂ ਇਸਨੂੰ ਭਰਦੇ ਹੋ, ਤਾਂ ਇਹ ਸਾਈਬਰ ਕ੍ਰਾਈਮ ਵਿੱਚ ਸ਼ਿਕਾਇਤ ਵਜੋਂ ਦਰਜ ਨਹੀਂ ਕੀਤਾ ਜਾਵੇਗਾ। ਤੁਹਾਨੂੰ ਸ਼ਿਕਾਇਤ ਸਪੁਰਦ ਕਰੋ ਬਟਨ 'ਤੇ ਕਲਿੱਕ ਕਰਨ ਤੋਂ ਬਾਅਦ ਸਾਈਬਰ ਕ੍ਰਾਈਮ ਵੈੱਬਸਾਈਟ 'ਤੇ ਖੁਦ ਦਰਜ ਕਰਨਾ ਹੋਵੇਗਾ।",
            "details.submit_complaint": "ਸ਼ਿਕਾਇਤ ਦਰਜ ਕਰੋ",
            "details.complaint_success": "ਸ਼ਿਕਾਇਤ ਸਫਲਤਾਪੂਰਵਕ\nਦਰਜ ਕੀਤੀ ਗਈ!",
            "details.complaint_success_msg": "ਤੁਹਾਡੀ ਸ਼ਿਕਾਇਤ ZaferPay ਨੂੰ ਭੇਜ ਦਿੱਤੀ ਗਈ ਹੈ। ਹੁਣ ਤੁਹਾਨੂੰ ਅਧਿਕਾਰਤ ਰਿਪੋਰਟ ਦਰਜ ਕਰਨ ਲਈ ਸਾਈਬਰ ਕ੍ਰਾਈਮ ਪੋਰਟਲ 'ਤੇ ਭੇਜ ਦਿੱਤਾ ਜਾਵੇਗਾ।",
            "details.error_generic": "ਇੱਕ ਗਲਤੀ ਹੋਈ। ਕਿਰਪਾ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।",
            "details.select_reason_error": "ਕਿਰਪਾ ਕਰਕੇ ਸ਼ਿਕਾਇਤ ਦਾ ਕਾਰਨ ਚੁਣੋ।",
            "details.other_reason_error": "ਕਿਰਪਾ ਕਰਕੇ 'ਹੋਰ' ਚੁਣਨ ਵੇਲੇ ਵੇਰਵਾ ਪ੍ਰਦਾਨ ਕਰੋ।",
            "details.identify_account_error": "ਰਿਪੋਰਟ ਕੀਤੇ ਖਾਤੇ ਦੀ ਪਛਾਣ ਕਰਨ ਵਿੱਚ ਅਸਮਰਥ।"
        },
        "bn": {
            "home.cannot_pay_self": "নিজেকে টাকা পাঠানো যাবে না",
            "scan.my_qr_tab": "আমার QR",
            "scan.upload_gallery": "গ্যালারি থেকে আপলোড করুন",
            "scan.open_scanner_btn": "স্ক্যানার খুলুন",
            "scan.share_qr_btn": "QR কোড শেয়ার করুন",
            "scan.low_light": "কম আলো সনাক্ত করা হয়েছে",
            "contacts.pay_btn": "প্রদান করুন",
            "contacts.invite_btn": "আমন্ত্রণ জানান",
            "contacts.grant_permission_msg": "পরিচিতি দেখতে দয়া করে অনুমতি দিন",
            "contacts.grant_permission_btn": "অনুমতি দিন",
            "contacts.no_contacts": "কোন পরিচিতি পাওয়া যায়নি",
            "details.request_withdrawn": "অনুরোধ প্রত্যাহার করা হয়েছে",
            "details.withdraw_failed": "অনুরোধ প্রত্যাহার করতে ব্যর্থ",
            "details.sender_name": "প্রেরকের নাম",
            "details.sender_upi": "প্রেরকের UPI ID",
            "details.receiver_name": "প্রাপকের নাম",
            "details.receiver_upi": "প্রাপকের UPI ID",
            "details.txn_id_label": "লেনদেন ID",
            "details.txn_date": "লেনদেনের তারিখ",
            "details.txn_time": "লেনদেনের সময়",
            "details.sender_bank": "প্রেরকের ব্যাংকের নাম",
            "details.receiver_bank": "প্রাপকের ব্যাংকের নাম",
            "details.pay_through": "পেমেন্ট মাধ্যম",
            "details.reason_label": "অভিযোগের কারণ",
            "details.select_reason": "একটি কারণ নির্বাচন করুন",
            "details.description": "বিবরণ",
            "details.optional": "ঐচ্ছিক",
            "details.required": "আবশ্যক",
            "details.complaint_warning": "আপনি যদি এটি পূরণ করেন তবে এটি সাইবার ক্রাইমে অভিযোগ হিসাবে দায়ের করা হবে না। সাবমিট অভিযোগ বাটনে ক্লিক করার পর আপনাকে সাইবার ক্রাইম ওয়েবসাইটে ম্যানুয়ালি ফাইল করতে হবে।",
            "details.submit_complaint": "অভিযোগ জমা দিন",
            "details.complaint_success": "অভিযোগ সফলভাবে\nজমা দেওয়া হয়েছে!",
            "details.complaint_success_msg": "আপনার অভিযোগ ZaferPay-এ জমা দেওয়া হয়েছে। এখন একটি অফিসিয়াল রিপোর্ট দায়ের করার জন্য আপনাকে সাইবার ক্রাইম পোর্টালে পাঠানো হবে।",
            "details.error_generic": "একটি ত্রুটি ঘটেছে। অনুগ্রহ করে আবার চেষ্টা করুন।",
            "details.select_reason_error": "অনুগ্রহ করে অভিযোগের একটি কারণ নির্বাচন করুন।",
            "details.other_reason_error": " 'অন্যান্য' নির্বাচন করার সময় একটি বিবরণ প্রদান করুন।",
            "details.identify_account_error": "রিপোর্ট করা অ্যাকাউন্টটি সনাক্ত করতে অক্ষম।"
        },
        "ta": {
            "home.cannot_pay_self": "உங்களுக்கு நீங்களே பணம் அனுப்ப முடியாது",
            "scan.my_qr_tab": "எனது QR",
            "scan.upload_gallery": "கேலரியில் இருந்து பதிவேற்றவும்",
            "scan.open_scanner_btn": "ஸ்கேனரைத் திற",
            "scan.share_qr_btn": "QR குறியீட்டைப் பகிர்க",
            "scan.low_light": "குறைந்த ஒளி கண்டறியப்பட்டது",
            "contacts.pay_btn": "செலுத்து",
            "contacts.invite_btn": "அழைப்பு",
            "contacts.grant_permission_msg": "தொடர்புகளைப் பார்க்க அனுமதி வழங்கவும்",
            "contacts.grant_permission_btn": "அனுமதி வழங்கு",
            "contacts.no_contacts": "தொடர்புகள் எதுவும் இல்லை",
            "contacts.no_phone": "தொலைபேசி எண் இல்லை",
            "details.request_withdrawn": "கோரிக்கை திரும்பப் பெறப்பட்டது",
            "details.withdraw_failed": "கோரிக்கையைத் திரும்பப் பெறுவதில் தோல்வி"
        },
        "ml": {
            "home.cannot_pay_self": "സ്വയം പണം അയക്കാൻ കഴിയില്ല",
            "scan.my_qr_tab": "എന്റെ QR",
            "scan.upload_gallery": "ഗാലറിയിൽ നിന്ന് അപ്‌ലോഡ് ചെയ്യുക",
            "scan.open_scanner_btn": "സ്കാനർ തുറക്കുക",
            "scan.share_qr_btn": "QR കോഡ് പങ്കിടുക",
            "scan.low_light": "കുറഞ്ഞ വെളിച്ചം കണ്ടെത്തി",
            "contacts.pay_btn": "പണമടയ്ക്കുക",
            "contacts.invite_btn": "ക്ഷണിക്കുക",
            "contacts.grant_permission_msg": "കോൺടാക്റ്റുകൾ കാണുന്നതിന് അനുമതി നൽകുക",
            "contacts.grant_permission_btn": "അനുമതി നൽകുക",
            "contacts.no_contacts": "കോൺടാക്റ്റുകളൊന്നും കണ്ടെത്തിയില്ല",
            "contacts.no_phone": "ഫോൺ ഇല്ല",
            "details.request_withdrawn": "അഭ്യർത്ഥന പിൻവലിച്ചു",
            "details.withdraw_failed": "അഭ്യർത്ഥന പിൻവലിക്കുന്നതിൽ പരാജയപ്പെട്ടു"
        },
        "kn": {
            "home.cannot_pay_self": "ನಿಮಗೆ ನೀವೇ ಹಣ ಕಳುಹಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ",
            "scan.my_qr_tab": "ನನ್ನ QR",
            "scan.upload_gallery": "ಗ್ಯಾಲರಿಯಿಂದ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ",
            "scan.open_scanner_btn": "ಸ್ಕ್ಯಾನರ್ ತೆರೆಯಿರಿ",
            "scan.share_qr_btn": "QR ಕೋಡ್ ಹಂಚಿಕೊಳ್ಳಿ",
            "scan.low_light": "ಕಡಿಮೆ ಬೆಳಕು ಪತ್ತೆಯಾಗಿದೆ",
            "contacts.pay_btn": "ಪಾವತಿಸಿ",
            "contacts.invite_btn": "ಆಹ್ವಾನಿಸಿ",
            "contacts.grant_permission_msg": "ಸಂಪರ್ಕಗಳನ್ನು ವೀಕ್ಷಿಸಲು ದಯವಿಟ್ಟು ಅನುಮತಿ ನೀಡಿ",
            "contacts.grant_permission_btn": "ಅನುಮತಿ ನೀಡಿ",
            "contacts.no_contacts": "ಯಾವುದೇ ಸಂಪರ್ಕಗಳು ಕಂಡುಬಂದಿಲ್ಲ",
            "contacts.no_phone": "ಫೋನ್ ಇಲ್ಲ",
            "details.request_withdrawn": "ವಿನಂತಿಯನ್ನು ಹಿಂಪಡೆಯಲಾಗಿದೆ",
            "details.withdraw_failed": "ವಿನಂತಿಯನ್ನು ಹಿಂಪಡೆಯಲು ವಿಫಲವಾಗಿದೆ"
        },
        "te": {
            "home.cannot_pay_self": "మీకు మీరే డబ్బు పంపలేరు",
            "scan.my_qr_tab": "నా QR",
            "scan.upload_gallery": "గ్యాలరీ నుండి అప్‌లోడ్ చేయండి",
            "scan.open_scanner_btn": "స్కానర్‌ని తెరువు",
            "scan.share_qr_btn": "QR కోడ్‌ని షేర్ చేయండి",
            "scan.low_light": "తక్కువ వెలుతురు కనుగొనబడింది",
            "contacts.pay_btn": "చెల్లించండి",
            "contacts.invite_btn": "ఆహ్వಾನించండి",
            "contacts.grant_permission_msg": "పరిచయాలను చూడటానికి దయచేసి అనుమతి ఇవ్వండి",
            "contacts.grant_permission_btn": "అనుమతి ఇవ్వండి",
            "contacts.no_contacts": "పరిచయాలు కనుగొనబడలేదు",
            "contacts.no_phone": "ఫోన్ లేదు",
            "details.request_withdrawn": "అభ్యర్థన ఉపసంహరించబడింది",
            "details.withdraw_failed": "అభ్యర్థనను ఉపసంహరించుకోవడం విఫలమైంది"
        },
        "mr": {
            "home.cannot_pay_self": "स्वतःला पैसे पाठवू शकत नाही",
            "scan.my_qr_tab": "माझा QR",
            "scan.upload_gallery": "गॅलरीमधून अपलोड करा",
            "scan.open_scanner_btn": "स्कॅनर उघडा",
            "scan.share_qr_btn": "QR कोड शेअर करा",
            "scan.low_light": "कमी प्रकाश आढळला",
            "contacts.pay_btn": "पैसे द्या",
            "contacts.invite_btn": "आमंत्रित करा",
            "contacts.grant_permission_msg": "संपर्क पाहण्यासाठी कृपया परवानगी द्या",
            "contacts.grant_permission_btn": "परवानगी द्या",
            "contacts.no_contacts": "कोणतेही संपर्क सापडले नाहीत",
            "contacts.no_phone": "फोन नाही",
            "details.request_withdrawn": "विनंती मागे घेतली",
            "details.withdraw_failed": "विनंती मागे घेण्यात अपयश"
        },
        "gu": {
            "home.cannot_pay_self": "સ્વતંત્રને પૈસા મોકલી શકાતા નથી",
            "scan.my_qr_tab": "મારો QR",
            "scan.upload_gallery": "ગેલેરીમાંથી અપલોડ કરો",
            "scan.open_scanner_btn": "સ્કેનર ખોલો",
            "scan.share_qr_btn": "QR કોડ શેર કરો",
            "scan.low_light": "ઓછો પ્રકાશ મળ્યો",
            "contacts.pay_btn": "ચૂકવો",
            "contacts.invite_btn": "આમંત્રણ આપો",
            "contacts.grant_permission_msg": "સંપર્કો જોવા માટે કૃપા કરીને પરવાનગી આપો",
            "contacts.grant_permission_btn": "પરવાનગી આપો",
            "contacts.no_contacts": "કોઈ સંપર્કો મળ્યા નથી",
            "contacts.no_phone": "ફોન નથી",
            "details.request_withdrawn": "વિનંતી પાછી ખેંચી લેવામાં આવી",
            "details.withdraw_failed": "વિનંتی પાછી ખેંચવામાં નિષ્ફળ"
        },
        "bn": {
            "home.cannot_pay_self": "নিজেকে টাকা পাঠানো যাবে না",
            "scan.my_qr_tab": "আমার QR",
            "scan.upload_gallery": "গ্যালারি থেকে আপলোড করুন",
            "scan.open_scanner_btn": "স্ক্যানার খুলুন",
            "scan.share_qr_btn": "QR কোড শেয়ার করুন",
            "scan.low_light": "কম আলো সনাক্ত করা হয়েছে",
            "contacts.pay_btn": "প্রদান করুন",
            "contacts.invite_btn": "আমন্ত্রণ জানান",
            "contacts.grant_permission_msg": "পরিচিতি দেখতে দয়া করে অনুমতি দিন",
            "contacts.grant_permission_btn": "অনুমতি দিন",
            "contacts.no_contacts": "কোন পরিচিতি পাওয়া যায়নি",
            "contacts.no_phone": "ফোন নেই",
            "details.request_withdrawn": "অনুরোধ প্রত্যাহার করা হয়েছে",
            "details.withdraw_failed": "অনুরোধ প্রত্যাহার করতে ব্যর্থ"
        },
        "pa": {
            "home.cannot_pay_self": "ਆਪਣੇ ਆਪ ਨੂੰ ਪੈਸੇ ਨਹੀਂ ਭੇਜ ਸਕਦੇ",
            "scan.my_qr_tab": "ਮੇਰਾ QR",
            "scan.upload_gallery": "ਗੈਲਰੀ ਤੋਂ ਅਪਲੋਡ ਕਰੋ",
            "scan.open_scanner_btn": "ਸਕੈਨਰ ਖੋਲ੍ਹੋ",
            "scan.share_qr_btn": "QR ਕੋਡ ਸਾਂਝਾ ਕਰੋ",
            "scan.low_light": "ਘੱਟ ਰੋਸ਼ਨੀ ਮਿਲੀ",
            "contacts.pay_btn": "ਭੁਗਤਾਨ ਕਰੋ",
            "contacts.invite_btn": "ਸੱਦਾ ਦਿਓ",
            "contacts.grant_permission_msg": "ਸੰਪਰਕ ਦੇਖਣ ਲਈ ਕਿਰਪਾ ਕਰਕੇ ਇਜਾਜ਼ਤ ਦਿਓ",
            "contacts.grant_permission_btn": "ਇਜਾਜ਼ਤ ਦਿਓ",
            "contacts.no_contacts": "ਕੋਈ ਸੰਪਰਕ ਨਹੀਂ ਮਿਲਿਆ",
            "contacts.no_phone": "ਕੋਈ ਫ਼ੋਨ ਨਹੀਂ",
            "details.request_withdrawn": "ਬੇਨਤੀ ਵਾਪਸ ਲੈ ਲਈ ਗਈ",
            "details.withdraw_failed": "ਬੇਨਤੀ ਵਾਪਸ ਲੈਣ ਵਿੱਚ ਅਸਫਲ"
        }
    }

    def sync_dict(base, target, lang_code, prefix=''):
        synced = {}
        for key, value in base.items():
            full_key = f"{prefix}.{key}" if prefix else key
            
            # If target has it, keep it
            if key in target:
                if isinstance(value, dict) and isinstance(target[key], dict):
                    synced[key] = sync_dict(value, target[key], lang_code, full_key)
                else:
                    synced[key] = target[key]
            else:
                # Target is missing key. Check manual override
                override = translations.get(lang_code, {}).get(full_key)
                if override:
                    synced[key] = override
                else:
                    # Recursive for nested structures missing in target
                    if isinstance(value, dict):
                        synced[key] = sync_dict(value, {}, lang_code, full_key)
                    else:
                        # Fallback to English but mark for review if needed
                        synced[key] = value
        return synced

    supported_langs = ['hi', 'ta', 'bn', 'gu', 'kn', 'ml', 'mr', 'te', 'pa', 'hi_en']
    
    for lang_code in supported_langs:
        f_name = f"{lang_code}.json"
        path = os.path.join(base_dir, f_name)
        
        target_data = {}
        if os.path.exists(path):
            with open(path, 'r', encoding='utf-8') as f:
                try:
                    target_data = json.load(f)
                except json.JSONDecodeError:
                    print(f"Error decoding {f_name}, starting fresh.")
                    target_data = {}
            
        new_data = sync_dict(en_data, target_data, lang_code)
        
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(new_data, f, ensure_ascii=False, indent=4)
        print(f"Propagated to {f_name}")

if __name__ == "__main__":
    propagate_translations()
