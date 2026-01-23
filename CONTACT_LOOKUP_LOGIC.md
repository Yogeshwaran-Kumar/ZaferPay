# Contact Phone Number Lookup - Smart +91 Handling

## How It Works

The contact lookup system now intelligently handles Indian phone numbers with or without the +91 country code.

## Lookup Strategy

When a user selects a contact, the app tries to find them in the database using THREE attempts:

### Example Contact: "John" with phone "+91 9876543210"

1. **First Try**: Search with EXACT number as stored in contact
   - Search for: `+919876543210`
   
2. **Second Try** (if not found and starts with +91): Remove country code
   - Search for: `9876543210`
   
3. **Third Try** (if not found and 10 digits without +): Add country code
   - If contact has: `9876543210`
   - Search for: `+919876543210`

## Code Logic

```dart
for (var phone in contact.phones) {
  String cleanedPhone = phone.number.replaceAll(RegExp(r'[^0-9+]'), '');
  
  // Try 1: Original number
  var userInfo = await _api.lookupUserByPhone(cleanedPhone);
  if (userInfo != null) return userInfo;
  
  // Try 2: If starts with +91, try without it
  if (cleanedPhone.startsWith('+91')) {
    String phoneWithoutCountryCode = cleanedPhone.substring(3);
    userInfo = await _api.lookupUserByPhone(phoneWithoutCountryCode);
    if (userInfo != null) return userInfo;
  }
  
  // Try 3: If 10 digits without +91, try with it
  else if (cleanedPhone.length == 10 && !cleanedPhone.startsWith('+')) {
    String phoneWithCountryCode = '+91$cleanedPhone';
    userInfo = await _api.lookupUserByPhone(phoneWithCountryCode);
    if (userInfo != null) return userInfo;
  }
}
```

## Benefits

✅ **Flexible Matching**: Works regardless of how phone numbers are stored in database
✅ **Multiple Formats**: Handles +91XXXXXXXXXX, XXXXXXXXXX, or any variation
✅ **No False Negatives**: Won't miss users due to format differences
✅ **Efficient**: Stops searching as soon as a match is found

## Examples

| Contact Format | Database Format | Result |
|---------------|----------------|--------|
| +91 9876543210 | 9876543210 | ✅ Found (Try 2) |
| 9876543210 | +919876543210 | ✅ Found (Try 3) |
| +91 9876543210 | +919876543210 | ✅ Found (Try 1) |
| 9876543210 | 9876543210 | ✅ Found (Try 1) |
| +1 5551234567 | US number | ❌ Only tries +91 for India |

## User Experience

1. User taps "Select Contact"
2. User selects "John"
3. Shows loading: "Looking up contact..."
4. App tries all 3 variations
5. If found → Opens payment screen
6. If not found → Shows "John is not registered on 2Way"

## Backend Requirements

The backend should accept phone numbers in ANY format:
- With +91: `+919876543210`
- Without +91: `9876543210`
- With spaces/dashes (cleaned by app): `+91 98765-43210` → `+919876543210`

Recommended database normalization:
```python
def normalize_phone(phone: str) -> str:
    # Remove all non-numeric except +
    cleaned = re.sub(r'[^0-9+]', '', phone)
    
    # Store in consistent format (your choice)
    if cleaned.startswith('+91'):
        return cleaned[3:]  # Store without +91
    return cleaned
```

Then search using the normalized format in the lookup endpoint.
