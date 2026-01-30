import 'dart:async';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'contact_service.dart';

import 'mcc_helper.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onSwitchTab;

  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _user;
  List<dynamic> _history = [];
  List<dynamic> _recentPeople = [];
  List<dynamic> _recentMerchants = [];
  bool _isLoading = true;
  bool _isPeopleExpanded = false;
  bool _isMerchantsExpanded = false;

  // New fields for UPI payment

  Timer? _timer;

  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    // 0. Sync Load (True Zero Latency)
    // Initialize state BEFORE first build
    final cached = _api.getCachedHomeDataSync();
    if (cached != null) {
      _user = cached['user'];
      _history = cached['history'] ?? [];
      _recentPeople = cached['people'] ?? [];
      _recentMerchants = cached['merchants'] ?? [];
      _isLoading = false; // No spinner ever!
    } else {
      // Only trigger async load if sync failed
      _loadData();
    }

    // Start polling every 10 seconds to avoid hitting rate limits
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _loadData(showLoading: false);
      }
    });

    // Listen for forced logout
    _authSubscription = _api.authStateChanges.listen((_) {
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });

    // Silent Contact Pre-fetch (Zero Latency Payment Prep)
    ContactService.instance.prefetchContactsIfGranted();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSubscription?.cancel();

    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      // Try loading cache first for instant UI
      final cached = await _api.getCachedHomeData();
      if (cached != null) {
        _updateStateWithData(cached);
        // If we have cache, don't show loading spinner, just refresh in background
        showLoading = false;
      }
    }

    if (showLoading) {
      setState(() => _isLoading = true);
    }

    // Fetch fresh data
    try {
      final data = await _api.getHomeScreenData();
      if (data != null) {
        _updateStateWithData(data);
      }
    } catch (e) {
      // Ignore error if we have cache, otherwise stop loading
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateStateWithData(Map<String, dynamic> data) {
    if (!mounted) return;
    final user = data['user'];
    final history = data['history'];
    final people = data['people'];
    final merchants = data['merchants'];

    setState(() {
      if (user != null) _user = user;
      if (history != null) _history = history;
      if (people != null) _recentPeople = people;
      if (merchants != null) _recentMerchants = merchants;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: Text("Failed to load user")),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 1. Top Bar (Profile only)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    // Search Bar
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // Navigate to pay/search screen
                          Navigator.pushNamed(context, '/pay');
                        },
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF5F259F).withValues(alpha: 0.2)
                                : const Color(
                                    0xFF5F259F,
                                  ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark
                                  ? const Color(
                                      0xFF5F259F,
                                    ).withValues(alpha: 0.3)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search,
                                color: isDark
                                    ? const Color(0xFF9E65E6)
                                    : const Color(0xFF5F259F),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Pay friends and merchants",
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(
                                          0xFF9E65E6,
                                        ).withValues(alpha: 0.8)
                                      : const Color(
                                          0xFF5F259F,
                                        ).withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Profile Icon
                    GestureDetector(
                      onTap: () {
                        widget.onSwitchTab?.call(2);
                      },
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF5F259F), // Match theme
                        child: Text(
                          _user!['username'][0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Banner Image
              // 2. Scanner Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: _handleScan,
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF5F259F).withValues(alpha: 0.2)
                          : const Color(0xFF5F259F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF5F259F).withValues(alpha: 0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF5F259F).withValues(alpha: 0.2)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(
                                      0xFF5F259F,
                                    ).withValues(alpha: 0.5)
                                  : Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.qr_code_scanner,
                            size: 40,
                            color: isDark
                                ? const Color(0xFF9E65E6)
                                : const Color(0xFF5F259F),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Scan QR Code",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF5F259F),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 3. Functional Icons Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // Pay Anyone Button
                    Expanded(
                      child: GestureDetector(
                        onTap: _handlePayAnyone,
                        child: Container(
                          height: 70,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF5F259F).withValues(alpha: 0.2)
                                : const Color(
                                    0xFF5F259F,
                                  ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? const Color(
                                      0xFF5F259F,
                                    ).withValues(alpha: 0.3)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.send,
                                color: isDark
                                    ? const Color(0xFF9E65E6)
                                    : const Color(0xFF5F259F),
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Pay anyone",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF5F259F),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // View Balance Button
                    Expanded(
                      child: GestureDetector(
                        onTap: _handleViewBalance,
                        child: Container(
                          height: 70,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF5F259F).withValues(alpha: 0.2)
                                : const Color(
                                    0xFF5F259F,
                                  ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? const Color(
                                      0xFF5F259F,
                                    ).withValues(alpha: 0.3)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet,
                                color: isDark
                                    ? const Color(0xFF9E65E6)
                                    : const Color(0xFF5F259F),
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "View balance",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF5F259F),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 4. People Section
              if (_recentPeople.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "People",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildPeopleGrid(),
                ),
                const SizedBox(height: 24),
              ],

              // 5. Businesses Section
              if (_recentMerchants.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Businesses",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildMerchantGrid(),
                ),
                const SizedBox(height: 24),
              ],

              // 6. Extra Options Section (Transaction History & Settings)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildListItem(
                      icon: Icons.history,
                      text: "See transaction history",
                      onTap: () {
                        widget.onSwitchTab?.call(1);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildListItem(
                      icon: Icons.settings_outlined,
                      text: "View settings",
                      onTap: () {
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Powered By Footer
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Powered by SafePay",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white54 : Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleScan() async {
    final scanResult = await Navigator.pushNamed(
      context,
      '/scan',
      arguments: _user,
    );
    if (scanResult != null) {
      String scannedUpi = "";
      String? scannedMcc;
      String? scannedName;

      if (scanResult is Map) {
        scannedUpi = scanResult['upi'];
        scannedMcc = scanResult['mcc'];
        scannedName = scanResult['name'];
      } else if (scanResult is String) {
        scannedUpi = scanResult;
      }

      final myUpi = _user?['upi_id'];
      if (myUpi != null && myUpi == scannedUpi) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot send money to self')),
        );
        return;
      }

      if (!mounted) return;
      String? category;
      if (scannedMcc != null && scannedMcc.isNotEmpty) {
        category = MccHelper.getDomain(scannedMcc);
      }

      final nav = Navigator.of(context);
      final payResult = await nav.pushNamed(
        '/amount',
        arguments: {
          'upi': scannedUpi,
          'name': scannedName,
          'category': category,
          'mcc': scannedMcc,
          'senderBalance': _user?['balance'],
          'senderUpi': _user?['upi_id'],
        },
      );

      if (payResult != null && payResult is Map<String, dynamic>) {
        setState(() {
          _history.insert(0, payResult);
          if (_user != null) {
            _user!['balance'] -= payResult['amount'];
          }
        });
      }
    }
  }

  Future<void> _handlePayAnyone() async {
    await Navigator.pushNamed(context, '/pay');
    if (mounted) {
      _loadData(showLoading: false);
    }
  }

  void _handleViewBalance() {
    widget.onSwitchTab?.call(1);
  }

  Widget _buildPeopleGrid() {
    final totalPeople = _recentPeople.length;

    int countToShow;
    if (!_isPeopleExpanded) {
      if (totalPeople > 8) {
        countToShow = 7; // 7 people + 1 arrow
      } else {
        countToShow = totalPeople;
      }
    } else {
      // Expanded
      // Limit to 15 people + 1 arrow = 16 slots.
      countToShow = totalPeople > 15 ? 15 : totalPeople;
    }

    List<Widget> items = [];
    for (int i = 0; i < countToShow; i++) {
      items.add(_buildPersonItem(_recentPeople[i]));
    }

    if (totalPeople > 8) {
      items.add(_buildArrowItem(isDown: !_isPeopleExpanded));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // GridView inside LayoutBuilder to respect parent width
        return GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.75,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          children: items,
        );
      },
    );
  }

  Widget _buildPersonItem(
    Map<String, dynamic> person, {
    bool isMerchant = false,
  }) {
    String name = person['username'] ?? "User";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Clean up "User123..." names to just show "123..." or a formatted name
    if (name.startsWith('User') && name.length > 4) {
      if (RegExp(r'^User\d+$').hasMatch(name)) {
        name = name.substring(4); // Show just the number
      }
    }

    final initial = name.isNotEmpty ? name[0].toUpperCase() : "?";

    // Generate a consistent color based on the name
    final List<Color> avatarColors = [
      const Color(0xFFE57373), // Red
      const Color(0xFFBA68C8), // Purple
      const Color(0xFF7986CB), // Indigo
      const Color(0xFF4FC3F7), // Light Blue
      const Color(0xFF4DB6AC), // Teal
      const Color(0xFF81C784), // Green
      const Color(0xFFFFB74D), // Orange
      const Color(0xFFA1887F), // Brown
      const Color(0xFF90A4AE), // Blue Grey
    ];
    final color = avatarColors[name.hashCode.abs() % avatarColors.length];

    return GestureDetector(
      onTap: () {
        final upi = person['upi_id'];
        final mobile = person['mobile_number'];
        Navigator.pushNamed(
          context,
          '/conversation',
          arguments: {
            'upi': upi,
            'name': name,
            'mobile': mobile,
            'isMerchant': isMerchant,
          },
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildArrowItem({required bool isDown}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isPeopleExpanded = !_isPeopleExpanded;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDown ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDown ? "More" : "Less",
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantGrid() {
    final totalMerchants = _recentMerchants.length;

    int countToShow;
    if (!_isMerchantsExpanded) {
      if (totalMerchants > 8) {
        countToShow = 7; // 7 merchants + 1 arrow
      } else {
        countToShow = totalMerchants;
      }
    } else {
      // Expanded
      countToShow = totalMerchants > 15 ? 15 : totalMerchants;
    }

    List<Widget> items = [];
    for (int i = 0; i < countToShow; i++) {
      items.add(_buildPersonItem(_recentMerchants[i], isMerchant: true));
    }

    if (totalMerchants > 8) {
      items.add(_buildMerchantArrowItem(isDown: !_isMerchantsExpanded));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.75,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          children: items,
        );
      },
    );
  }

  Widget _buildMerchantArrowItem({required bool isDown}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isMerchantsExpanded = !_isMerchantsExpanded;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDown ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDown ? "More" : "Less",
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.grey[800]
                  : Colors.grey.shade100, // Light background for icon
            ),
            child: Icon(
              icon,
              color: isDark ? const Color(0xFF9E65E6) : const Color(0xFF5F259F),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: isDark ? Colors.grey[400] : Colors.grey,
          ),
        ],
      ),
    );
  }
}
