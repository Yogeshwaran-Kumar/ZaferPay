import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'spending_limit_screen.dart';
import 'services/app_localizations.dart';

/// A self-contained tab screen that LIVE-polls user + history data
/// and passes fresh data into SpendAnalysisScreen so the spending
/// limit card always reflects the most recent transactions.
class SpendingLimitTabScreen extends StatefulWidget {
  const SpendingLimitTabScreen({super.key});

  @override
  State<SpendingLimitTabScreen> createState() => _SpendingLimitTabScreenState();
}

class _SpendingLimitTabScreenState extends State<SpendingLimitTabScreen>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiService();

  Map<String, dynamic>? _user;
  List<dynamic> _history = [];
  bool _isLoading = true;
  bool _hasError = false;

  Timer? _pollTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData(isInitial: true);

    // Poll every 3 seconds so the limit card updates as soon as
    // a transaction is confirmed (matches HomeScreen polling cadence).
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool isInitial = false}) async {
    if (isInitial) {
      // 1. Show cached data immediately for a no-flicker first render
      final cached = await _api.getCachedHomeData();
      if (cached != null && mounted) {
        setState(() {
          _user = cached['user'] as Map<String, dynamic>?;
          _history = (cached['history'] as List<dynamic>?) ?? [];
          _isLoading = _user == null;
        });
      }
    }

    // 2. Always fetch fresh data from the network
    try {
      final homeData = await _api.getHomeScreenData();
      if (!mounted) return;
      setState(() {
        _user = homeData['user'] as Map<String, dynamic>?;
        _history = (homeData['history'] as List<dynamic>?) ?? [];
        _isLoading = false;
        _hasError = _user == null;
      });
    } catch (_) {
      if (mounted && _user == null) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FA);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasError || _user == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('spending_limit.error_load') ??
                    'Could not load spending data',
                style: GoogleFonts.outfit(
                  color: Colors.grey.shade500,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadData(isInitial: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B9F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)?.translate('common.retry') ??
                      'Retry',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SpendingLimitScreen(
      user: _user!,
      history: _history,
      showBackButton: false,
    );
  }
}
