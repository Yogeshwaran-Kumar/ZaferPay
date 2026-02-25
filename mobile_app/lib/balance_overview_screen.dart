import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'mcc_helper.dart';
import 'utils.dart';
import 'spend_analysis_screen.dart';

class BalanceOverviewScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<dynamic> history;

  const BalanceOverviewScreen({
    super.key,
    required this.user,
    required this.history,
  });

  @override
  State<BalanceOverviewScreen> createState() => _BalanceOverviewScreenState();
}

class _BalanceOverviewScreenState extends State<BalanceOverviewScreen> {
  bool _isLoading = true;
  double _balance = 0.0;
  List<Map<String, dynamic>> _topCategories = [];
  String _currentMonth = '';

  @override
  void initState() {
    super.initState();
    _currentMonth = DateFormat('MMMM').format(DateTime.now());
    _loadData();
  }

  void _loadData() {
    _balance = (widget.user['balance'] ?? 0.0).toDouble();
    _calculateTopCategories();
    setState(() {
      _isLoading = false;
    });
  }

  void _calculateTopCategories() {
    final now = DateTime.now();
    final currentMonthStr = DateFormat('yyyy-MM').format(now);

    Map<String, double> categorySpends = {};

    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;

      final isDebit = tx['sender_upi_id'] == widget.user['upi_id'];
      if (!isDebit) continue; // Only count outward spends

      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);

        if (txMonthStr == currentMonthStr) {
          final mcc = tx['receiver_mcc'];
          String category = 'Others';

          if (mcc != null && MccHelper.isMerchant(mcc)) {
            final domain = MccHelper.getDomain(mcc.toString());
            category = MccHelper.getGroupedCategory(domain);
          } else if (MccHelper.isPersonal(mcc)) {
            category = 'People';
          }

          final amount = (tx['amount'] ?? 0).toDouble();
          categorySpends[category] = (categorySpends[category] ?? 0) + amount;
        }
      } catch (e) {
        // Skip invalid dates
      }
    }

    var sortedCategories = categorySpends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // Descending order

    _topCategories = sortedCategories.take(2).map((e) {
      return {'name': e.key, 'amount': e.value};
    }).toList();
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food & Drinks':
        return Icons.restaurant;
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Transport':
        return Icons.directions_car;
      case 'Bills & Utilities':
        return Icons.receipt;
      case 'Entertainment':
        return Icons.movie;
      case 'Health':
        return Icons.medical_services;
      case 'People':
        return Icons.people;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food & Drinks':
        return Colors.orange;
      case 'Shopping':
        return Colors.pink;
      case 'Transport':
        return Colors.blue;
      case 'Bills & Utilities':
        return Colors.purple;
      case 'Entertainment':
        return Colors.red;
      case 'Health':
        return Colors.teal;
      case 'People':
        return Colors.indigo;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Background: Clean look matching home screen
    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bgColor,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Balance Header ---
                    Text(
                      'Available balance',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '₹${formatAmount(_balance)}',
                              style: GoogleFonts.outfit(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            // Refresh logic could go here if needed
                          },
                          child: Icon(
                            Icons.sync,
                            size: 24,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Opacity(
                            opacity: value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E2630)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.user['username'] ?? 'User',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    widget.user['upi_id'] ?? '',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withAlpha(25)
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "ZaferPay Bank", // Mocked Bank Name as requested or could pull from DB if available
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // --- Spend Analysis Header ---
                    Text(
                      'Your spend analysis for $_currentMonth',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Top Categories List ---
                    if (_topCategories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            "No spends this month yet.",
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else
                      ..._topCategories.map(
                        (cat) => _buildCategoryItem(
                          cat['name'],
                          cat['amount'],
                          isDark,
                        ),
                      ),

                    const SizedBox(height: 32),

                    // --- Check Spend Analysis Button ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SpendAnalysisScreen(
                                user: widget.user,
                                history: widget.history,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF1E2630)
                              : const Color(0xFFF0F0F0),
                          foregroundColor: isDark
                              ? Colors.white
                              : Colors.black87,
                          elevation: 0,
                          side: isDark
                              ? const BorderSide(color: Colors.white10)
                              : BorderSide.none,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Check spend analysis',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // --- Powered by ZaferPay ---
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.security,
                            size: 14,
                            color: Colors.blue.shade400,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Powered by ZaferPay',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryItem(String name, double amount, bool isDark) {
    // Find max spend to calculate bar width, or just use a fixed percentage logic
    double maxSpend = _topCategories.isNotEmpty
        ? _topCategories.first['amount']
        : 1;
    if (maxSpend == 0) maxSpend = 1;

    // Make sure the bar is at least 10% wide so it's visible, up to 60% of the row
    double fillFraction = amount / maxSpend;
    // Base width as fraction of screen roughly
    double barMaxWidth = 100.0;
    double barWidth = (fillFraction * barMaxWidth).clamp(20.0, barMaxWidth);

    IconData icon = _getCategoryIcon(name);
    Color color = _getCategoryColor(name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2630) : const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
              border: isDark ? Border.all(color: Colors.white10) : null,
            ),
            child: Icon(
              icon,
              color: isDark ? Colors.white : Colors.black87,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Name and Bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: isDark
                        ? Colors.grey.shade300
                        : const Color(0xFF4B5563),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutQuart,
                  height: 6,
                  width: barWidth,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
          // Amount
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.35,
            ),
            child: FittedBox(
              alignment: Alignment.centerRight,
              fit: BoxFit.scaleDown,
              child: Text(
                '₹${formatAmount(amount)}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
