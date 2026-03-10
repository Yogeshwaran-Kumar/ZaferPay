# Localization Testing Checklist

## Quick Test (5 minutes)

### 1. Language Selection Test
- [ ] Open app
- [ ] Go to Profile > Language
- [ ] Select Tamil (தமிழ்)
- [ ] Verify confirmation message appears
- [ ] Navigate to Home Screen
- [ ] Verify all text is in Tamil

### 2. Overflow Test
- [ ] With Tamil selected, check these screens:
  - [ ] Home Screen - Daily Summary card
  - [ ] Home Screen - Pending Requests
  - [ ] Home Screen - People section
  - [ ] Home Screen - Businesses section
  - [ ] Settings Screen - All options
  - [ ] Profile Screen - User details

### 3. Console Check
- [ ] Open Flutter DevTools
- [ ] Navigate through all screens
- [ ] Verify NO overflow errors in console
- [ ] Verify NO yellow/black stripes on UI

## Comprehensive Test (15 minutes)

### Test Each Language:

#### English (en)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Hindi (हिन्दी)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Hinglish (हिन्लिश)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Bengali (বাংলা)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Gujarati (ગુજરાતી)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Kannada (ಕನ್ನಡ)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Malayalam (മലയാളം)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Marathi (मराठी)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Tamil (தமிழ்)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

#### Telugu (తెలుగు)
- [ ] Select language
- [ ] Navigate: Home → History → Settings → Profile
- [ ] Verify all text displays correctly
- [ ] Check for any overflow

## Detailed Screen Tests

### Home Screen
- [ ] Top search bar
- [ ] Scanner card text
- [ ] Quick action buttons
- [ ] Pending requests banner
- [ ] Circle invites banner
- [ ] People section names
- [ ] Businesses section names
- [ ] Daily summary card
- [ ] Transaction history link
- [ ] Settings link
- [ ] Powered by footer

### Settings Screen
- [ ] App Lock title/subtitle
- [ ] Change PIN title/subtitle
- [ ] Change UPI PIN title/subtitle
- [ ] Biometric Login title/subtitle
- [ ] Summary Notifications title/subtitle
- [ ] Theme title/subtitle
- [ ] Logout button

### Profile Screen
- [ ] User name
- [ ] UPI ID
- [ ] Phone number
- [ ] Bank details
- [ ] QR code label
- [ ] Share button
- [ ] Settings button
- [ ] Language button
- [ ] UPI Circle button

### Transaction History
- [ ] Month selector
- [ ] Filter labels
- [ ] Transaction list items
- [ ] Amount displays
- [ ] Date/time stamps
- [ ] Status labels

### Transaction Details
- [ ] Transaction ID
- [ ] Amount
- [ ] Status
- [ ] Timestamp
- [ ] Sender/Receiver info
- [ ] Category
- [ ] Notes
- [ ] Action buttons

### Amount Screen
- [ ] Recipient name
- [ ] Amount input label
- [ ] Note input label
- [ ] Balance display
- [ ] Circle selector
- [ ] Risk warnings
- [ ] Pay button

### Conversation Screen
- [ ] Message list
- [ ] Input placeholder
- [ ] Send button
- [ ] Transaction cards
- [ ] Request cards

## Edge Cases to Test

### Long Names
- [ ] Test with very long contact names
- [ ] Test with very long merchant names
- [ ] Verify text truncates with ellipsis

### Long Messages
- [ ] Test with very long transaction notes
- [ ] Test with very long request reasons
- [ ] Verify text wraps or truncates properly

### Small Screens
- [ ] Test on smallest supported device
- [ ] Verify all text is readable
- [ ] Verify no horizontal scrolling

### Large Text Size
- [ ] Enable large text in device settings
- [ ] Verify app scales properly
- [ ] Verify no overflow issues

## Automated Checks

### Run Flutter Analyze
```bash
cd mobile_app
flutter analyze
```
Expected: No errors

### Run Tests
```bash
flutter test
```
Expected: All tests pass

### Check for Overflow Warnings
```bash
flutter run --debug
# Navigate through app
# Check console for overflow warnings
```
Expected: No overflow warnings

## Performance Checks

### Language Switch Speed
- [ ] Switch between languages
- [ ] Verify instant UI update
- [ ] No lag or stuttering

### Memory Usage
- [ ] Monitor memory during language switches
- [ ] Verify no memory leaks
- [ ] Check for excessive allocations

### Scroll Performance
- [ ] Scroll through long lists
- [ ] Verify smooth 60fps
- [ ] No jank or dropped frames

## Regression Tests

### After Each Fix
- [ ] Re-test all languages
- [ ] Verify fix didn't break other screens
- [ ] Check console for new errors
- [ ] Test on multiple devices

## Sign-Off

### Before Deployment
- [ ] All languages tested
- [ ] All screens verified
- [ ] No overflow errors
- [ ] No console warnings
- [ ] Performance acceptable
- [ ] Edge cases handled
- [ ] Documentation updated

**Tester Name:** _______________
**Date:** _______________
**Build Version:** _______________
**Status:** ⬜ PASS ⬜ FAIL

## Common Issues & Solutions

### Issue: Text still overflows
**Solution:** Wrap Text in Expanded widget

### Issue: Language not changing
**Solution:** Check SharedPreferences, restart app

### Issue: Some text still in English
**Solution:** Check backend translations, verify API header

### Issue: Text too small to read
**Solution:** Increase font size, use responsive sizing

### Issue: Layout breaks on small screens
**Solution:** Use Flexible/Expanded, test on smallest device

## Contact

For issues or questions:
- Check `LOCALIZATION_GUIDE.md`
- Review `MULTILINGUAL_FIX_SUMMARY.md`
- Test with `text_overflow_fix.dart` utilities
