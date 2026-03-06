import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
    final myUpi = widget.user['upi_id'];
    final isChild = widget.user['bank_name'] == null;

    Map<String, double> categorySpends = {};

    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;

      final isDebit =
          tx['sender_upi_id'] == myUpi || tx['initiated_by_upi'] == myUpi;
      if (!isDebit) continue; // Only count outward spends

      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);

        if (txMonthStr == currentMonthStr) {
          final initiatorName = tx['initiated_by_name'];
          final initiatorUpi = tx['initiated_by_upi'];

          String category = 'Personal';
          if (initiatorUpi != null) {
            if (isChild) {
              category = 'UPI Circle';
            } else {
              category = initiatorName ?? 'UPI Circle';
            }
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

    _topCategories = sortedCategories.map((e) {
      return {'name': e.key, 'amount': e.value};
    }).toList();
  }

  Color _getCategoryColor(String category) {
    if (category == 'Personal') {
      return const Color(0xFF00B9F1); // Signature Blue
    }
    // Deterministic color for child names/Circle
    return getAvatarColor(category);
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

                    // --- Top Categories Chart ---
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
                    else ...[
                      // Donut pie chart
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 200,
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
                                        'Top Spends',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.grey.shade500
                                              : Colors.grey.shade500,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '₹${formatAmount(_topCategories.fold(0.0, (sum, cat) => sum + (cat['amount'] as double)))}',
                                          style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
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

                      const SizedBox(height: 24),

                      // Color-dot legend
                      Center(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _topCategories.map((cat) {
                            final total = _topCategories.fold(
                              0.0,
                              (sum, c) => sum + (c['amount'] as double),
                            );
                            final pct = total > 0
                                ? (cat['amount'] as double) / total * 100
                                : 0.0;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _getCategoryColor(cat['name']),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${cat['name']} ${pct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],

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
    final strokeWidth = size.width * 0.18; // donut ring width
    final innerRadius = outerRadius - strokeWidth;
    final rect = Rect.fromCircle(
      center: center,
      radius: outerRadius - strokeWidth / 2,
    );
    const startAngle = -math.pi / 2; // start from 12 o'clock
    const gapAngle = 0.025; // radians gap between slices

    double currentAngle = startAngle;

    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final fraction = (cat['amount'] as double) / total;
      final sweepAngle = fraction * 2 * math.pi * progress - gapAngle;
      if (sweepAngle <= 0) continue;

      final paint = Paint()
        ..color = getColor(cat['name'] as String)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        rect,
        currentAngle + gapAngle / 2,
        sweepAngle,
        false,
        paint,
      );
      currentAngle += fraction * 2 * math.pi * progress;
    }

    // Draw inner shadow ring (subtle)
    final shadowPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, innerRadius, shadowPaint);
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      old.progress != progress || old.categories != categories;
}
