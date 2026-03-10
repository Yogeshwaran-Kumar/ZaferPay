# Localization Guide for ZaferPay Mobile App

## Supported Languages

The app supports 10 languages:
1. English (en)
2. Hindi (hi)
3. Hinglish (hi_EN) - Hindi written in English script
4. Bengali (bn)
5. Gujarati (gu)
6. Kannada (kn)
7. Malayalam (ml)
8. Marathi (mr)
9. Tamil (ta)
10. Telugu (te)

## How Localization Works

### 1. Language Selection
- Users can select their preferred language from Profile > Language
- Selection is saved in SharedPreferences
- The app automatically applies the language across all screens

### 2. API Integration
- The selected language is sent to the backend via `Accept-Language` header
- Backend returns localized responses based on this header
- See `mobile_app/lib/services/api_client.dart` for implementation

### 3. UI Text Localization
All user-facing text uses the `AppLocalizations` service:

```dart
Text(
  AppLocalizations.of(context)?.translate('key.name') ?? 'Fallback Text',
)
```

### 4. Preventing Text Overflow

#### Problem
Long translations (especially in Tamil, Telugu, Malayalam) can cause UI overflow.

#### Solutions

**A. Use Expanded in Rows:**
```dart
Row(
  children: [
    Icon(Icons.home),
    SizedBox(width: 8),
    Expanded(  // ← Prevents overflow
      child: Text(
        AppLocalizations.of(context)?.translate('long.text') ?? 'Text',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

**B. Use Flexible Widgets:**
```dart
Row(
  children: [
    Flexible(
      child: Text(
        longText,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    ),
  ],
)
```

**C. Use Helper Utilities:**
```dart
import 'utils/text_overflow_fix.dart';

// Automatically handles overflow
TextOverflowFix.safeRowText(
  text: AppLocalizations.of(context)?.translate('key') ?? 'Text',
  style: TextStyle(fontSize: 16),
  leading: [Icon(Icons.home)],
)
```

### 5. Common Patterns

#### ListTile (Handles overflow automatically)
```dart
ListTile(
  title: Text(AppLocalizations.of(context)?.translate('title') ?? 'Title'),
  subtitle: Text(AppLocalizations.of(context)?.translate('subtitle') ?? 'Subtitle'),
)
```

#### Card with Long Text
```dart
Card(
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info),
            SizedBox(width: 8),
            Expanded(  // ← Important!
              child: Text(
                AppLocalizations.of(context)?.translate('message') ?? 'Message',
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ],
    ),
  ),
)
```

### 6. Testing Localization

To test all languages:

1. **Run the app**
2. **Go to Profile > Language**
3. **Select each language and verify:**
   - All text is translated
   - No UI overflow errors
   - Text is readable and makes sense
   - Buttons and cards display properly

### 7. Adding New Translations

When adding new UI text:

1. **Add translation key to backend** (`backend/i18n.py`)
2. **Use AppLocalizations in Flutter:**
   ```dart
   AppLocalizations.of(context)?.translate('new.key') ?? 'Fallback'
   ```
3. **Always provide fallback text** (English)
4. **Wrap in Expanded if in a Row**

### 8. Common Mistakes to Avoid

❌ **Don't do this:**
```dart
Row(
  children: [
    Icon(Icons.home),
    Text('Very long text that might overflow'),  // ← Will overflow!
    Spacer(),
  ],
)
```

✅ **Do this instead:**
```dart
Row(
  children: [
    Icon(Icons.home),
    SizedBox(width: 8),
    Expanded(  // ← Prevents overflow
      child: Text(
        'Very long text that might overflow',
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

### 9. Responsive Design Tips

- Use `ScreenUtil` for responsive sizing (already configured)
- Test on different screen sizes
- Use `maxLines` and `overflow: TextOverflow.ellipsis` for long text
- Avoid fixed widths for text containers
- Use `Flexible` or `Expanded` in Rows and Columns

### 10. Debugging Overflow Issues

If you see overflow errors:

1. **Find the widget** causing overflow (check error stack trace)
2. **Locate the Row/Column** containing the text
3. **Wrap text in Expanded** or use `TextOverflowFix` utility
4. **Add overflow: TextOverflow.ellipsis** to Text widget
5. **Test in all languages** (especially Tamil, Telugu, Malayalam)

## Files to Reference

- `mobile_app/lib/services/app_localizations.dart` - Localization service
- `mobile_app/lib/services/app_language_provider.dart` - Language state management
- `mobile_app/lib/services/api_client.dart` - API language header
- `mobile_app/lib/utils/text_overflow_fix.dart` - Overflow prevention utilities
- `backend/i18n.py` - Translation strings
