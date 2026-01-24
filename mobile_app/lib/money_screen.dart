import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'transaction_history_screen.dart';
import 'transaction_details_screen.dart';
import 'balance_check_screen.dart';

class MoneyScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const MoneyScreen({super.key, this.onBack});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _user;
  List<dynamic> _history = [];
  bool _isLoading = true;
  bool _isBalanceVisible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Polling for transaction updates
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _loadData(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    final user = await _api.getMe();
    final history = await _api.getHistory();
    setState(() {
      if (user != null) {
        _user = user;
      }
      if (history != null) {
        _history = history;
      }
      _isLoading = false;
    });
  }

  Future<void> _checkBalance() async {
    if (_user == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            BalanceCheckScreen(mobileNumber: _user!['mobile_number'] ?? ''),
      ),
    );

    if (result == true && mounted) {
      setState(() => _isBalanceVisible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return const Scaffold(body: Center(child: Text('Failed to load data')));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Money',
          style: TextStyle(
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
          ),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        iconTheme: Theme.of(context).iconTheme,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(showLoading: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance Card
              GestureDetector(
                onTap: _isBalanceVisible ? null : _checkBalance,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5F259F), Color(0xFF8E2DE2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5F259F).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Available Balance',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            _isBalanceVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isBalanceVisible
                            ? '₹ ${_user!['balance'].toStringAsFixed(2)}'
                            : '₹ ••••••',
                        style: GoogleFonts.outfit(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (!_isBalanceVisible) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Tap to view balance',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _isBalanceVisible = false);
                          },
                          icon: const Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 16,
                          ),
                          label: const Text(
                            'Hide Balance',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.qr_code,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _user!['upi_id'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Transaction History
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const TransactionHistoryScreen(),
                        ),
                      );
                    },
                    child: const Text('Show More'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_history.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'No transactions yet',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _history.length > 10 ? 10 : _history.length,
                  itemBuilder: (context, index) {
                    final tx = _history[index];
                    final isDebit = tx['sender_upi_id'] == _user!['upi_id'];
                    Color color;

                    if (tx['status'] == 'BLOCKED') {
                      color = Colors.grey;
                    } else if (tx['status'] == 'FAILED') {
                      color = Colors.red;
                    } else {
                      color = isDebit ? Colors.red : Colors.green;
                    }

                    final String displayName = isDebit
                        ? (tx['receiver_name'] as String? ??
                              tx['receiver_upi_id'] as String? ??
                              'Unknown')
                        : (tx['sender_name'] as String? ??
                              tx['sender_upi_id'] as String? ??
                              'Unknown');

                    String formattedDate;
                    try {
                      final dt = DateTime.parse(tx['timestamp']);
                      formattedDate = DateFormat(
                        'yyyy-MM-dd',
                      ).format(dt.toLocal());
                    } catch (e) {
                      formattedDate = tx['timestamp'];
                    }

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TransactionDetailsScreen(
                              transaction: tx,
                              currentUpiId: _user!['upi_id'],
                            ),
                          ),
                        );
                      },
                      child: Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Theme.of(context).cardTheme.color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.1),
                            child: Icon(
                              isDebit
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: color,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedDate,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              if (tx['risk_score'] != 'SAFE')
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tx['risk_score'] == 'HIGH'
                                        ? Colors.red.shade100
                                        : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Risk: ${tx['risk_score']}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: tx['risk_score'] == 'HIGH'
                                          ? Colors.red
                                          : Colors.orange.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isDebit ? '-' : '+'} ₹${tx['amount']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: color,
                                ),
                              ),
                              Text(
                                tx['status'],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
