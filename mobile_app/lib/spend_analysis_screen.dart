import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/app_localizations.dart';
import 'package:intl/intl.dart';
import 'mcc_helper.dart';
import 'utils.dart';
import 'transaction_history_screen.dart';

class SpendAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<dynamic> history;
  final bool showBackButton;

  const SpendAnalysisScreen({
    super.key,
    required this.user,
    required this.history,
    this.showBackButton = true,
  });

  @override
  State<SpendAnalysisScreen> createState() => _SpendAnalysisScreenState();
}

class _SpendAnalysisScreenState extends State<SpendAnalysisScreen> {
  DateTime _selectedMonth = DateTime.now();

  double _incomingStr = 0.0;
  double _outgoingStr = 0.0;

  double _prevOutgoingStr = 0.0;

  List<Map<String, dynamic>> _categories = [];
  double _totalSpend = 0.0;

  // UPI Circle Filters
  String _selectedSource = 'All'; // 'All', 'Personal', 'Circle'

  @override
  void initState() {
    super.initState();
    _calculateDataForMonth();
  }

  @override
  void didUpdateWidget(SpendAnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculate if history length changed OR if spending limit settings changed.
    // This ensures the limit card updates live when a new transaction comes in.
    final historyChanged =
        oldWidget.history.length != widget.history.length ||
        oldWidget.user['spending_limit'] != widget.user['spending_limit'] ||
        oldWidget.user['spending_limit_period'] !=
            widget.user['spending_limit_period'];
    if (historyChanged) {
      _calculateDataForMonth();
    }
  }

  void _calculateDataForMonth() {
    final selectedMonthStr = DateFormat('yyyy-MM').format(_selectedMonth);

    // Previous month relative to selected month
    final prevMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month - 1,
      1,
    );
    final prevMonthStr = DateFormat('yyyy-MM').format(prevMonth);

    double incoming = 0.0;
    double outgoing = 0.0;
    double prevOutgoing = 0.0;

    double monthlyTotalOut = 0.0;

    Map<String, double> categorySpends = {};
    bool selectionHasCircleSpends = false;

