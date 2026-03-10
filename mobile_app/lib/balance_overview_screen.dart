import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'utils.dart';
import 'spend_analysis_screen.dart';
import 'services/app_localizations.dart';
import 'mcc_helper.dart';

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
    final myUpi = widget.user['upi_id'];

    Map<String, double> categorySpends = {};
    bool hasCircleSpends = false;

    // First pass: Check if there are any circle spends
    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;
      final txDateStr = tx['timestamp'];
      if (txDateStr == null) continue;

      try {
        final txDate = DateTime.parse(txDateStr).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);
        if (txMonthStr != currentMonthStr) continue;

        final isDebit =
            tx['sender_upi_id'] == myUpi || tx['initiated_by_upi'] == myUpi;
        if (!isDebit) continue;

        if (tx['initiated_by_upi'] != null) {
          hasCircleSpends = true;
          break;
        }
      } catch (e) {
        /**/
      }
    }

    // Second pass: Aggregate based on strategy
    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;
      final txDateStr = tx['timestamp'];
      if (txDateStr == null) continue;

      try {
        final txDate = DateTime.parse(txDateStr).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);
        if (txMonthStr != currentMonthStr) continue;

        final isDebit =
            tx['sender_upi_id'] == myUpi || tx['initiated_by_upi'] == myUpi;
        if (!isDebit) continue;

        final amount = (tx['amount'] ?? 0).toDouble();
        String category = 'Others';

        if (hasCircleSpends) {
          // Rule: Show UPI Circle and Personal only
          if (tx['initiated_by_upi'] != null) {
            category = 'UPI Circle';
          } else {
            category = 'Personal';
          }
        } else {
          // Rule: Show functional categories (Food, Shopping, etc)
          final mcc = tx['mcc'];
          final note = tx['remark'] ?? tx['note'];

          String? categoryFromNote = MccHelper.getCategoryFromNote(note);
          if (categoryFromNote != null) {
            category = categoryFromNote;
          } else {
            category = MccHelper.getGroupedCategory(MccHelper.getDomain(mcc));
          }

          // If it's a P2P transfer (Personal), we can label it explicitly
          if (category == 'People') {
            category = 'P2P / Friends';
          }
        }

        categorySpends[category] = (categorySpends[category] ?? 0) + amount;
      } catch (e) {
        /**/
      }
    }

    var sortedCategories = categorySpends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    _topCategories = sortedCategories.map((e) {
      return {'name': e.key, 'amount': e.value};
    }).toList();
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Personal':
      case 'P2P / Friends':
        return const Color(0xFF00B9F1);
      case 'UPI Circle':
        return const Color(0xFF4CAF50);
      case 'Food & Drinks':
        return const Color(0xFFFF9800);
      case 'Shopping':
        return const Color(0xFFE91E63);
      case 'Transport':
        return const Color(0xFF9C27B0);
      case 'Bills & Utilities':
        return const Color(0xFF3F51B5);
      case 'Entertainment':
        return const Color(0xFFF44336);
      case 'Health':
        return const Color(0xFF009688);
      case 'Education':
        return const Color(0xFF795548);
      case 'Investments':
        return const Color(0xFF607D8B);
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    // --- Redesigned Balance Card ---
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF1E2630),
                                  const Color(0xFF161C24),
                                ]
                              : [Colors.white, const Color(0xFFF1F5F9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: isDark
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.white,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('analysis.available_balance') ??
                                'Available balance',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '₹${formatAmount(_balance)}',
                                    style: GoogleFonts.notoSans(
                                      fontSize: 48, // Increased size
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.blue.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.sync,
                                    size: 22,
                                    color: isDark
                                        ? Colors.blue.shade300
                                        : Colors.blue.shade600,
                                  ),
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- User Card ---
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
                                    widget.user['username'] ?? "User",
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
                            Text(
                              "ZaferPay Bank",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // --- Spend Analysis Header ---
                    Text(
                      (AppLocalizations.of(context)?.translate(
                                'analysis.spend_analysis_for_month',
                              ) ??
                              'Your spend analysis for {month}')
                          .replaceAll('{month}', _currentMonth),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Top Categories Content ---
                    if (_topCategories.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            "No spends this month yet.",
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else ...[
                      Center(
                        child: SizedBox(
                          width: 220,
                          height: 220,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, progress, _) {
                              return CustomPaint(
                                painter: _PieChartPainter(
                                  categories: _topCategories,
                                  getColor: (name) => _getCategoryColor(name),
                                  total: _topCategories.fold(
                                    0.0,
                                    (sum, cat) =>
                                        sum + (cat['amount'] as double),
                                  ),
                                  progress: progress,
                                  isDark: isDark,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Total Spends',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '₹${formatAmount(_topCategories.fold(0.0, (sum, cat) => sum + (cat['amount'] as double)))}',
                                          style: GoogleFonts.notoSans(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _topCategories.map((cat) {
                          final total = _topCategories.fold(
                            0.0,
                            (sum, c) => sum + (c['amount'] as double),
                          );
                          final pct = total > 0
                              ? (cat['amount'] as double) / total * 100
                              : 0.0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withAlpha(15)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade100,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getCategoryColor(cat['name']),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${cat['name']} ${pct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 40),

                    // --- Action Button ---
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
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(
                                context,
                              )?.translate('analysis.check_spend_analysis') ??
                              'Check detailed analysis',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
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
                            'Powered by ZaferPay Secure',
                            style: GoogleFonts.notoSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade500,
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
}

// ── Pie chart painter ──────────────────────────────────────────────────────
class _PieChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> categories;
  final Color Function(String) getColor;
  final double total;
  final double progress;
  final bool isDark;

  _PieChartPainter({
    required this.categories,
    required this.getColor,
    required this.total,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || categories.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final strokeWidth = size.width * 0.16;
    final rect = Rect.fromCircle(
      center: center,
      radius: outerRadius - strokeWidth / 2,
    );
    const startAngle = -math.pi / 2;
    const gapAngle = 0.04;

    double currentAngle = startAngle;

    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final fraction = (cat['amount'] as double) / total;
      final sweepAngle = fraction * 2 * math.pi * progress - gapAngle;
      if (sweepAngle <= 0) {
        currentAngle += fraction * 2 * math.pi * progress;
        continue;
      }

      final paint = Paint()
        ..color = getColor(cat['name'] as String)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        currentAngle + gapAngle / 2,
        sweepAngle,
        false,
        paint,
      );
      currentAngle += fraction * 2 * math.pi * progress;
    }

    final shadowPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, outerRadius - strokeWidth, shadowPaint);
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      old.progress != progress || old.categories != categories;
}
