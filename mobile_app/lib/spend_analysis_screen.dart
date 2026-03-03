import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
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
  final _api = ApiService();

  DateTime _selectedMonth = DateTime.now();

  double _incomingStr = 0.0;
  double _outgoingStr = 0.0;

  double _prevOutgoingStr = 0.0;

  List<Map<String, dynamic>> _categories = [];
  double _totalSpend = 0.0;

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

    Map<String, double> categorySpends = {};

    for (var tx in widget.history) {
      if (tx['status'] != 'SUCCESS') continue;

      final isDebit = tx['sender_upi_id'] == widget.user['upi_id'];
      final amount = (tx['amount'] ?? 0).toDouble();

      try {
        final txDate = DateTime.parse(tx['timestamp']).toLocal();
        final txMonthStr = DateFormat('yyyy-MM').format(txDate);

        if (txMonthStr == selectedMonthStr) {
          if (isDebit) {
            outgoing += amount;

            // Categorize outward
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
            categorySpends[category] = (categorySpends[category] ?? 0) + amount;
          } else {
            incoming += amount;
          }
        } else if (txMonthStr == prevMonthStr) {
          if (isDebit) {
            prevOutgoing += amount;
          }
        }
      } catch (e) {
        // block invalid date
      }
    }

    var sortedCategories = categorySpends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    setState(() {
      _incomingStr = incoming;
      _outgoingStr = outgoing;
      _prevOutgoingStr = prevOutgoing;
      _totalSpend = outgoing;

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
                  'Select Month & Year',
                  style: GoogleFonts.outfit(
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
                        DateFormat('MMMM yyyy').format(month),
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
            ? null
            : Text(
                'Spending Limit',
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
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Monthly summary',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
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
              const SizedBox(height: 24),

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
                                  style: GoogleFonts.outfit(
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
                                  style: GoogleFonts.outfit(
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

              // Spending Limit Card
              _buildSpendingLimitCard(isDark),

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
                                '₹${formatAmount(diffAbs)} Spent ${isMore ? 'more' : 'less'} vs $prevMonthName this time',
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
                          // Total Spends Item
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.sync_alt,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            title: Text(
                              'Total spends',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            trailing: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '₹${formatAmount(_totalSpend)}',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
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
                                  ),
                                ],
                              ),
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
                                      cat['name'],
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
                                                style: GoogleFonts.outfit(
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
                                      // Navigate to history with month and category filters
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              TransactionHistoryScreen(
                                                showFilters: false,
                                                initialMonth: _selectedMonth,
                                                initialCategory: cat['name'],
                                                initialType: 'Money sent',
                                              ),
                                        ),
                                      );
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
                    // Close this dialog, open PIN dialog
                    Navigator.pop(ctx);
                    _showUpiPinConfirmDialog(
                      isDark: isDark,
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

  void _showUpiPinConfirmDialog({
    required bool isDark,
    required bool isEnabled,
    required double? amount,
    required int period,
  }) {
    String enteredPin = '';
    String? errorMessage;
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setPinState) {
            void onKeyTap(String key) {
              if (isVerifying) return;
              setPinState(() {
                errorMessage = null;
                if (key == 'BACK') {
                  if (enteredPin.isNotEmpty) {
                    enteredPin = enteredPin.substring(0, enteredPin.length - 1);
                  }
                } else if (enteredPin.length < 4) {
                  enteredPin += key;
                }
              });

              // Auto-submit when 4 digits entered
              if (enteredPin.length == 4 && !isVerifying) {
                setPinState(() => isVerifying = true);
                _verifyPinAndSave(
                  ctx: ctx,
                  pin: enteredPin,
                  isDark: isDark,
                  isEnabled: isEnabled,
                  amount: amount,
                  period: period,
                  onError: (msg) {
                    setPinState(() {
                      enteredPin = '';
                      errorMessage = msg;
                      isVerifying = false;
                    });
                  },
                );
              }
            }

            final bg = isDark ? const Color(0xFF1E2630) : Colors.white;
            final textColor = isDark ? Colors.white : Colors.black87;
            final subColor = isDark
                ? Colors.grey.shade400
                : Colors.grey.shade600;

            return AlertDialog(
              backgroundColor: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B9F1).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF00B9F1),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Confirm with UPI PIN',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your UPI PIN to update\nyour spending limit',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PIN dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < enteredPin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? const Color(0xFF00B9F1)
                              : Colors.transparent,
                          border: Border.all(
                            color: filled
                                ? const Color(0xFF00B9F1)
                                : (isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade400),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),

                  // Error message
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  if (isVerifying) ...[
                    const SizedBox(height: 16),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00B9F1),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Keypad
                  ...[
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ].map((row) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: row.map((key) {
                          return _buildPinKey(
                            key,
                            onKeyTap,
                            isDark,
                            isVerifying,
                          );
                        }).toList(),
                      ),
                    );
                  }),

                  // Bottom row: Back — 0 — ✕
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPinKey(
                        'BACK',
                        onKeyTap,
                        isDark,
                        isVerifying,
                        icon: Icons.backspace_outlined,
                      ),
                      _buildPinKey('0', onKeyTap, isDark, isVerifying),
                      _buildPinKey(
                        'CANCEL',
                        onKeyTap,
                        isDark,
                        isVerifying,
                        icon: Icons.close_rounded,
                        overrideTap: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPinKey(
    String label,
    void Function(String) onDigitTap,
    bool isDark,
    bool disabled, {
    IconData? icon,
    VoidCallback? overrideTap,
  }) {
    final bg = isDark ? const Color(0xFF2A3340) : Colors.grey.shade100;
    return GestureDetector(
      onTap: disabled ? null : (overrideTap ?? () => onDigitTap(label)),
      child: Container(
        width: 64,
        height: 52,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: icon != null
              ? Icon(
                  icon,
                  size: 20,
                  color: isDark ? Colors.white70 : Colors.black54,
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _verifyPinAndSave({
    required BuildContext ctx,
    required String pin,
    required bool isDark,
    required bool isEnabled,
    required double? amount,
    required int period,
    required void Function(String) onError,
  }) async {
    final status = await _api.verifyUpiPin(pin);

    if (status == PinVerificationStatus.success) {
      // Save the settings
      if (!isEnabled) {
        await _api.updateSettings(clearSpendingLimit: true);
      } else if (amount != null) {
        await _api.updateSettings(
          spendingLimit: amount,
          spendingLimitPeriod: period,
        );
      }
      if (!mounted || !ctx.mounted) return;
      Navigator.pop(ctx); // close PIN dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                isEnabled
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
    } else if (status == PinVerificationStatus.lockedOut) {
      if (!mounted || !ctx.mounted) return;
      Navigator.pop(ctx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many wrong attempts. Logged out for security.'),
          backgroundColor: Colors.red,
        ),
      );
      await _api.logout();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } else if (status == PinVerificationStatus.expired) {
      if (!mounted || !ctx.mounted) return;
      Navigator.pop(ctx);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('PIN Expired'),
          content: const Text(
            'Your UPI PIN has expired. Please update it to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/change-upi-pin');
              },
              child: const Text('Update PIN'),
            ),
          ],
        ),
      );
    } else {
      // incorrect or unknown
      final remaining = 3 - _api.failedAttempts;
      onError(
        'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.',
      );
    }
  }

  Widget _buildSpendingLimitCard(bool isDark) {
    final limit = widget.user['spending_limit'] != null
        ? (widget.user['spending_limit'] as num).toDouble()
        : null;
    if (limit == null || limit <= 0) return const SizedBox.shrink();

    final period = (widget.user['spending_limit_period'] as num?)?.toInt() ?? 1;
    final String? updatedAtStr = widget.user['spending_limit_updated_at'];

    DateTime limitStart;
    final now = DateTime.now();

    if (updatedAtStr != null) {
      try {
        final updatedAt = DateTime.parse(updatedAtStr).toLocal();
        // Midnight of the day it was set
        final setDate = DateTime(
          updatedAt.year,
          updatedAt.month,
          updatedAt.day,
        );
        // Midnight of today
        final today = DateTime(now.year, now.month, now.day);

        // Find which cycle we are currently in
        final daysSinceSet = today.difference(setDate).inDays;
        final fullCyclesPassed = daysSinceSet >= 0
            ? (daysSinceSet ~/ period)
            : 0;

        // The start of the current active cycle
        limitStart = setDate.add(Duration(days: fullCyclesPassed * period));
      } catch (_) {
        limitStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: period - 1));
      }
    } else {
      // Fallback: Rolling N-day window from midnight today
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
    final percent = (spent / limit).clamp(0.0, 1.0);
    final isExceeded = spent >= limit;
    final isCritical = percent >= 0.9;
    final isWarning = percent >= 0.75 && !isCritical;

    Color progressColor = const Color(0xFF00C853); // Green
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
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
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
          // ── Header row ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: progressColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$periodLabel Spending Limit',
                    style: TextStyle(
                      fontSize: 16,
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
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusFg,
                        fontSize: 11,
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
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 15,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 3-tile stats row ────────────────────────────────────
          Row(
            children: [
              // Spent
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
                height: 40,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              // Remaining
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
                height: 40,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              // Total limit
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

          const SizedBox(height: 16),

          // ── Animated progress bar ───────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: percent),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(value * 100).toStringAsFixed(1)}% used',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Warning / Exceeded banners ──────────────────────────
          if (isExceeded) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded, color: Colors.red, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Spending limit reached. New payments will be blocked until the limit resets.',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isCritical) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Almost at your limit. Spend carefully — only ₹${formatAmount(remaining)} left.',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 12,
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
            fontSize: 11,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '₹${formatAmount(amount)}',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
