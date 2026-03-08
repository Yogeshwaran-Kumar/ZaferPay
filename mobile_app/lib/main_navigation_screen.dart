import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'money_screen.dart';
import 'spending_limit_tab_screen.dart';
import 'profile_screen.dart';
import 'services/app_localizations.dart';

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
      const SpendingLimitTabScreen(),
      ProfileScreen(onBack: () => _switchToTab(0)),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          // If not on Home tab, switch to Home tab
          if (_currentIndex == 1) {
            _moneyScreenKey.currentState?.lockBalance();
          }
          setState(() {
            _currentIndex = 0;
          });
        } else {
          // Already on Home tab — exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111318) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black38 : Colors.grey.shade200,
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label:
                        AppLocalizations.of(context)?.translate('nav.home') ??
                        'Home',
                    index: 0,
                  ),
                  _buildNavItem(
                    icon: Icons.account_balance_wallet_outlined,
                    activeIcon: Icons.account_balance_wallet_rounded,
                    label:
                        AppLocalizations.of(context)?.translate('nav.money') ??
                        'Money',
                    index: 1,
                  ),
                  _buildNavItem(
                    icon: Icons.donut_large_outlined,
                    activeIcon: Icons.donut_large_rounded,
                    label:
                        AppLocalizations.of(
                          context,
                        )?.translate('nav.analytics') ??
                        'Analytics',
                    index: 2,
                  ),
                  _buildNavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label:
                        AppLocalizations.of(
                          context,
                        )?.translate('nav.profile') ??
                        'You',
                    index: 3,
                  ),
                ],
              ),
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

    final activeBgColor = isDark
        ? const Color(0xFF00B9F1).withValues(alpha: 0.18)
        : const Color(0xFF00B9F1).withValues(alpha: 0.1);
    final activeIconColor = const Color(0xFF00B9F1);
    final inactiveIconColor = isDark
        ? Colors.grey.shade500
        : Colors.grey.shade500;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_currentIndex == 1 && index != 1) {
          _moneyScreenKey.currentState?.lockBalance();
        }
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey('${index}_$isActive'),
                color: isActive ? activeIconColor : inactiveIconColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: isActive ? activeIconColor : inactiveIconColor,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