    // Calculate totals across ALL sources first for the summary cards
    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;
      final myUpi = widget.user['upi_id'];
      final isDebit =
          tx['sender_upi_id'] == myUpi || tx['initiated_by_upi'] == myUpi;
      final amount = (tx['amount'] ?? 0).toDouble();

      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);

        if (txMonthStr == selectedMonthStr) {
          if (isDebit) {
            monthlyTotalOut += amount;
            if (tx['initiated_by_upi'] != null) {
              // Already handled by checking initiated_by_upi
            }
            final mcc = tx['receiver_mcc'] ?? tx['mcc'];
            final note = tx['note'] ?? tx['remark'];
            String? categoryFromNote = MccHelper.getCategoryFromNote(note);
            String category = 'Others';
            if (categoryFromNote != null) {
              category = categoryFromNote;
            } else {
              category = MccHelper.getGroupedCategory(
                MccHelper.getDomain(mcc?.toString()),
              );
            }
            if (category == 'People' || category == 'P2P / Friends') {
              // P2P total logic removed as it's handled by individual categories list
            }
          }
        }
      } catch (_) {}
    }

    // First pass: Check if the current selection (All/Circle) has circle spends to determine strategy
    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;
      final txDateStr = tx['timestamp'];
      if (txDateStr == null) continue;

      try {
        final txDate = DateTime.parse(txDateStr).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);
        if (txMonthStr != selectedMonthStr) continue;

        if (tx['initiated_by_upi'] != null &&
            tx['initiated_by_upi'] != widget.user['upi_id']) {
          selectionHasCircleSpends = true;
          break;
        }
      } catch (e) {
        /**/
      }
    }

    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;

      final myUpi = widget.user['upi_id'];
      final isDebit =
          tx['sender_upi_id'] == myUpi || tx['initiated_by_upi'] == myUpi;
      final isCredit = tx['receiver_upi_id'] == myUpi;
      final isChild = widget.user['bank_name'] == null;

      final amount = (tx['amount'] ?? 0).toDouble();

      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);

        if (txMonthStr == selectedMonthStr) {
          // Source Filter Logic
          final isCircle = tx['initiated_by_upi'] != null;
          final initiatorName = tx['initiated_by_name'];
          final initiatorUpi = tx['initiated_by_upi'];

          if (isDebit) {
            // Functional categorization logic
            final mcc = tx['receiver_mcc'] ?? tx['mcc'];
            final note = tx['note'] ?? tx['remark'];
            String category = 'Others';

            String? catFromNote = MccHelper.getCategoryFromNote(note);
            if (catFromNote != null) {
              category = catFromNote;
            } else {
              category = MccHelper.getGroupedCategory(
                MccHelper.getDomain(mcc?.toString()),
              );
            }

            final isCircleTransfer =
                category == 'UPI Circle' || tx['is_circle_payment'] == true;

            if (_selectedSource == 'Personal' &&
                (isCircle || isCircleTransfer)) {
              continue;
            }
            if (_selectedSource == 'UPI Circle') {
              if (!isCircle && !isCircleTransfer) continue;
              if (isChild && initiatorUpi != myUpi) continue;
            }

            if (!['All', 'Personal', 'UPI Circle'].contains(_selectedSource) &&
                initiatorName != _selectedSource) {
              continue;
            }

            outgoing += amount;

            if (_selectedSource == 'All' && selectionHasCircleSpends) {
              // Group circle spends collectively as requested
              if (isCircle || isCircleTransfer) {
                category = 'UPI Circle';
              } else {
                category = 'Personal';
              }
            } else {
              if (category == 'People') {
                category = 'P2P / Friends';
              }
            }

            categorySpends[category] = (categorySpends[category] ?? 0) + amount;
          } else if (isCredit) {
            incoming += amount;
          }
        } else if (txMonthStr == prevMonthStr) {
          if (isDebit) {
            prevOutgoing += amount;
          }
        }
      } catch (e) {
        /**/
      }
    }

    var sortedCategories = categorySpends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    setState(() {
      _incomingStr = incoming;
      _outgoingStr = outgoing;
      _prevOutgoingStr = prevOutgoing;
      _totalSpend = monthlyTotalOut;

      _categories = sortedCategories.map((e) {
        return {'name': e.key, 'amount': e.value};
      }).toList();
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
        1,
      );
      _calculateDataForMonth();
    });
  }

  void _showMonthYearPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final now = DateTime.now();
        // Generate last 24 months for selection
        final List<DateTime> months = List.generate(24, (index) {
          return DateTime(now.year, now.month - index, 1);
        });

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  AppLocalizations.of(
                        context,
                      )?.translate('analysis.select_month_year') ??
                      'Select Month & Year',
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: months.length,
                  itemBuilder: (context, index) {
                    final month = months[index];
                    final isSelected =
                        month.year == _selectedMonth.year &&
                        month.month == _selectedMonth.month;
                    return ListTile(
                      title: Text(
                        (AppLocalizations.of(
                                  context,
                                )?.translate('analysis.month_year') ??
                                '{month} {year}')
                            .replaceAll(
                              '{month}',
                              DateFormat('MMMM').format(month),
                            )
                            .replaceAll(
                              '{year}',
                              DateFormat('yyyy').format(month),
                            ),
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.blue
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedMonth = month;
                          _calculateDataForMonth();
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Personal':
      case 'P2P / Friends':
      case 'People':
        return Icons.people;
      case 'UPI Circle':
        return Icons.supervised_user_circle;
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
      case 'Education':
        return Icons.school;
      case 'Investments':
        return Icons.trending_up;
      case 'Tea & Snacks':
        return Icons.coffee;
      case 'School':
        return Icons.school;
      case 'Hospital':
        return Icons.local_hospital;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Personal':
      case 'P2P / Friends':
      case 'People':
        return const Color(0xFF00B9F1);
      case 'UPI Circle':
        return const Color(0xFF4CAF50);
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
      case 'Education':
        return Colors.lightBlue;
      case 'Investments':
        return Colors.green;
      case 'Tea & Snacks':
        return Colors.brown;
      case 'School':
        return Colors.indigo;
      case 'Hospital':
        return Colors.redAccent;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final monthName = DateFormat('MMM yyyy').format(_selectedMonth);

    final prevMonthName = DateFormat(
      'MMMM',
    ).format(DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1));

    final diff = _outgoingStr - _prevOutgoingStr;
    final isMore = diff > 0;
    final diffAbs = diff.abs();

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
            ? Text(
                AppLocalizations.of(
                      context,
                    )?.translate('analysis.spend_analysis') ??
                    'Spend Analysis',
                style: GoogleFonts.notoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              )
            : Text(
                AppLocalizations.of(
                      context,
                    )?.translate('analysis.monthly_summary') ??
                    'Monthly Summary',
                style: GoogleFonts.notoSans(
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
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(
                            context,
                          )?.translate('analysis.monthly_summary') ??
                          'Monthly Summary',
                      style: GoogleFonts.notoSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2630) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _changeMonth(-1),
                          child: Icon(
                            Icons.chevron_left,
                            size: 20,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showMonthYearPicker,
                          child: Text(
                            monthName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            if (_selectedMonth.year == DateTime.now().year &&
                                _selectedMonth.month == DateTime.now().month) {
                              return;
                            }
                            _changeMonth(1);
                          },
                          child: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color:
                                (_selectedMonth.year == DateTime.now().year &&
                                    _selectedMonth.month ==
                                        DateTime.now().month)
                                ? Colors.grey
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Source Filter Chips
              if (_hasCircleTransactions()) ...[
                _buildSourceFilter(isDark),
                const SizedBox(height: 16),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('analysis.monthly_analysis') ??
                        'Monthly Analysis',
                    style: GoogleFonts.notoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],

              // Incoming / Outgoing Cards
              Row(
                children: [
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 500),
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
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TransactionHistoryScreen(
                                showFilters: false,
                                initialMonth: _selectedMonth,
                                initialType: 'Money received',
                              ),
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
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.call_received,
                                color: Colors.green,
                                size: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.translate('analysis.incoming') ??
                                    'Incoming',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '+₹${formatAmount(_incomingStr)}',
                                  style: GoogleFonts.notoSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TweenAnimationBuilder<double>(
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
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TransactionHistoryScreen(
                                showFilters: false,
                                initialMonth: _selectedMonth,
                                initialType: 'Money sent',
                                initialSource: _selectedSource,
                              ),
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
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.call_made,
                                color: isDark ? Colors.white70 : Colors.black87,
                                size: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.translate('analysis.outgoing') ??
                                    'Outgoing',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '-₹${formatAmount(_outgoingStr)}',
                                  style: GoogleFonts.notoSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.red.shade400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Detailed Card
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2630) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    // Comparison Banner
                    if (diffAbs > 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isMore
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isMore
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: isMore ? Colors.red : Colors.green,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (AppLocalizations.of(context)?.translate(
                                          isMore
                                              ? 'analysis.comparison_more'
                                              : 'analysis.comparison_less',
                                        ) ??
                                        'Spent ${isMore ? 'more' : 'less'} vs $prevMonthName this time')
                                    .replaceAll(
                                      '{amount}',
                                      '₹${formatAmount(diffAbs)}',
                                    )
                                    .replaceAll('{month}', prevMonthName),
                                style: TextStyle(
                                  color: isMore ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Categories List
                          // Total Spend Category Item
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('analysis.total_spends') ??
                                  'Total Spends',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade300
                                    : Colors.black87,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₹${formatAmount(_totalSpend)}',
                                  style: GoogleFonts.notoSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey.shade400,
                                  size: 20,
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      TransactionHistoryScreen(
                                        showFilters: false,
                                        initialMonth: _selectedMonth,
                                        initialType: 'Money sent',
                                      ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // Multi-color Segmented Progress Bar
                          if (_categories.isNotEmpty)
                            Container(
                              height: 18,
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(vertical: 20),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey.shade900
                                    : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Row(
                                children: _categories.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final c = entry.value;

                                  // Minimum of 20 flex to ensure tiny amounts are still visible as dots
                                  int flex = (c['amount'] / _totalSpend * 1000)
                                      .toInt();
                                  if (flex < 20) flex = 20;

                                  return Expanded(
                                    flex: flex,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.fastOutSlowIn,
                                      margin: EdgeInsets.only(
                                        right: index < _categories.length - 1
                                            ? 4
                                            : 0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getCategoryColor(c['name']),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                          Divider(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade200,
                          ),

                          // Categories List
                          ..._categories.asMap().entries.map((entry) {
                            final index = entry.key;
                            final cat = entry.value;

                            return TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: 1),
                              duration: Duration(
                                milliseconds: 400 + (index * 100),
                              ),
                              curve: Curves.easeOutQuart,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(0, 20 * (1 - value)),
                                  child: Opacity(
                                    opacity: value.clamp(0.0, 1.0),
                                    child: child,
                                  ),
                                );
                              },
                              child: Column(
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _getCategoryColor(cat['name']),
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        _getCategoryIcon(cat['name']),
                                        color: _getCategoryColor(cat['name']),
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      _getLocalizedCategoryName(
                                        context,
                                        cat['name'],
                                      ),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey.shade300
                                            : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                    trailing: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                            0.4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '₹${formatAmount(cat['amount'])}',
                                                style: GoogleFonts.notoSans(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey.shade400,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                    onTap: () {
                                      final name = cat['name'];
                                      // Drill-down logic: If 'Personal' or 'UPI Circle' is clicked in 'All' mode, update filter
                                      if (_selectedSource == 'All' &&
                                          (name == 'Personal' ||
                                              name == 'UPI Circle')) {
                                        setState(() {
                                          _selectedSource = name;
                                          _calculateDataForMonth();
                                        });
                                      } else {
                                        // Specific category / child navigation
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                TransactionHistoryScreen(
                                                  showFilters: false,
                                                  initialMonth: _selectedMonth,
                                                  initialCategory:
                                                      name == 'P2P / Friends'
                                                      ? 'People'
                                                      : name,
                                                  initialType: 'Money sent',
                                                  initialSource:
                                                      _selectedSource,
                                                ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  Divider(
                                    color: isDark
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade200,
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Footer
              Center(
                child: Text(
                  AppLocalizations.of(
                        context,
                      )?.translate('common.powered_by') ??
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

  bool _hasCircleTransactions() {
    return widget.history.any((tx) => tx['initiated_by_upi'] != null);
  }

  Widget _buildSourceFilter(bool isDark) {
    final circleUsers = widget.history
        .where((tx) => tx['initiated_by_name'] != null)
        .map((tx) => tx['initiated_by_name'] as String)
        .toSet()
        .toList();

    final isChild = widget.user['bank_name'] == null;

    final showChildChips =
        !isChild &&
        (_selectedSource == 'UPI Circle' ||
            circleUsers.contains(_selectedSource));

    final sources = [
      'All',
      'Personal',
      'UPI Circle',
      if (showChildChips) ...circleUsers,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: sources.map((source) {
          final isSelected = _selectedSource == source;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(source),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedSource = source;
                    _calculateDataForMonth();
                  });
                } else if (source != 'All') {
                  setState(() {
                    _selectedSource = 'All';
                    _calculateDataForMonth();
                  });
                }
              },
              backgroundColor: isDark ? const Color(0xFF1E2630) : Colors.white,
              selectedColor: isDark
                  ? Colors.deepPurple.shade400
                  : Colors.deepPurple,
              checkmarkColor: Colors.white,
              elevation: isSelected ? 2 : 0,
              pressElevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark ? Colors.white10 : Colors.grey.shade300),
                ),
              ),
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getLocalizedCategoryName(BuildContext context, String category) {
    final loc = AppLocalizations.of(context);
    return loc?.translate(
          'spending_limit.cat_${category.toLowerCase().replaceAll(' & ', '_').replaceAll(' ', '_')}',
        ) ??
        category;
  }
}
