# CRITICAL: Translation Files Need Fixing

## Problem Identified

The mobile app translation files for languages other than English and Hindi contain **incorrect text**:

- `ta.json` (Tamil) - Contains Hindi text instead of Tamil
- `te.json` (Telugu) - Contains Hindi text with corrupted encoding
- `bn.json` (Bengali) - Contains Hindi text
- `gu.json` (Gujarati) - Contains Hindi text
- `kn.json` (Kannada) - Contains Hindi text
- `ml.json` (Malayalam) - Contains Hindi text
- `mr.json` (Marathi) - Contains Hindi text
- `pa.json` (Punjabi) - Contains Hindi text

## Root Cause

The translation JSON files in `mobile_app/assets/translations/` were likely:
1. Copied from `hi.json` (Hindi) as templates
2. Never properly translated to the target languages
3. Or had encoding issues during creation

## Impact

- Users selecting Tamil, Telugu, Bengali, etc. see Hindi text instead
- Only English and Hindi work correctly
- This breaks the multilingual experience for 8 out of 10 languages

## Solution Options

### Option 1: Professional Translation (Recommended)
1. Send `en.json` to professional translators for each language
2. Ensure proper UTF-8 encoding
3. Verify translations with native speakers
4. Replace the files in `mobile_app/assets/translations/`

### Option 2: Machine Translation (Quick Fix)
1. Use Google Translate API or similar service
2. Translate all strings from English to target languages
3. Review and correct any errors
4. Update the JSON files

### Option 3: Backend Integration (Long-term)
1. Move all translations to backend only
2. Mobile app fetches translations from API
3. Easier to maintain and update
4. Single source of truth

## Immediate Action Required

Until proper translations are available, you should:

1. **Disable non-working languages** in the language selection screen
2. **Show only English and Hindi** to users
3. **Add a notice** that more languages are coming soon

## How to Disable Non-Working Languages

Edit `mobile_app/lib/language_selection_screen.dart`:

```dart
final List<Map<String, String>> _languages = [
  {'name': 'English', 'localName': 'English', 'code': 'en'},
  {'name': 'Hindi', 'localName': 'हिन्दी', 'code': 'hi'},
  {'name': 'Hinglish', 'localName': 'हिन्लिश', 'code': 'hi', 'country': 'EN'},
  // TEMPORARILY DISABLED - Translations need fixing
  // {'name': 'Bengali', 'localName': 'বাংলা', 'code': 'bn'},
  // {'name': 'Gujarati', 'localName': 'ગુજરાતી', 'code': 'gu'},
  // {'name': 'Kannada', 'localName': 'ಕನ್ನಡ', 'code': 'kn'},
  // {'name': 'Malayalam', 'localName': 'മലയാളം', 'code': 'ml'},
  // {'name': 'Marathi', 'localName': 'मराठी', 'code': 'mr'},
  // {'name': 'Tamil', 'localName': 'தமிழ்', 'code': 'ta'},
  // {'name': 'Telugu', 'localName': 'తెలుగు', 'code': 'te'},
];
```

## Translation File Structure

Each JSON file should follow this structure:

```json
{
  "app_name": "ZaferPay",
  "select_language": "[Translated: Select language]",
  "done": "[Translated: Done]",
  "nav": {
    "home": "[Translated: Home]",
    "money": "[Translated: Money]",
    "analytics": "[Translated: Analytics]",
    "profile": "[Translated: Profile]"
  },
  ...
}
```

## Verification Checklist

Before deploying translations:

- [ ] File is valid JSON (no syntax errors)
- [ ] File is UTF-8 encoded
- [ ] All keys from `en.json` are present
- [ ] Text is in the correct language (not Hindi!)
- [ ] Special characters display correctly
- [ ] Tested on actual device with native speaker
- [ ] No text overflow issues in UI

## Cost Estimate

Professional translation for 8 languages:
- ~500 strings per language
- ~4000 words per language
- Cost: $0.10-0.20 per word
- Total: $3,200 - $6,400 for all 8 languages

Machine translation:
- Free (Google Translate API has free tier)
- Requires manual review and corrections
- Time: 2-4 hours per language

## Priority Languages

Based on Indian demographics:
1. Hindi (✅ Working)
2. Bengali (❌ Needs fix)
3. Telugu (❌ Needs fix)
4. Marathi (❌ Needs fix)
5. Tamil (❌ Needs fix)
6. Gujarati (❌ Needs fix)
7. Kannada (❌ Needs fix)
8. Malayalam (❌ Needs fix)

## Contact

For translation services:
- Gengo: https://gengo.com/
- One Hour Translation: https://www.onehourtranslation.com/
- Lokalise: https://lokalise.com/

For machine translation:
- Google Cloud Translation API
- Microsoft Translator API
- AWS Translate

## Status

- **Identified:** 2026-03-09
- **Severity:** HIGH
- **Impact:** 8 out of 10 languages broken
- **Action Required:** IMMEDIATE

---

**Note:** This is a critical issue that affects user experience for non-Hindi speaking users. Please prioritize fixing this before wider release.
