import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'utils.dart';
import 'mcc_helper.dart';
import 'transaction_history_screen.dart';
import 'spending_limit_pin_screen.dart';

class SpendingLimitScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<dynamic> history;
  final bool showBackButton;

  const SpendingLimitScreen({
    super.key,
    required this.user,
    required this.history,
    this.showBackButton = true,
  });

  @override
  State<SpendingLimitScreen> createState() => _SpendingLimitScreenState();
}

class _SpendingLimitScreenState extends State<SpendingLimitScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(SpendingLimitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculate if history length changed OR if spending limit settings changed.
    // This ensures the limit card updates live when a new transaction comes in.
    final historyChanged =
        oldWidget.history.length != widget.history.length ||
        oldWidget.user['spending_limit'] != widget.user['spending_limit'] ||
        oldWidget.user['spending_limit_period'] !=
            widget.user['spending_limit_period'];
    if (historyChanged) {
      setState(() {});
    }
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
      case 'Education':
        return Icons.school;
      case 'Investments':
        return Icons.trending_up;
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
      case 'Education':
        return Colors.lightBlue;
      case 'Investments':
        return Colors.green;
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
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).iconTheme.color,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: widget.showBackButton
            ? null
            : Text(
                'Analytics',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Spend Analysis Card ──
              _buildSpendAnalysisCard(isDark),

              const SizedBox(height: 16),

              // ── Limit Card ──
              _buildLimitCard(isDark),

              const SizedBox(height: 32),

              // Footer
              Center(
                child: Text(
                  'Powered by ZaferPay',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _getFrequencyLabel(int p) {
    if (p == 1) return 'Daily';
    if (p == 7) return 'Weekly';
    if (p == 14) return 'Bi-Weekly';
    if (p == 30) return 'Monthly';
    return '$p days';
  }

  void _showSpendingLimitDialog(bool isDark) {
    final currentLimit = widget.user['spending_limit'] != null
        ? (widget.user['spending_limit'] as num).toDouble()
        : null;
    final currentPeriod = widget.user['spending_limit_period'] ?? 1;

    final TextEditingController amountController = TextEditingController(
      text: currentLimit != null ? currentLimit.toStringAsFixed(0) : '',
    );
    int tempPeriod = currentPeriod;
    bool isEnabled = currentLimit != null;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E2630) : Colors.white,
              title: Text(
                'Set Spending Limit',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Enable Limit',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    value: isEnabled,
                    onChanged: (val) {
                      setDialogState(() => isEnabled = val);
                    },
                    activeThumbColor: const Color(0xFF00B9F1),
                  ),
                  if (isEnabled) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount (₹)',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        border: const OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      // Use -1 as sentinel for "Custom"
                      initialValue: [1, 7, 14, 30].contains(tempPeriod)
                          ? tempPeriod
                          : -1,
                      dropdownColor: isDark
                          ? const Color(0xFF1E2630)
                          : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Period',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        ...([1, 7, 14, 30].map((int value) {
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text(_getFrequencyLabel(value)),
                          );
                        })),
                        const DropdownMenuItem<int>(
                          value: -1,
                          child: Text('Custom…'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            if (val == -1) {
                              // Keep tempPeriod as current or reset to 0
                              // to force user to fill in the custom field
                              tempPeriod = -1;
                            } else {
                              tempPeriod = val;
                            }
                          });
                        }
                      },
                    ),

                    // Custom days text field — shown only when Custom is selected
                    if (tempPeriod == -1) ...[
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final customController = TextEditingController(
                            text:
                                (![1, 7, 14, 30].contains(tempPeriod) &&
                                    tempPeriod > 0)
                                ? tempPeriod.toString()
                                : '',
                          );
                          return TextField(
                            controller: customController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Number of days (1 – 365)',
                              labelStyle: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                              border: const OutlineInputBorder(),
                              suffixText: 'days',
                              suffixStyle: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                            onChanged: (val) {
                              final days = int.tryParse(val);
                              if (days != null && days >= 1 && days <= 365) {
                                // Don't call setDialogState here — would reset
                                // cursor. We'll read it on Next tap instead.
                                tempPeriod = days;
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B9F1),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Validate amount first
                    if (isEnabled) {
                      final amt = double.tryParse(amountController.text);
                      if (amt == null || amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid amount'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      if (tempPeriod < 1 || tempPeriod > 365) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please enter a valid period between 1 and 365 days',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }
                    // Close the settings dialog, then navigate to PIN screen
                    Navigator.pop(ctx);
                    _navigateToPinScreen(
                      isEnabled: isEnabled,
                      amount: isEnabled
                          ? double.tryParse(amountController.text)
                          : null,
                      period: tempPeriod,
                    );
                  },
                  child: const Text('Next →'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _navigateToPinScreen({
    required bool isEnabled,
    required double? amount,
    required int period,
  }) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpendingLimitPinScreen(
          isEnabled: isEnabled,
          amount: amount,
          period: period,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null && result is Map && result['success'] == true) {
      final wasEnabled = result['isEnabled'] as bool;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                wasEnabled
                    ? 'Spending limit updated!'
                    : 'Spending limit removed.',
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ── Empty-state helper (shared by both card builders) ──────────────────────
  Widget _buildEmptyLimitState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
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
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 52,
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
          const SizedBox(height: 18),
          Text(
            'No Spending Limit Set',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Set a spending limit to track your expenses and stay on budget.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: () => _showSpendingLimitDialog(isDark),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B9F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              elevation: 0,
            ),
            child: const Text(
              'Set Spending Limit',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 1: Spending Limit ────────────────────────────────────────────────
  Widget _buildLimitCard(bool isDark) {
    final limit = widget.user['spending_limit'] != null
        ? (widget.user['spending_limit'] as num).toDouble()
        : null;
    if (limit == null || limit <= 0) return _buildEmptyLimitState(isDark);

    // ── Shared computations ──
    final period = (widget.user['spending_limit_period'] as num?)?.toInt() ?? 1;
    final String? updatedAtStr = widget.user['spending_limit_updated_at'];
    final now = DateTime.now();
    DateTime limitStart;
    if (updatedAtStr != null) {
      try {
        final updatedAt = DateTime.parse(updatedAtStr).toLocal();
        final setDate = DateTime(
          updatedAt.year,
          updatedAt.month,
          updatedAt.day,
        );
        final today = DateTime(now.year, now.month, now.day);
        final daysSinceSet = today.difference(setDate).inDays;
        final fullCyclesPassed = daysSinceSet >= 0
            ? (daysSinceSet ~/ period)
            : 0;
        limitStart = setDate.add(Duration(days: fullCyclesPassed * period));
      } catch (_) {
        limitStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: period - 1));
      }
    } else {
      limitStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: period - 1));
    }

    double spent = 0.0;
    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;
      if (tx['sender_upi_id'] != widget.user['upi_id']) continue;
      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        if (txDate.isAfter(limitStart)) {
          spent += (tx['amount'] ?? 0).toDouble();
        }
      } catch (_) {}
    }

    final remaining = (limit - spent).clamp(0.0, double.infinity);
    final percent = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final isExceeded = spent >= limit;
    final isCritical = percent >= 0.9 && !isExceeded;
    final isWarning = percent >= 0.75 && !isCritical && !isExceeded;

    Color progressColor = const Color(0xFF00C853);
    if (isExceeded) {
      progressColor = Colors.red;
    } else if (isCritical) {
      progressColor = Colors.red.shade400;
    } else if (isWarning) {
      progressColor = Colors.orange;
    }

    String periodLabel = period == 1
        ? 'Daily'
        : period == 7
        ? 'Weekly'
        : period == 14
        ? 'Bi-Weekly'
        : period == 30
        ? 'Monthly'
        : '$period-Day';

    String statusLabel = isExceeded
        ? 'Limit Reached'
        : isCritical
        ? 'Almost Full'
        : isWarning
        ? 'Nearing Limit'
        : 'On Track';

    Color statusBg = isExceeded || isCritical
        ? Colors.red.withValues(alpha: isDark ? 0.2 : 0.08)
        : isWarning
        ? Colors.orange.withValues(alpha: isDark ? 0.2 : 0.08)
        : Colors.green.withValues(alpha: isDark ? 0.2 : 0.08);

    Color statusFg = isExceeded || isCritical
        ? Colors.red
        : isWarning
        ? Colors.orange
        : const Color(0xFF00C853);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2630) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExceeded || isCritical
              ? Colors.red.withValues(alpha: 0.3)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: progressColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$periodLabel Spending Limit',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // Status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusFg,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Edit button
                  InkWell(
                    onTap: () => _showSpendingLimitDialog(isDark),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 16,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── 3-tile stats row ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _buildStatTile(
                  label: 'Spent',
                  amount: spent,
                  color: progressColor,
                  isDark: isDark,
                  isBold: true,
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              Expanded(
                child: _buildStatTile(
                  label: 'Remaining',
                  amount: remaining,
                  color: isExceeded
                      ? Colors.red
                      : (isDark ? Colors.white70 : Colors.black87),
                  isDark: isDark,
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              Expanded(
                child: _buildStatTile(
                  label: 'Limit',
                  amount: limit,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  isDark: isDark,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ── Animated progress bar ─────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: percent),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      minHeight: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${(value * 100).toStringAsFixed(1)}% used',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Warning / Exceeded banners ────────────────────────────
          if (isExceeded) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Spending limit reached. New payments will be blocked until the limit resets.',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isCritical) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Almost at your limit. Spend carefully — only ₹${formatAmount(remaining)} left.',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Card 2: Spend Analysis ────────────────────────────────────────────────
  Widget _buildSpendAnalysisCard(bool isDark) {
    final limit = widget.user['spending_limit'] != null
        ? (widget.user['spending_limit'] as num).toDouble()
        : null;
    if (limit == null || limit <= 0) return const SizedBox.shrink();

    // Re-compute limitStart & categories
    final period = (widget.user['spending_limit_period'] as num?)?.toInt() ?? 1;
    final String? updatedAtStr = widget.user['spending_limit_updated_at'];
    final now = DateTime.now();
    DateTime limitStart;
    if (updatedAtStr != null) {
      try {
        final updatedAt = DateTime.parse(updatedAtStr).toLocal();
        final setDate = DateTime(
          updatedAt.year,
          updatedAt.month,
          updatedAt.day,
        );
        final today = DateTime(now.year, now.month, now.day);
        final daysSinceSet = today.difference(setDate).inDays;
        final fullCyclesPassed = daysSinceSet >= 0
            ? (daysSinceSet ~/ period)
            : 0;
        limitStart = setDate.add(Duration(days: fullCyclesPassed * period));
      } catch (_) {
        limitStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: period - 1));
      }
    } else {
      limitStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: period - 1));
    }

    double spent = 0.0;
    Map<String, double> categorySpends = {};
    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;
      if (tx['sender_upi_id'] != widget.user['upi_id']) continue;
      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        if (txDate.isAfter(limitStart)) {
          final amt = (tx['amount'] ?? 0).toDouble();
          spent += amt;
          final mcc = tx['receiver_mcc'];
          final note = tx['note'] ?? tx['remark'];
          String category = MccHelper.getCategoryFromNote(note) ?? 'Others';
          if (category == 'Others') {
            if (mcc != null && MccHelper.isMerchant(mcc)) {
              final domain = MccHelper.getDomain(mcc.toString());
              category = MccHelper.getGroupedCategory(domain);
            } else if (MccHelper.isPersonal(mcc)) {
              category = 'People';
            }
          }
          categorySpends[category] = (categorySpends[category] ?? 0) + amt;
        }
      } catch (_) {}
    }

    if (categorySpends.isEmpty) return const SizedBox.shrink();

    final sortedCategories = categorySpends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<Map<String, dynamic>> categories = sortedCategories
        .map((e) => {'name': e.key, 'amount': e.value})
        .toList();

    return Container(
      padding: const EdgeInsets.all(22),
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
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ─────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.pie_chart_rounded,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 10),
              Text(
                'Spend Analysis',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Donut pie chart ───────────────────────────────────────
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
                      categories: categories,
                      getColor: _getCategoryColor,
                      total: spent,
                      progress: progress,
                      isDark: isDark,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${formatAmount(spent)}',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
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

          const SizedBox(height: 20),

          // ── Color-dot legend ──────────────────────────────────────
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: categories.map((cat) {
              final pct = spent > 0
                  ? (cat['amount'] as double) / spent * 100
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

          const SizedBox(height: 20),

          // ── Divider ───────────────────────────────────────────────
          Divider(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
            height: 1,
          ),

          const SizedBox(height: 12),

          // ── Categories list ───────────────────────────────────────
          ...categories.map((cat) {
            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransactionHistoryScreen(
                      showFilters: false,
                      initialDateFrom: limitStart,
                      initialCategory: cat['name'],
                      initialType: 'Money sent',
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 4.0,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getCategoryColor(
                          cat['name'],
                        ).withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        _getCategoryIcon(cat['name']),
                        color: _getCategoryColor(cat['name']),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        cat['name'],
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '₹${formatAmount(cat['amount'])}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required double amount,
    required Color color,
    required bool isDark,
    bool isBold = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '₹${formatAmount(amount)}',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
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
