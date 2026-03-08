import json
import logging

logger = logging.getLogger(__name__)

# Basic dictionary of translations mapped to the keys used in main.py
_TRANSLATIONS = {
    "en": {
        "already_logged_in": "User is already logged in on another device.",
        "first_time_receiver": "First time sending to this receiver",
        "fraud_blocked_call": "Transaction blocked for security. You cannot perform risky actions while on an active phone call.",
        "fraud_blocked_flagged": "Transaction blocked. This account has been flagged for fraudulent activity.",
        "send_to_self": "Cannot send money to yourself",
        "send_to_child": "Cannot send money directly to a child account. Please pay the parent instead.",
        "approval_sent": "Approval request sent to primary account holder",
        "limit_exceeded": "Transaction Failed. You cannot send more than {limit} to this person in one day.",
        "transaction_blocked_security": "Transaction Blocked for Security",
        "no_contacts": "No valid phone numbers found in contacts",
        "contacts_synced": "Successfully synced {count} contacts. Created {links} new trust relationships.",
        "complaint_success": "Complaint submitted successfully",
        "complaint_duplicate": "A complaint has already been filed for this transaction.",
        "complaint_not_found": "No existing complaint found.",
        "fallback_error": "An error occurred",
        "unauthorized": "Unauthorized access"
    },
    "hi": {
        "already_logged_in": "\u0909\u092a\u092f\u094b\u0917\u0915\u0930\u094d\u0924\u093e \u092a\u0939\u0932\u0947 \u0938\u0947 \u0939\u0940 \u0915\u093f\u0938\u0940 \u0905\u0928\u094d\u092f \u0921\u093f\u0935\u093e\u0907\u0938 \u092a\u0930 \u0932\u0949\u0917 \u0907\u0928 \u0939\u0948\u0964",
        "first_time_receiver": "\u0907\u0938 \u0930\u093f\u0938\u0940\u0935\u0930 \u0915\u094b \u092a\u0939\u0932\u0940 \u092c\u093e\u0930 \u092d\u0947\u091c \u0930\u0939\u0947 \u0939\u0948\u0902",
        "fraud_blocked_call": "\u0938\u0941\u0930\u0915\u094d\u0937\u093e \u0915\u0947 \u0932\u093f\u090f \u0932\u0947\u0928\u0926\u0947\u0928 \u092c\u094d\u0932\u0949\u0915 \u0915\u093f\u092f\u093e \u0917\u092f\u093e\u0964 \u0906\u092a \u0938\u0915\u094d\u0930\u093f\u092f \u092b\u094b\u0928 \u0915\u0949\u0932 \u092a\u0930 \u0939\u094b\u0928\u0947 \u092a\u0930 \u091c\u094b\u0916\u093f\u092e \u092d\u0930\u0947 \u0915\u093e\u0930\u094d\u092f \u0928\u0939\u0940\u0902 \u0915\u0930 \u0938\u0915\u0924\u0947 \u0939\u0948\u0902\u0964",
        "fraud_blocked_flagged": "\u0932\u0947\u0928\u0926\u0947\u0928 \u092c\u094d\u0932\u0949\u0915 \u0915\u093f\u092f\u093e \u0917\u092f\u093e\u0964 \u0907\u0938 \u0916\u093e\u0924\u0947 \u0915\u094b \u0927\u094b\u0916\u093e\u0927\u0921\u093c\u0940 \u0915\u0940 \u0917\u0924\u093f\u0935\u093f\u0927\u093f \u0915\u0947 \u0932\u093f\u090f \u091a\u093f\u0939\u094d\u0928\u093f\u0924 \u0915\u093f\u092f\u093e \u0917\u092f\u093e \u0939\u0948\u0964",
        "send_to_self": "\u0905\u092a\u0928\u0947 \u0906\u092a \u0915\u094b \u092a\u0948\u0938\u0947 \u0928\u0939\u0940\u0902 \u092d\u0947\u091c \u0938\u0915\u0924\u0947",
        "send_to_child": "\u0938\u0940\u0927\u0947 \u091a\u093e\u0907\u0932\u094d\u0921 \u0905\u0915\u093e\u0909\u0902\u091f \u092e\u0947\u0902 \u092a\u0948\u0938\u0947 \u0928\u0939\u0940\u0902 \u092d\u0947\u091c \u0938\u0915\u0924\u0947\u0964 \u0915\u0943\u092a\u092f\u093e \u0907\u0938\u0915\u0947 \u092c\u091c\u093e\u092f \u092e\u093e\u0924\u093e-\u092a\u093f\u0924\u093e \u0915\u094b \u092d\u0941\u0917\u0924\u093e\u0928 \u0915\u0930\u0947\u0902\u0964",
        "approval_sent": "\u092a\u094d\u0930\u093e\u0925\u092e\u093f\u0915 \u0916\u093e\u0924\u093e\u0927\u093e\u0930\u0915 \u0915\u094b \u0938\u094d\u0935\u0940\u0915\u0943\u0924\u093f \u0905\u0928\u0941\u0930\u094b\u0927 \u092d\u0947\u091c\u093e \u0917\u092f\u093e",
        "limit_exceeded": "\u0932\u0947\u0928\u0926\u0947\u0928 \u0935\u093f\u092b\u0932 \u0939\u094b \u0917\u092f\u093e\u0964 \u0906\u092a \u090f\u0915 \u0926\u093f\u0928 \u092e\u0947\u0902 \u0907\u0938 \u0935\u094d\u092f\u0915\u094d\u0924\u093f \u0915\u094b {limit} \u0938\u0947 \u0905\u0927\u093f\u0915 \u0928\u0939\u0940\u0902 \u092d\u0947\u091c \u0938\u0915\u0924\u0947\u0964",
        "transaction_blocked_security": "\u0938\u0941\u0930\u0915\u094d\u0937\u093e \u0915\u0947 \u0932\u093f\u090f \u0932\u0947\u0928\u0926\u0947\u0928 \u092c\u094d\u0932\u0949\u0915 \u0915\u093f\u092f\u093e \u0917\u092f\u093e",
        "no_contacts": "\u0938\u0902\u092a\u0930\u094d\u0915\u094b\u0902 \u092e\u0947\u0902 \u0915\u094b\u0908 \u0935\u0948\u0927 \u092b\u094b\u0928 \u0928\u0902\u092c\u0930 \u0928\u0939\u0940\u0902 \u092e\u093f\u0932\u093e",
        "contacts_synced": "{count} \u0938\u0902\u092a\u0930\u094d\u0915 \u0938\u092b\u0932\u0924\u093e\u092a\u094f\u0930\u094d\u0935\u0915 \u0938\u093f\u0902\u0915 \u0915\u093f\u090f \u0917\u090f\u0964 {links} \u0928\u090f \u091f\u094d\u0930\u0938\u094d\u091f \u0930\u093f\u0932\u0947\u0936\u0928\u0936\u093f\u092a \u092c\u0928\u093e\u090f \u0917\u090f\u0964",
        "complaint_success": "\u0936\u093f\u0915\u093e\u092f\u0924 \u0938\u092b\u0932\u0924\u093e\u092a\u0942\u0930\u094d\u0935\u0915 \u0926\u0930\u094d\u091c \u0915\u0940 \u0917\u0908",
        "complaint_duplicate": "\u0907\u0938 \u0932\u0947\u0928\u0926\u0947\u0928 \u0915\u0947 \u0932\u093f\u090f \u092a\u0939\u0932\u0947 \u0939\u0940 \u0936\u093f\u0915\u093e\u092f\u0924 \u0926\u0930\u094d\u091c \u0915\u0940 \u091c\u093e \u091a\u0941\u0915\u0940 \u0939\u0948\u0964",
        "complaint_not_found": "\u0915\u094b\u0908 \u092e\u094c\u091c\u0942\u0926\u093e \u0936\u093f\u0915\u093e\u092f\u0924 \u0928\u0939\u0940\u0902 \u092e\u093f\u0932\u0940\u0964",
        "fallback_error": "\u090f\u0915 \u0924\u094d\u0930\u0941\u091f\u093f \u0939\u0941\u0908",
        "unauthorized": "\u0905\u0928\u0927\u093f\u0915\u0943\u0924 \u092a\u0939\u0941\u0902\u091a"
    },
    "hi_en": {
        "already_logged_in": "User already kisi aur device par logged in hai.",
        "first_time_receiver": "Is receiver ko pehli baar bhej rahe hain",
        "fraud_blocked_call": "Security ke liye transaction block kiya gaya. Phone call par rehte hue aap risky action nahi le sakte.",
        "fraud_blocked_flagged": "Transaction blocked. Is account ko fraud activity ke liye flag kiya gaya hai.",
        "send_to_self": "Apne aap ko paise nahi bhej sakte",
        "send_to_child": "Child account me directly paise nahi bhej sakte. Please parent ko pay karein.",
        "approval_sent": "Primary account holder ko approval request bhej di gayi",
        "limit_exceeded": "Transaction Failed. Aap ek din me is person ko {limit} se zyada nahi bhej sakte.",
        "transaction_blocked_security": "Security ke liye transaction block kiya gaya",
        "no_contacts": "Contacts me koi valid phone number nahi mila",
        "contacts_synced": "Successfully {count} contacts sync ho gaye. {links} naye trust relationships banaye.",
        "complaint_success": "Complaint successfully submit ho gayi",
        "complaint_duplicate": "Is transaction ke liye pehle hi complaint file ki ja chuki hai.",
        "complaint_not_found": "Koi existing complaint nahi mili.",
        "fallback_error": "Ek error aayi",
        "unauthorized": "Unauthorized access"
    },
    "ta": {
        "already_logged_in": "பயனர் ஏற்கனவே மற்றொரு சாதனத்தில் உள்நுழைந்துள்ளார்.",
        "first_time_receiver": "இந்த பெறுநருக்கு முதல் முறையாக அனுப்பப்படுகிறது",
        "fraud_blocked_call": "பாதுகாப்புக்காக பரிவர்த்தனை முடக்கப்பட்டது. தொலைபேசியில் பேசும்போது அபாயகரமான செயல்களைச் செய்ய முடியாது.",
        "fraud_blocked_flagged": "பரிவர்த்தனை முடக்கப்பட்டது. இந்த கணக்கு மோசடி நடவடிக்கைகளுக்காகக் குறிக்கப்பட்டுள்ளது.",
        "send_to_self": "உங்களுக்கே பணத்தை அனுப்ப முடியாது",
        "send_to_child": "குழந்தை கணக்கிற்கு நேரடியாக பணத்தை அனுப்ப முடியாது. பெற்றோருக்கு செலுத்தவும்.",
        "approval_sent": "முதன்மை கணக்காளருக்கு ஒப்புதல் கோரிக்கை அனுப்பப்பட்டது",
        "limit_exceeded": "பரிவர்த்தனை தோல்வியடைந்தது. ஒரு நாளில் இந்த நபருக்கு {limit}-க்கு மேல் அனுப்ப முடியாது.",
        "transaction_blocked_security": "பாதுகாப்புக்காக பரிவர்த்தனை முடக்கப்பட்டது",
        "no_contacts": "தொடர்புகளில் செல்லுபடியாகும் தொலைபேசி எண்கள் எதுவும் இல்லை",
        "contacts_synced": "{count} தொடர்புகள் வெற்றிகரமாக ஒத்திசைக்கப்பட்டன. {links} புதிய நம்பகத்தன்மை உறவுகள் உருவாக்கப்பட்டன.",
        "complaint_success": "புகார் வெற்றிகரமாக சமர்ப்பிக்கப்பட்டது",
        "complaint_duplicate": "இந்த பரிவர்த்தனைக்கு ஏற்கனவே ஒரு புகார் அளிக்கப்பட்டுள்ளது.",
        "complaint_not_found": "ஏற்கனவே உள்ள புகார் எதுவும் கிடைக்கவில்லை.",
        "fallback_error": "ஒரு பிழை ஏற்பட்டது",
        "unauthorized": "அங்கீகாரமற்ற அணுகல்"
    },
    "te": {
        "already_logged_in": "వాడుకరి ఇప్పటికే వేరొక పరికరంలో లాగిన్ అయ్యారు.",
        "first_time_receiver": "ఈ రిసీవర్‌కు మొదటిసారి పంపబడుతోంది",
        "fraud_blocked_call": "భద్రత కోసం లావాదేవీ నిరోధించబడింది. ఫోన్ కాల్లో ఉండగా మీరు ప్రమాదకర చర్యలను చేయలేరు.",
        "fraud_blocked_flagged": "లావాదేవీ నిరోధించబడింది. ఈ ఖాతా మోసపూరిత కార్యకలాపాల కోసం ఫ్లాగ్ చేయబడింది.",
        "send_to_self": "మీకు మీరే డబ్బు పంపలేరు",
        "send_to_child": "పిల్లల ఖాతాకు నేరుగా డబ్బు పంపలేరు. దయచేసి తల్లిదండ్రులకు చెల్లించండి.",
        "approval_sent": "ప్రాథమిక ఖాతాదారునికి ఆమోదం కోసం అభ్యర్థన పంపబడింది",
        "limit_exceeded": "లావాదేవీ విఫలమైంది. మీరు ఒక రోజులో ఈ వ్యక్తికి {limit} కంటే ఎక్కువ పంపలేరు.",
        "transaction_blocked_security": "భద్రత కోసం లావాదేవీ నిరోధించబడింది",
        "no_contacts": "పరిచయాలలో చెల్లుబాటు అయ్యే ఫోన్ నంబర్లు ఏవీ కనుగొనబడలేదు",
        "contacts_synced": "{count} పరిచయాలను విజయవంతంగా సమకాలీకరించాము. {links} కొత్త నమ్మకమైన సంబంధాలు సృష్టించబడ్డాయి.",
        "complaint_success": "ఫిర్యాదు విజయవంతంగా సమర్పించబడింది",
        "complaint_duplicate": "ఈ లావాదేవీకి ఇప్పటికే ఫిర్యాదు నమోదు చేయబడింది.",
        "complaint_not_found": "ఇప్పటికే ఉన్న ఫిర్యాదు ఏదీ కనుగొనబడలేదు.",
        "fallback_error": "ఒక లోపం ఏర్పడింది",
        "unauthorized": "అనధికార ప్రాప్యత"
    },
    "ml": {
        "already_logged_in": "ഉപയോക്താവ് ഇതിനകം മറ്റൊരു ഉപകരണത്തിൽ ലോഗിൻ ചെയ്‌തിട്ടുണ്ട്.",
        "first_time_receiver": "ഈ അക്കൗണ്ടിലേക്ക് ആദ്യമായാണ് പണം അയയ്ക്കുന്നത്",
        "fraud_blocked_call": "സുരക്ഷയ്ക്കായി ഇടപാട് തടഞ്ഞു. ഫോൺ വിളിക്കുമ്പോൾ നിങ്ങൾക്ക് സുരക്ഷിതമല്ലാത്ത പ്രവൃത്തികൾ ചെയ്യാൻ കഴിയില്ല.",
        "fraud_blocked_flagged": "ഇടപാട് തടഞ്ഞു. ഈ അക്കൗണ്ട് തട്ടിപ്പ് പ്രവർത്തനങ്ങൾക്ക് പേരുകേട്ടതാണ്.",
        "send_to_self": "നിങ്ങൾക്ക് നിങ്ങൾക്ക് തന്നെ പണം അയയ്ക്കാൻ കഴിയില്ല",
        "send_to_child": "കുട്ടിയുടെ അക്കൗണ്ടിലേക്ക് നേരിട്ട് പണം അയയ്ക്കാൻ കഴിയില്ല. പകരം രക്ഷിതാവിന് പണം നൽകുക.",
        "approval_sent": "പ്രധാന അക്കൗണ്ട് ഉടമയ്ക്ക് അനുമതി അഭ്യർത്ഥന അയച്ചു",
        "limit_exceeded": "ഇടപാട് പരാജയപ്പെട്ടു. നിങ്ങൾക്ക് ഒരു ദിവസം ഈ വ്യക്തിക്ക് {limit} ൽ കൂടുതൽ അയയ്ക്കാൻ കഴിയില്ല.",
        "transaction_blocked_security": "സുരക്ഷയ്ക്കായി ഇടപാട് തടഞ്ഞു",
        "no_contacts": "കോൺടാക്റ്റുകളിൽ സാധുവായ ഫോൺ നമ്പറുകളൊന്നും കണ്ടെത്തിയില്ല",
        "contacts_synced": "{count} കോൺടാക്റ്റുകൾ വിജയകരമായി സമന്വയിപ്പിച്ചു. {links} പുതിയ വിശ്വാസ ബന്ധങ്ങൾ സൃഷ്ടിച്ചു.",
        "complaint_success": "പരാതി വിജയകരമായി സമർപ്പിച്ചു",
        "complaint_duplicate": "ഈ ഇടപാടിന് ഇതിനകം ഒരു പരാതി നൽകിയിട്ടുണ്ട്.",
        "complaint_not_found": "നിലവിലുള്ള പരാതികളൊന്നും കണ്ടെത്തിയില്ല.",
        "fallback_error": "ഒരു പിശക് സംഭവിച്ചു",
        "unauthorized": "അംഗീകൃതമല്ലാത്ത പ്രവേശനം"
    },
    "kn": {
        "already_logged_in": "ಬಳಕೆದಾರರು ಈಗಾಗಲೇ ಮತ್ತೊಂದು ಸಾಧನದಲ್ಲಿ ಲಾಗಿನ್ ಆಗಿದ್ದಾರೆ.",
        "first_time_receiver": "ಈ ರಿಸೀವರ್‌ಗೆ ಮೊದಲ ಬಾರಿಗೆ ಕಳುಹಿಸಲಾಗುತ್ತಿದೆ",
        "fraud_blocked_call": "ಭದ್ರತೆಗಾಗಿ ವಹಿವಾಟನ್ನು ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ. ಫೋನ್ ಕರೆಯಲ್ಲಿರುವಾಗ ನೀವು ಅಪಾಯಕಾರಿ ಕ್ರಿಯೆಗಳನ್ನು ಮಾಡಲು ಸಾಧ್ಯವಿಲ್ಲ.",
        "fraud_blocked_flagged": "ವಹಿವಾಟನ್ನು ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ. ಈ ಖಾತೆಯನ್ನು ವಂಚನೆ ಚಟುವಟಿಕೆಗಾಗಿ ಫ್ಲ್ಯಾಗ್ ಮಾಡಲಾಗಿದೆ.",
        "send_to_self": "ನಿಮಗೆ ನೀವೇ ಹಣವನ್ನು ಕಳುಹಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ",
        "send_to_child": "ಮಗುವಿನ ಖಾತೆಗೆ ನೇರವಾಗಿ ಹಣವನ್ನು ಕಳುಹಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ. ದಯವಿಟ್ಟು ಬದಲಿಗೆ ಪೋಷಕರಿಗೆ ಪಾವತಿಸಿ.",
        "approval_sent": "ಪ್ರಾಥಮಿಕ ಖಾತೆದಾರರಿಗೆ ಅನುಮೋದನೆ ವಿನಂತಿಯನ್ನು ಕಳುಹಿಸಲಾಗಿದೆ",
        "limit_exceeded": "ವಹಿವಾಟು ವಿಫಲವಾಗಿದೆ. ನೀವು ಒಂದು ದಿನದಲ್ಲಿ ಈ ವ್ಯಕ್ತಿಗೆ {limit} ಕ್ಕಿಂತ ಹೆಚ್ಚು ಕಳುಹಿಸುವಂತಿಲ್ಲ.",
        "transaction_blocked_security": "ಭದ್ರತೆಗಾಗಿ ವಹಿವಾಟನ್ನು ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ",
        "no_contacts": "ಸಂಪರ್ಕಗಳಲ್ಲಿ ಯಾವುದೇ ಮಾನ್ಯವಾದ ಫೋನ್ ಸಂಖ್ಯೆಗಳು ಕಂಡುಬಂದಿಲ್ಲ",
        "contacts_synced": "{count} ಸಂಪರ್ಕಗಳನ್ನು ಯಶಸ್ವಿಯಾಗಿ ಸಿಂಕ್ ಮಾಡಲಾಗಿದೆ. {links} ಹೊಸ ಟ್ರಸ್ಟ್ ಸಂಬಂಧಗಳನ್ನು ರಚಿಸಲಾಗಿದೆ.",
        "complaint_success": "ದೂರನ್ನು ಯಶಸ್ವಿಯಾಗಿ ಸಲ್ಲಿಸಲಾಗಿದೆ",
        "complaint_duplicate": "ಈ ವಹಿವಾಟಿಗೆ ಈಗಾಗಲೇ ದೂರನ್ನು ದಾಖಲಿಸಲಾಗಿದೆ.",
        "complaint_not_found": "ಅಸ್ತಿತ್ವದಲ್ಲಿರುವ ಯಾವುದೇ ದೂರು ಕಂಡುಬಂದಿಲ್ಲ.",
        "fallback_error": "ಒಂದು ದೋಷ ಸಂಭವಿಸಿದೆ",
        "unauthorized": "ಅನಧಿಕೃತ ಪ್ರವೇಶ"
    },
    "mr": {
        "already_logged_in": "वापरकर्ता आधीच दुसर्या डिव्हाइसवर लॉग इन आहे.",
        "first_time_receiver": "या रिसेव्हरला पहिल्यांदाच पैसे पाठवत आहात",
        "fraud_blocked_call": "सुरक्षेसाठी व्यवहार अवरोधित केला. फोन कॉलवर असताना तुम्ही धोक्याची कृती करू शकत नाही.",
        "fraud_blocked_flagged": "व्यवहार अवरोधित केला. हे खाते फसवणुकीच्या क्रियाकलापांसाठी ध्वजांकित केले गेले आहे.",
        "send_to_self": "स्वतःला पैसे पाठवू शकत नाही",
        "send_to_child": "चाइल्ड खात्यात थेट पैसे पाठवू शकत नाही. कृपया त्याऐवजी पालकांना पैसे द्या.",
        "approval_sent": "प्राथमिक खातेधारकास मंजुरीसाठी विनंती पाठविली",
        "limit_exceeded": "व्यवहार यशस्वी झाला नाही. आपण एका दिवसात या व्यक्तीला {limit} पेक्षा जास्त पाठवू शकत नाही.",
        "transaction_blocked_security": "सुरक्षेसाठी व्यवहार अवरोधित केला",
        "no_contacts": "संपर्कांमध्ये कोणतेही योग्य फोन नंबर आढळले नाहीत",
        "contacts_synced": "{count} संपर्क यशस्वीरित्या समक्रमित केले. {links} नवीन विश्वासार्ह नातेसंबंध तयार केले.",
        "complaint_success": "तक्रार यशस्वीरित्या नोंदवली",
        "complaint_duplicate": "या व्यवहारासाठी आधीच तक्रार दाखल केली गेली आहे.",
        "complaint_not_found": "कोणतीही अस्तित्वात असलेली तक्रार आढळली नाही.",
        "fallback_error": "त्रुटी आली",
        "unauthorized": "अनधिकृत प्रवेश"
    },
    "gu": {
        "already_logged_in": "વપરાશકર્તા પહેલેથી અન્ય ઉપકરણ પર લૉગ ઇન છે.",
        "first_time_receiver": "પહેલીવાર આ રિસીવરને મોકલી રહ્યાં છો",
        "fraud_blocked_call": "સુરક્ષા માટે વ્યવહાર બ્લોક કરવામાં આવ્યો છે. તમે ફોન કૉલ પર હોય ત્યારે જોખમી પગલાં લઈ શકતા નથી.",
        "fraud_blocked_flagged": "વ્યવહાર બ્લોક કરવામાં આવ્યો છે. આ એકાઉન્ટ છેતરપિંડીની પ્રવૃત્તિ માટે ફ્લેગ કરવામાં આવ્યું છે.",
        "send_to_self": "તમે તમારી જાતને પૈસા મોકલી શકતા નથી",
        "send_to_child": "બાળકના એકાઉન્ટમાં સીધા પૈસા મોકલી શકાતા નથી. કૃપા કરીને માતાપિતાને ચૂકવો.",
        "approval_sent": "મુખ્ય એકાઉન્ટ ધારકને મંજૂરી વિનંતી મોકલી",
        "limit_exceeded": "વ્યવહાર નિષ્ફળ ગયો. તમે એક દિવસમાં આ વ્યક્તિને {limit} કરતાં વધુ મોકલી શકતા નથી.",
        "transaction_blocked_security": "સુરક્ષા માટે વ્યવહાર બ્લોક કરવામાં આવ્યો છે",
        "no_contacts": "સંપર્કોમાં કોઈ માન્ય ફોન નંબર મળ્યા નથી",
        "contacts_synced": "{count} સંપર્કો સફળતાપૂર્વક સમન્વયિત થયા. {links} નવા વિશ્વસનીય સંબંધો બનાવ્યા.",
        "complaint_success": "ફરિયાદ સફળતાપૂર્વક સબમિટ કરવામાં આવી",
        "complaint_duplicate": "આ વ્યવહાર માટે પહેલેથી જ ફરિયાદ નોંધવામાં આવી છે.",
        "complaint_not_found": "કોઈ અસ્તિત્વમાં રહેલી ફરિયાદ મળી નથી.",
        "fallback_error": "એક ભૂલ આવી",
        "unauthorized": "બિનસત્તાવાર ઍક્સેસ"
    },
    "bn": {
        "already_logged_in": "ব্যবহারকারী ইতিমধ্যেই অন্য একটি ডিভাইসে লগ ইন করেছেন।",
        "first_time_receiver": "এই প্রাপককে প্রথমবার পাঠানো হচ্ছে",
        "fraud_blocked_call": "নিরাপত্তার জন্য লেনদেন ব্লক করা হয়েছে। ফোন কলে থাকার সময় আপনি ঝুঁকিপূর্ণ কাজ করতে পারবেন না।",
        "fraud_blocked_flagged": "লেনদেন ব্লক করা হয়েছে। এই অ্যাকাউন্টটি প্রতারণামূলক কার্যকলাপের জন্য চিহ্নিত করা হয়েছে।",
        "send_to_self": "নিজেকে টাকা পাঠাতে পারবেন না",
        "send_to_child": "সরাসরি সন্তানের অ্যাকাউন্টে টাকা পাঠাতে পারবেন না। অনুগ্রহ করে এর বদলে পিতামাতাকে প্রদান করুন।",
        "approval_sent": "প্রাথমিক অ্যাকাউন্ট হোল্ডারকে অনুমোদনের অনুরোধ পাঠানো হয়েছে",
        "limit_exceeded": "লেনদেন ব্যর্থ হয়েছে। আপনি একদিনে এই ব্যক্তিকে {limit}-এর বেশি পাঠাতে পারবেন না।",
        "transaction_blocked_security": "নিরাপত্তার জন্য লেনদেন ব্লক করা হয়েছে",
        "no_contacts": "পরিচিতিতে কোনো বৈধ ফোন নম্বর পাওয়া যায়নি",
        "contacts_synced": "{count} পরিচিতি সফলভাবে সিঙ্ক করা হয়েছে। {links} নতুন আস্থার সম্পর্ক তৈরি করা হয়েছে।",
        "complaint_success": "অভিযোগ সফলভাবে জমা দেওয়া হয়েছে",
        "complaint_duplicate": "এই লেনদেনের জন্য ইতিমধ্যেই একটি অভিযোগ দায়ের করা হয়েছে।",
        "complaint_not_found": "বিদ্যমান কোনো অভিযোগ পাওয়া যায়নি।",
        "fallback_error": "একটি ত্রুটি দেখা দিয়েছে",
        "unauthorized": "অননুমোদিত অ্যাক্সেস"
    }
}

def get_text(key: str, lang: str = "en", **kwargs) -> str:
    """Gets localized text from the translation dictionary."""
    if lang not in _TRANSLATIONS:
        # Fall back to base languages or defaults
        if lang.startswith("hi"):
            lang = "hi"
        else:
            lang = "en"
            
    group = _TRANSLATIONS.get(lang, _TRANSLATIONS["en"])
    text = group.get(key, _TRANSLATIONS["en"].get(key, key))
    if kwargs:
        try:
            return text.format(**kwargs)
        except Exception:
            return text
    return text
