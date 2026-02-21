import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'money_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // GlobalKey to access MoneyScreen state for locking balance
  final GlobalKey<MoneyScreenState> _moneyScreenKey =
      GlobalKey<MoneyScreenState>();

  void _switchToTab(int index) {
    // Lock balance when switching away from Money tab (index 1)
    if (_currentIndex == 1 && index != 1) {
      _moneyScreenKey.currentState?.lockBalance();
    }
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(onSwitchTab: _switchToTab),
      MoneyScreen(key: _moneyScreenKey, onBack: () => _switchToTab(0)),
      ProfileScreen(onBack: () => _switchToTab(0)),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.grey.shade300,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet,
                  label: 'Money',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'You',
                  index: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final bool isActive = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware colors
    final activeBgColor = isDark
        ? const Color(0xFF00B9F1).withValues(alpha: 0.2)
        : const Color(0xFF00B9F1).withValues(alpha: 0.1);
    final activeIconColor = isDark
        ? const Color(0xFF00B9F1)
        : const Color(0xFF00B9F1);
    final inactiveIconColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;

    return GestureDetector(
      onTap: () {
        // Lock balance when switching away from Money tab (index 1)
        if (_currentIndex == 1 && index != 1) {
          _moneyScreenKey.currentState?.lockBalance();
        }
        setState(() => _currentIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? activeIconColor : inactiveIconColor,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? activeIconColor : inactiveIconColor,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
