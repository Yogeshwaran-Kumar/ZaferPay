import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'transaction_details_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic>? _user;
  List<dynamic> _allHistory = [];
  List<dynamic> _filteredHistory = [];
  bool _isLoading = true;

  // Filters
  List<String> _selectedStatuses = [];
  String?
  _selectedPaymentType; // 'Sent', 'Received' - Single select as per logic
  // Amount - Multiple selection supported
  List<int> _selectedAmountRangeIndices = [];

  final List<Map<String, dynamic>> _amountRanges = [
    {'label': 'Up to ₹200', 'min': 0, 'max': 200},
    {'label': '₹200 - ₹500', 'min': 200, 'max': 500},
    {'label': '₹500 - ₹2,000', 'min': 500, 'max': 2000},
    {'label': 'Above ₹2,000', 'min': 2000, 'max': null},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _api.getMe();
      final history = await _api.getHistory();
      if (mounted) {
        setState(() {
          _user = user;
          _allHistory = history ?? [];
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<dynamic> temp = List.from(_allHistory);

    // 1. Search
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      temp = temp.where((tx) {
        final name =
            (tx['sender_name'] ?? '').toString().toLowerCase() +
            (tx['receiver_name'] ?? '').toString().toLowerCase() +
            (tx['sender_upi_id'] ?? '').toString().toLowerCase() +
            (tx['receiver_upi_id'] ?? '').toString().toLowerCase();
        return name.contains(query);
      }).toList();
    }

    // 2. Status
    if (_selectedStatuses.isNotEmpty) {
      temp = temp.where((tx) {
        // Map UI status to Backend status
        // Completed -> SUCCESS, Failed -> FAILED, Processing -> BLOCKED (or others)
        String status = tx['status'];
        if (_selectedStatuses.contains('Completed') && status == 'SUCCESS') {
          return true;
        }
        if (_selectedStatuses.contains('Failed') && status == 'FAILED') {
          return true;
        }
        if (_selectedStatuses.contains('Processing') && status == 'BLOCKED') {
          return true; // Assuming BLOCKED as Processing/Pending for demo
        }
        return false;
      }).toList();
    }

    // 3. Payment Type (Sent/Received)
    if (_selectedPaymentType != null && _user != null) {
      temp = temp.where((tx) {
        final isDebit = tx['sender_upi_id'] == _user!['upi_id'];
        if (_selectedPaymentType == 'Money sent') return isDebit;
        if (_selectedPaymentType == 'Money received') return !isDebit;
        return true;
      }).toList();
    }

    // 4. Amount Range (OR logic for multiple ranges)
    if (_selectedAmountRangeIndices.isNotEmpty) {
      temp = temp.where((tx) {
        final amt = (tx['amount'] as num).toDouble();
        for (int index in _selectedAmountRangeIndices) {
          final range = _amountRanges[index];
          final min = range['min'] as num;
          final max = range['max'] as num?;

          bool matches = false;
          if (max != null) {
            matches = amt >= min && amt <= max;
          } else {
            matches = amt >= min;
          }
          if (matches) return true;
        }
        return false;
      }).toList();
    }

    setState(() {
      _filteredHistory = temp;
    });
  }

  // Helper to group transactions by Month
  Map<String, List<dynamic>> _groupTransactions(List<dynamic> transactions) {
    Map<String, List<dynamic>> grouped = {};
    for (var tx in transactions) {
      try {
        final dt = DateTime.parse(tx['timestamp']).toLocal();
        final key = DateFormat('MMMM yyyy').format(dt); // e.g., "January 2026"
        if (!grouped.containsKey(key)) {
          grouped[key] = [];
        }
        grouped[key]!.add(tx);
      } catch (e) {
        // Skip invalid dates
      }
    }
    return grouped;
  }

  double _calculateMonthlyTotal(List<dynamic> monthTxs) {
    double total = 0;
    if (_user == null) return 0;

    for (var tx in monthTxs) {
      final isDebit = tx['sender_upi_id'] == _user!['upi_id'];
      final amount = (tx['amount'] as num).toDouble();
      if (tx['status'] == 'SUCCESS') {
        if (isDebit) {
          total -= amount;
        } else {
          total += amount;
        }
      }
    }
    return total;
  }

  // --- FILTER UI METHODS ---

  void _showStatusFilter() {
    List<String> tempSelected = List.from(_selectedStatuses);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              height: 450, // Fixed height to match image approximate
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222222) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Status",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildStatusOption(
                          "Completed",
                          Icons.check_circle,
                          Colors.green,
                          tempSelected,
                          setModalState,
                        ),
                        _buildStatusOption(
                          "Failed",
                          Icons.cancel,
                          Colors.red,
                          tempSelected,
                          setModalState,
                        ),
                        _buildStatusOption(
                          "Processing",
                          Icons.access_time_filled,
                          Colors.orange,
                          tempSelected,
                          setModalState,
                        ),
                      ],
                    ),
                  ),
                  _buildBottomButtons(
                    onSame: () {
                      setModalState(() => tempSelected.clear());
                    },
                    onApply: () {
                      setState(() => _selectedStatuses = tempSelected);
                      _applyFilters();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusOption(
    String label,
    IconData icon,
    Color color,
    List<String> group,
    StateSetter setState,
  ) {
    final isSelected = group.contains(label);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              group.remove(label);
            } else {
              group.add(label);
            }
          });
        },
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.grey,
                  width: 2,
                ),
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black)
                    : Colors.transparent, // Radio style
              ),
              child: isSelected
                  ? Icon(
                      Icons.circle,
                      color: isDark ? Colors.black : Colors.white,
                      size: 10,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentTypeFilter() {
    String? tempSelected = _selectedPaymentType;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              height: 400,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222222) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Payment type",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildTypeGridOption(
                              "Money sent",
                              Icons.arrow_outward,
                              tempSelected == "Money sent",
                              () {
                                setModalState(() {
                                  if (tempSelected == "Money sent") {
                                    tempSelected = null;
                                  } else {
                                    tempSelected = "Money sent";
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTypeGridOption(
                              "Money received",
                              Icons.call_received,
                              tempSelected == "Money received",
                              () {
                                setModalState(() {
                                  if (tempSelected == "Money received") {
                                    tempSelected = null;
                                  } else {
                                    tempSelected = "Money received";
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomButtons(
                    onSame: () {
                      setModalState(() => tempSelected = null);
                    },
                    onApply: () {
                      setState(() => _selectedPaymentType = tempSelected);
                      _applyFilters();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTypeGridOption(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? const Color(0xFF5F259F).withValues(alpha: 0.2)
                    : const Color(0xFFE3F2FD))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF9E65E6) : Colors.blue.shade200)
                : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? const Color(0xFF9E65E6) : Colors.white)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected
                    ? (isDark ? Colors.white : Colors.blue.shade700)
                    : (isDark ? Colors.grey.shade400 : Colors.black87),
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected
                    ? (isDark ? const Color(0xFF9E65E6) : Colors.blue.shade900)
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAmountFilter() {
    List<int> tempIndices = List.from(_selectedAmountRangeIndices);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              height: 500,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222222) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Amount",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _amountRanges.length,
                      itemBuilder: (context, index) {
                        final item = _amountRanges[index];
                        final isSelected = tempIndices.contains(index);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: InkWell(
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  tempIndices.remove(index);
                                } else {
                                  tempIndices.add(index);
                                }
                              });
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item['label'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      6,
                                    ), // Standard Checkbox shape
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.transparent
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                    color: isSelected
                                        ? (isDark ? Colors.white : Colors.black)
                                        : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check,
                                          color: isDark
                                              ? Colors.black
                                              : Colors.white,
                                          size: 16,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _buildBottomButtons(
                    onSame: () {
                      setModalState(() => tempIndices.clear());
                    },
                    onApply: () {
                      setState(() => _selectedAmountRangeIndices = tempIndices);
                      _applyFilters();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomButtons({
    required VoidCallback onSame,
    required VoidCallback onApply,
  }) {
    // Add extra padding at the bottom to avoid overlap with system navigation bar
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF5F259F)
                    : const Color(0xFFE3F2FD),
                foregroundColor: isDark ? Colors.white : Colors.blue.shade900,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: onApply,
              child: const Text(
                "Apply",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: isDark ? Colors.grey.shade600 : Colors.grey,
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: onSame,
              child: Text(
                "Clear all",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final grouped = _groupTransactions(_filteredHistory);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar Area
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.arrow_back,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: const InputDecoration(
                              hintText: "Search transactions",
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.grey,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                          "Status",
                          _selectedStatuses.isNotEmpty
                              ? "${_selectedStatuses.length} selected"
                              : null,
                          _showStatusFilter,
                        ),
                        _buildFilterChip(
                          "Payment type",
                          _selectedPaymentType,
                          _showPaymentTypeFilter,
                        ),
                        _buildFilterChip(
                          "Amount",
                          _selectedAmountRangeIndices.isNotEmpty
                              ? "${_selectedAmountRangeIndices.length} ranges"
                              : null,
                          _showAmountFilter,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // List
            Expanded(
              child: grouped.isEmpty
                  ? Center(
                      child: Text(
                        "No transactions found",
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: grouped.length,
                      itemBuilder: (context, index) {
                        final monthKey = grouped.keys.elementAt(index);
                        final monthTxs = grouped[monthKey]!;
                        final total = _calculateMonthlyTotal(monthTxs);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        monthKey.split(" ").length > 1
                                            ? monthKey.split(" ")[1]
                                            : "", // Year
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        monthKey.split(" ")[0], // Month
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    NumberFormat.currency(
                                      symbol: '₹',
                                    ).format(total),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...monthTxs.map((tx) => _buildTransactionItem(tx)),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String? selectedValue,
    VoidCallback onTap,
  ) {
    final isActive = selectedValue != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? Colors.black : Colors.white),
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(
              isActive ? selectedValue : label,
              style: TextStyle(
                color: isActive
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white : Colors.black),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: isActive ? Colors.white : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    if (_user == null) return const SizedBox();

    final isDebit = tx['sender_upi_id'] == _user!['upi_id'];
    final displayName = isDebit
        ? (tx['receiver_name'] as String? ?? tx['receiver_upi_id'] ?? 'Unknown')
              .toString()
        : (tx['sender_name'] as String? ?? tx['sender_upi_id'] ?? 'Unknown')
              .toString();

    final amount = tx['amount'];

    // Status Color
    Color amountColor;
    if (tx['status'] == 'FAILED') {
      amountColor = Colors.red;
    } else if (tx['status'] == 'BLOCKED') {
      amountColor = Colors.grey;
    } else {
      amountColor = isDebit
          ? Colors
                .red // User requested RED for sent amount
          : Colors.green.shade700;
    }

    String dateStr = "";
    try {
      final dt = DateTime.parse(tx['timestamp']);
      dateStr = DateFormat('d MMMM').format(dt);
    } catch (_) {}

    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.purple, // Or random color based on name
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${isDebit ? '-' : '+'}₹$amount",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: amountColor,
                  ),
                ),
                if (tx['status'] == 'SUCCESS' && !isDebit)
                  const SizedBox()
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      // If success and debit -> no text needed really, but user wanted "status"
                      // If failed -> FAILED
                      tx['status'] == 'SUCCESS' ? '' : tx['status'],
                      style: TextStyle(
                        fontSize: 10,
                        color: tx['status'] == 'FAILED'
                            ? Colors.red
                            : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
