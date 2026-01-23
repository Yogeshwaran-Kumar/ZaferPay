# Bottom Navigation Implementation - NEXT STEPS

## What We've Created

I've successfully created the following new files:

### 1. **main_navigation_screen.dart**
- Main screen with bottom navigation bar
- 3 tabs: Home, Money, You (Profile)
- Modern UPI-style design with purple accents

### 2. **money_screen.dart** ✅ COMPLETE
- **PIN-Protected Balance**: User must enter 4-digit PIN to view balance
- Shows "₹ ••••••" until PIN is entered
- Full transaction history
- Purple gradient balance card
- PIN verification dialog with keypad

### 3. **profile_screen.dart** ✅ COMPLETE
- User profile with avatar
- UPI ID display
- Mobile number
- Merchant badge (if applicable)
- Settings options: Change PIN, Settings, Help, About
- Logout functionality

## ⚠️ FINAL STEPS NEEDED

To complete the bottom nav implementation, you need to:

### Step 1: Update main.dart routing

Change the home route to point to `MainNavigationScreen` instead of `HomeScreen`:

```dart
// In main.dart, find the routes section and update:
'/home': (context) => const MainNavigationScreen(), // Changed from HomeScreen
```

### Step 2: Update home_screen.dart Structure

The home screen needs these changes:
1. **Remove** the balance card section (now in Money tab)
2. **Add** large "Scan QR Code" button at top (like UPI Shield image)
3. Keep the search bar
4. Keep Quick Actions
5. Keep People section
6. **Remove** FAB (floatingActionButton) since we have bottom nav
7. **Remove** AppBar since it'll be in NavigationScreen

### Simplified Home Screen Structure:
```
┌─────────────────────────────┐
│  [Large Scan QR Button]     │  ← Big blue rounded box
│                             │
│  Or pay to contact          │
│  [Search Bar]               │  ← Enter UPI/Phone
│                             │
│  Quick Actions              │
│  [Recharge] [Electricity]   │
│  [DTH] [Bills]              │
│                             │
│  People                     │
│  [Contact avatars...] →     │
│                             │
│  [See Transactions Button]  │
└─────────────────────────────┘
```

## Key Features Implemented

### Money Tab - PIN Protection
```dart
// When user taps balance card (if hidden):
- Shows PIN entry dialog
- User enters 4-digit PIN
- Verifies with backend via login()
- If correct: Shows balance
- If wrong: Shows error, keeps hidden
- "Hide Balance" button to lock again
```

### Bottom Navigation
```dart
- Home: Scanner, Quick Actions, People
- Money: Balance (PIN), Transactions
- You: Profile, Settings, Logout
```

## What's Left for HOME SCREEN

Since the home_screen.dart file is complex, here's what needs changing:

### Remove These Sections:
1. Lines with "Balance Display" - entire grey container
 2. Lines with "Recent Transactions" - the ListView.builder
3. The FAB (floatingActionButton)
4. The search bar in top grey container (old one)

### Add These Instead:
1. Large Scan QR button (blue gradient, 80px height)
2. "Or pay to contact" text
3. New search bar (white with border)
4. Keep Quick Actions (but make them smaller circles)
5. Keep People section
6. Add "See Transactions" button at bottom

## Quick Fix Option

If updating home_screen.dart is too complex, I can create a NEW `home_tab_screen.dart` with the clean structure, then just update MainNavigationScreen to use that instead.

Would you like me to:
A) Create a brand new clean home_tab_screen.dart? (RECOMMENDED)
B) Try to patch the existing home_screen.dart?

Let me know and I'll complete the implementation!
