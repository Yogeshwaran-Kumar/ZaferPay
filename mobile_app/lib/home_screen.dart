import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'contact_service.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/transaction_service.dart';
import 'services/user_service.dart';
import 'utils.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/risk_status_widget.dart';
// To reuse logic if needed, or better, keep logic in widget
import 'mcc_helper.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onSwitchTab;

  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  final _apiClient = ApiClient();
  late final _authService = AuthService(_apiClient);
  late final _userService = UserService(_apiClient);
  late final _transactionService = TransactionService(
    _apiClient,
    _authService,
    _userService,
  );
  Map<String, dynamic>? _user;
  List<dynamic> _history = [];
  List<dynamic> _recentPeople = [];
  List<dynamic> _recentMerchants = [];
  List<dynamic> _pendingRequests = [];
  bool _isLoading = true;
  bool _isPeopleExpanded = false;

  // RISK STATE
  bool _isRisk = false;
  final String _riskScore = 'SAFE'; // SAFE, WARN, HIGH
  final String _riskTitle = "";
  final String _riskDescription = "";
  final List<Widget> _riskFactors = [];

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
      _pendingRequests = cached['pending_requests'] ?? [];
      _isLoading = false; // No spinner ever!
    } else {
      // Only trigger async load if sync failed
      _loadData();
    }

    // Start polling every 2 seconds for near-instant updates
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        // Optimized: Only fetch what's needed or rely on _loadData's internal checks
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
      _updateStateWithData(data);
    } catch (e) {
      if (kDebugMode) print("Home Screen Load Error: $e");
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
    final pending = data['pending_requests'];

    if (user == null) {
      if (kDebugMode) {
        print(
          "Skipping state update: User data is null (Request likely failed)",
        );
      }
      return;
    }

    setState(() {
      _user = user;
      // Only update lists if we have a valid user response (robustness)
      if (history != null) {
        _history = history;
      }
      if (people != null) {
        _recentPeople = people;
      }
      if (merchants != null) {
        _recentMerchants = merchants;
      }
      if (pending != null) {
        _pendingRequests = pending;
      }

      // Update App Badge
      final totalUnread = data['total_unread'] as int? ?? 0;
      FlutterAppBadger.updateBadgeCount(totalUnread);
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
    final textColor = isDark ? Colors.white : const Color(0xFF1F1F1F);

    // RISK SCREEN INTERCEPT
    if (_isRisk) {
      return RiskStatusWidget(
        isRisk: _isRisk,
        isHighRisk: _riskScore == 'HIGH',
        riskScore: _riskScore,
        title: _riskTitle.isNotEmpty
            ? _riskTitle
            : (_riskScore == 'HIGH'
                  ? "CRITICAL RISK DETECTED"
                  : "SECURITY WARNING"),
        description: _riskDescription,
        riskFactors: _riskFactors.isNotEmpty
            ? _riskFactors
            : [
                _buildRiskFactorItem(
                  _riskDescription.isNotEmpty
                      ? _riskDescription
                      : "Unusual account activity detected.",
                  Icons.warning_amber_rounded,
                  _riskScore == 'HIGH'
                      ? const Color(0xFFEF5350)
                      : Colors.orange,
                  isDark,
                ),
              ],
        onProceed: () {
          setState(() {
            _isRisk = false; // Dismiss warning
          });
        },
        proceedButtonText: "I Understand, Proceed",
        showBackButton:
            false, // Don't allow backing out of home screen warning easily
      );
    }

    // Background: Clean look
    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 1. Top Bar (Search + Profile)
              _buildTopBar(isDark),

              // 2. Scanner Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildScannerCard(isDark),
              ),

              const SizedBox(height: 24),

              // 3. Quick Actions (Pay anyone, Balance)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildQuickActionCard(
                        icon: Icons.send_rounded,
                        label: "Pay anyone",
                        onTap: _handlePayAnyone,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildQuickActionCard(
                        icon: Icons.account_balance_wallet_rounded,
                        label: "Check balance",
                        onTap: _handleViewBalance,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),

              // Pending Requests Banner (Moved)
              if (_pendingRequests.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildPendingRequestsSection(isDark, textColor),
              ],

              const SizedBox(height: 32),

              // 4. People Section
              if (_recentPeople.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "People",
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      icon: Icons.history_rounded,
                      text: "See transaction history",
                      onTap: () {
                        widget.onSwitchTab?.call(1);
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildListItem(
                      icon: Icons.settings_outlined,
                      text: "View settings",
                      onTap: () {
                        Navigator.pushNamed(context, '/settings');
                      },
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

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
                      style: GoogleFonts.outfit(
                        fontSize: 14,
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

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // Search Bar
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/pay');
              },
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2630) : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Pay friends or merchants",
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white60 : Colors.grey.shade500,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: getAvatarColor(_user!['username']),
              ),
              child: Center(
                child: Text(
                  _user!['username'][0].toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerCard(bool isDark) {
    return GestureDetector(
      onTap: _handleScan,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 160),
        decoration: BoxDecoration(
          color: const Color(0xFF00B9F1), // SafePay Blue
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF00B9F1), Color(0xFF0288D1)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00B9F1).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                Icons.qr_code_scanner_rounded,
                size: 140,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Scan any QR code",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      "Pay at shops or send to friends",
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2630) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF00B9F1), size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1F1F1F),
              ),
            ),
          ],
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

    // Use deterministic color from utils
    final color = getAvatarColor(name);

    return GestureDetector(
      onTap: () {
        final upi = person['upi_id'];
        final mobile = person['mobile_number'];
        final id = person['id'];
        Navigator.pushNamed(
          context,
          '/conversation',
          arguments: {
            'upi': upi,
            'name': name,
            'mobile': mobile,
            'id': id,
            'isMerchant': isMerchant,
          },
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 26,
                    ),
                  ),
                ),
              ),
              // Badge
              if ((person['unread_count'] ?? 0) > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    child: Center(
                      child: Text(
                        person['unread_count'] > 9
                            ? "9+"
                            : "${person['unread_count']}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF1F1F1F),
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDown
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDown ? "More" : "Less",
            style: GoogleFonts.outfit(
              fontSize: 13,
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
    if (totalMerchants > 8) {
      countToShow = 7;
    } else {
      countToShow = totalMerchants;
    }

    List<Widget> items = [];
    for (int i = 0; i < countToShow; i++) {
      items.add(_buildPersonItem(_recentMerchants[i], isMerchant: true));
    }

    if (totalMerchants > 8) {
      items.add(_buildMerchantArrowItem(isDown: true));
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
    // Reusing same logic as People Arrow, or could be separate if needed
    return _buildArrowItem(isDown: isDown);
  }

  Widget _buildListItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.grey.withValues(alpha: 0.1)
                  : Colors.blue.withValues(alpha: 0.05), // Very light blue tint
            ),
            child: Icon(icon, color: const Color(0xFF00B9F1), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: isDark ? Colors.grey[400] : Colors.grey[400],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsSection(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF00B9F1).withValues(alpha: 0.1)
              : const Color(0xFF00B9F1).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? const Color(0xFF00B9F1).withValues(alpha: 0.3)
                : const Color(0xFF00B9F1).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B9F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      color: isDark
                          ? const Color(0xFF00B9F1)
                          : const Color(0xFF0077C2),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_pendingRequests.length} Pending Request${_pendingRequests.length > 1 ? 's' : ''}',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFF81D4FA)
                            : const Color(0xFF0277BD),
                      ),
                    ),
                  ),
                  if (_pendingRequests.length > 2)
                    GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/pending-requests').then((
                          _,
                        ) {
                          _loadData(showLoading: false);
                        });
                      },
                      child: Text(
                        "View all",
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF81D4FA)
                              : const Color(0xFF0277BD),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Request items (show max 2)
            ...(_pendingRequests.take(2).map((req) {
              final amount = req['amount'];
              final name =
                  req['requester_name'] ?? req['requester_upi_id'] ?? 'Unknown';
              final reason = req['reason'] ?? '';
              final requestId = req['id'];

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/conversation',
                      arguments: {
                        'upi': req['requester_upi_id'],
                        'name': name,
                        'id': req['requester_id'],
                        'isValid': true,
                        'pendingRequest': req,
                      },
                    ).then((_) => _loadData(showLoading: false));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.2)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.transparent
                            : const Color(0xFF00B9F1).withValues(alpha: 0.1),
                      ),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: const Color(
                              0xFF00B9F1,
                            ).withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$name',
                                style: GoogleFonts.outfit(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text:
                                          'requested ₹${formatAmount(amount)}',
                                      style: GoogleFonts.outfit(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey.shade700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (reason.isNotEmpty)
                                      TextSpan(
                                        text: ' ($reason)',
                                        style: GoogleFonts.outfit(
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.grey.shade500,
                                          fontSize: 15,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Action buttons
                        TextButton(
                          onPressed: () async {
                            final success = await _transactionService
                                .cancelPaymentRequest(requestId);
                            if (success && mounted) {
                              _loadData(showLoading: false);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Decline',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/amount',
                              arguments: {
                                'upi': req['requester_upi_id'],
                                'name': name,
                                'isRequestPayment': true,
                                'paymentRequestId': requestId,
                                'prefillAmount': amount,
                                'requestReason': reason,
                              },
                            ).then((_) => _loadData(showLoading: false));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B9F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Pay',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ), // Column
                  ), // Container
                ), // GestureDetector
              ); // Padding
            })),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskFactorItem(
    String desc,
    IconData icon,
    Color iconColor,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: iconColor),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            desc,
            style: TextStyle(
              fontSize: 16,
              color: (isDark ? Colors.white : Colors.black87).withValues(
                alpha: 0.9,
              ),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
