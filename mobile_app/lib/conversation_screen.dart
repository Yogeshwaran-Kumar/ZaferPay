import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:intl/intl.dart';
import 'transaction_details_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/transaction_service.dart';
import 'services/user_service.dart';
import 'utils.dart';
import 'services/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

class ConversationScreen extends StatefulWidget {
  final Map<String, dynamic> args;

  const ConversationScreen({super.key, required this.args});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _api = ApiService();
  final _apiClient = ApiClient();
  late final _authService = AuthService(_apiClient);
  late final _userService = UserService(_apiClient);
  late final _transactionService = TransactionService(
    _apiClient,
    _authService,
    _userService,
  );
  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  String? _myUpi;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  dynamic _highlightRequestId;
  final Map<dynamic, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    // 0. Sync Load (True Zero Latency)
    final targetUpi = widget.args['upi'];

    // Load User Sync (Me)
    final me = _api.getUserSync();
    if (me != null) {
      _myUpi = me['upi_id'];
    }

    final cached = _api.getCachedConversationSync(targetUpi);
    if (cached != null) {
      _messages = List.from(cached);
      _isLoading = false;
    }

    // Always fetch fresh data in background
    _loadData();

    // Set highlight if provided
    if (widget.args['pendingRequest'] != null) {
      _highlightRequestId = widget.args['pendingRequest']['id'];
      _scrollToHighlight();
    }

    // Mark as read immediately if ID is known (fire-and-forget for speed)
    _markConversationAsRead();
  }

  @override
  void dispose() {
    // Safety net: mark as read one final time when leaving the screen
    // This ensures the backend is updated even if the initial call failed
    _markConversationAsRead();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final targetUpi = widget.args['upi'];

    // 0. Update UI immediately from Disk Cache (if not already done by RAM)
    if (_messages.isEmpty) {
      final cachedHistory = await _api.getCachedConversation(targetUpi);
      if (mounted && cachedHistory != null && _messages.isEmpty) {
        setState(() {
          _messages = List.from(cachedHistory);
          _isLoading = false;
        });
      }
    }

    // 1. Parallel Network Fetch
    try {
      final results = await Future.wait([
        _myUpi == null ? _api.getMe() : Future.value(null),
        _api.getConversation(targetUpi),
      ]);

      if (!mounted) return;

      // Process User Info
      final user = results[0] as Map<String, dynamic>?;
      if (user != null) {
        setState(() => _myUpi = user['upi_id']);
      }

      // Process Messages
      final history = results[1] as List<dynamic>?;
      setState(() {
        if (history != null) {
          _messages = List.from(history);
          if (_highlightRequestId != null) {
            _scrollToHighlight();
          }
        }
        _isLoading = false;
      });

      // Mark as Read (AWAIT to ensure backend commits before HomeScreen refreshes)
      await _markConversationAsRead();
    } catch (e) {
      if (kDebugMode) print("Conversation Load Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('conversation.load_failed') ??
                  "Failed to load conversation",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Centralized method to mark all items from this contact as read.
  /// Tries args['id'] first (always available from HomeScreen), then
  /// falls back to extracting sender_id from messages.
  Future<void> _markConversationAsRead() async {
    int? contactId;

    // Priority 1: ID passed from HomeScreen (most reliable)
    if (widget.args['id'] != null) {
      contactId = widget.args['id'] is int
          ? widget.args['id']
          : int.tryParse(widget.args['id'].toString());
    }

    // Priority 2: Extract from messages
    if (contactId == null && _messages.isNotEmpty) {
      final otherMsg = _messages.firstWhere(
        (m) => m['sender_upi_id'] != _myUpi && m['sender_id'] != null,
        orElse: () => null,
      );
      if (otherMsg != null) {
        contactId = otherMsg['sender_id'] is int
            ? otherMsg['sender_id']
            : int.tryParse(otherMsg['sender_id'].toString());
      }
    }

    if (contactId != null) {
      if (kDebugMode) {
        print('🔴 MARK READ: Calling markRead with contactId=$contactId');
      }
      await _api.markRead(contactId);
      if (kDebugMode) {
        print('🟢 MARK READ: markRead completed for contactId=$contactId');
      }
    } else {
      if (kDebugMode) {
        print(
          '⚠️ MARK READ: No contactId found! args[id]=${widget.args['id']}, messages=${_messages.length}',
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  void _scrollToHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _highlightRequestId == null || _messages.isEmpty) return;

      // 1. Find the index in the current messages list
      final index = _messages.indexWhere((m) {
        final mid = m['id']?.toString();
        final rid = _highlightRequestId?.toString();
        return mid != null && rid != null && mid == rid;
      });

      if (index == -1) return;

      // 2. Approximate scroll to bring it into the built area
      // Roughly 200 pixels per message estimate for payment cards
      final offset = index * 200.0;

      _scrollController
          .animateTo(
            offset,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          )
          .then((_) {
            // 3. Once scrolled approximately, ensure precisely visible
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final key = _itemKeys[_highlightRequestId];
              if (key?.currentContext != null) {
                Scrollable.ensureVisible(
                  key!.currentContext!,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  alignment: 0.5,
                );
              }
            });
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.args['name'] ?? "User";
    final upiId = widget.args['upi'] ?? "";
    final initial = name.isNotEmpty ? name[0].toUpperCase() : "?";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F1115) : const Color(0xFFFFFFFF);
    final appBarColor = isDark
        ? const Color(0xFF0F1115)
        : const Color(0xFFFFFFFF);

    // Handle user not found

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: Theme.of(context).iconTheme.color),
        titleSpacing: 0,
        title: Row(
          children: [
            // GPay-style Orange Gradient Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: getAvatarColor(name),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: GoogleFonts.notoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.notoSans(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.args['isMerchant'] != true)
                    Text(
                      widget.args['mobile'] ?? upiId,
                      style: GoogleFonts.notoSans(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Future: Show options menu
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? _buildEmptyState(name, initial, isDark)
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final item = _messages[index];

                        // Date separator logic
                        Widget? dateSeparator;
                        if (index < _messages.length - 1) {
                          final currentDate = _parseTimestamp(
                            item['timestamp'],
                          );
                          final previousDate = _parseTimestamp(
                            _messages[index + 1]['timestamp'],
                          );
                          if (!_isSameDay(currentDate, previousDate)) {
                            dateSeparator = _buildDateSeparator(
                              previousDate,
                              isDark,
                            );
                          }
                        } else if (index == _messages.length - 1) {
                          // First message (at the top when reversed)
                          dateSeparator = _buildDateSeparator(
                            _parseTimestamp(item['timestamp']),
                            isDark,
                          );
                        }

                        final id = item['id'];
                        final key = id != null
                            ? (_itemKeys[id] ??= GlobalKey())
                            : null;

                        if (item['type'] == 'message') {
                          return Column(
                            key: key,
                            children: [
                              if (dateSeparator != null) dateSeparator,
                              _buildChatBubble(item, isDark),
                            ],
                          );
                        }
                        if (item['type'] == 'payment_request') {
                          return Column(
                            key: key,
                            children: [
                              if (dateSeparator != null) dateSeparator,
                              _buildPaymentRequestItem(item, isDark),
                            ],
                          );
                        }
                        // Default to Payment/Transaction bubble
                        return Column(
                          key: key,
                          children: [
                            if (dateSeparator != null) dateSeparator,
                            _buildMessageItem(item, isDark),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          _buildBottomBar(isDark),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateSeparator(DateTime date, bool isDark) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    String label;
    if (dateOnly == today) {
      label = "Today";
    } else if (dateOnly == yesterday) {
      label = "Yesterday";
    } else {
      label = DateFormat('d MMM yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2630) : const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: GoogleFonts.notoSans(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String name, String initial, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: getAvatarColor(name),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.notoSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Start a conversation with $name",
                style: GoogleFonts.notoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.args['upi'] ?? "",
                style: GoogleFonts.notoSans(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final upi = widget.args['upi'];
                  final name = widget.args['name'];
                  Navigator.pushNamed(
                    context,
                    '/amount',
                    arguments: {'upi': upi, 'name': name},
                  ).then((_) => _loadData());
                },
                icon: const Icon(Icons.currency_rupee_rounded, size: 18),
                label: Text(
                  "Make a payment",
                  style: GoogleFonts.notoSans(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B9F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _parseTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(timestamp).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatSmartDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);

    if (date == today) {
      return DateFormat('h:mm a').format(dt);
    } else if (date == yesterday) {
      return "Yesterday";
    } else {
      return DateFormat('d MMM').format(dt);
    }
  }

  // ──── MESSAGE ITEM (COMPLETED PAYMENTS) ────
  Widget _buildMessageItem(Map<String, dynamic> tx, bool isDark) {
    final bool isSender =
        tx['sender_upi_id'] == _myUpi || tx['initiated_by_upi'] == _myUpi;
    final bool isSuccess = tx['status'] == 'SUCCESS';
    final amount = tx['amount'];
    final bool isHighlighted =
        _highlightRequestId != null &&
        tx['id']?.toString() == _highlightRequestId.toString();

    final dt = _parseTimestamp(tx['timestamp']);
    final timeStr = _formatSmartDate(dt);

    // Styling Logic - Card Design
    final bgColor = isSender
        ? (isDark
              ? const Color(0xFF004D40)
              : const Color(0xFFE0F7FA)) // Sent: Teal/Cyan (kept distinct)
        : (isDark
              ? const Color(0xFF1E2630)
              : Colors.white); // Received: White/Gray (matches image)

    // final borderColor = isSender
    //     ? Colors.transparent
    //     : (isDark ? Colors.white10 : Colors.grey.shade200);

    // Card-like border radius
    final borderRadius = BorderRadius.circular(24);

    final textColor = isSender
        ? (isDark ? Colors.white70 : Colors.black87)
        : (isDark ? Colors.white70 : Colors.black87);

    final amountColor = isSender
        ? (isDark ? Colors.white : const Color(0xFF006064))
        : (isDark ? Colors.white : Colors.black);

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          final transaction = Map<String, dynamic>.from(tx);
          final contactName = widget.args['name'];
          if (isSender) {
            transaction['receiver_name'] = contactName;
          } else {
            transaction['sender_name'] = contactName;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransactionDetailsScreen(
                transaction: transaction,
                currentUpiId: _myUpi ?? '',
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.all(20),
          width: MediaQuery.of(context).size.width * 0.70,
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: borderRadius,
            border: Border.all(
              color: isHighlighted
                  ? const Color(0xFF00B9F1)
                  : (isSender
                        ? Colors.transparent
                        : (isDark ? Colors.white10 : Colors.grey.shade200)),
              width: isHighlighted ? 2.0 : 1.0,
            ),
            boxShadow: [
              if (!isDark && !isSender)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Title
              Text(
                isSender
                    ? "Payment to ${widget.args['name']}"
                    : "Payment to you",
                style: GoogleFonts.notoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),

              // 2. Amount
              Text(
                "₹${formatAmount(amount)}",
                style: GoogleFonts.notoSans(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 12),

              // 3. Status Footer
              if (!isSuccess)
                Row(
                  children: [
                    const Icon(Icons.error, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "Failed",
                      style: GoogleFonts.notoSans(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Color(0xFF00C853), // Green
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Paid • $timeStr",
                      style: GoogleFonts.notoSans(
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
                  ],
                ),

              // 4. Note
              if (tx['note'] != null && tx['note'].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tx['note'].toString(),
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              // 5. UPI Circle Attribution
              if (tx['initiated_by_name'] != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.deepPurple.withValues(alpha: 0.15)
                        : Colors.deepPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.deepPurple.withValues(alpha: 0.3)
                          : Colors.deepPurple.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group_rounded,
                        size: 13,
                        color: isDark
                            ? Colors.deepPurple.shade200
                            : Colors.deepPurple,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'UPI Circle by ${tx['initiated_by_name']}',
                          style: GoogleFonts.notoSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.deepPurple.shade200
                                : Colors.deepPurple,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ──── BOTTOM BAR (PAY BUTTON + TEXT INPUT) ────
  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1115) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade100,
          ),
        ),
      ),
      child: SafeArea(
        child: (widget.args['isValid'] == false)
            ? Center(
                child: Text(
                  "This user is not on ZaferPay",
                  style: GoogleFonts.notoSans(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              )
            : Row(
                children: [
                  // Pay Button Pill
                  ElevatedButton(
                    onPressed: () {
                      final upi = widget.args['upi'];
                      final name = widget.args['name'];
                      final isContact = widget.args['isContact'] ?? false;
                      Navigator.pushNamed(
                        context,
                        '/amount',
                        arguments: {
                          'upi': upi,
                          'name': name,
                          'isContact': isContact,
                        },
                      ).then((_) => _loadData());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B9F1), // ZaferPay Blue
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)?.translate('pin.pay') ??
                          "Pay",
                      style: GoogleFonts.notoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Message Input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2630)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              style: GoogleFonts.notoSans(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                hintText: "Message...",
                                hintStyle: GoogleFonts.notoSans(
                                  color: isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade500,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _handleSendMessage(),
                            ),
                          ),
                          _isSending
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.send_rounded),
                                  iconSize: 22,
                                  color: _msgController.text.trim().isEmpty
                                      ? (isDark ? Colors.grey : Colors.grey)
                                      : const Color(0xFF00B9F1),
                                  onPressed: _handleSendMessage,
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ──── CHAT BUBBLE (TEXT MESSAGES) ────
  Widget _buildChatBubble(Map<String, dynamic> msg, bool isDark) {
    final bool isSender = msg['sender_upi_id'] == _myUpi;
    final String content = msg['content'] ?? "";
    final dt = _parseTimestamp(msg['timestamp']);
    final timeStr = _formatSmartDate(dt);
    final bool isFailed = msg['status'] == 'FAILED';

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isSender
              ? (isFailed
                    ? Colors.red.shade400
                    : const Color(0xFFE3F2FD)) // Light Blue for sender
              : (isDark ? const Color(0xFF1E2630) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isSender
                ? const Radius.circular(18)
                : const Radius.circular(4),
            bottomRight: isSender
                ? const Radius.circular(4)
                : const Radius.circular(18),
          ),
          border: isSender
              ? null // No border for sender
              : Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end, // Time always at end
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              content,
              style: GoogleFonts.notoSans(
                color: isSender
                    ? const Color(0xFF0D47A1) // Dark Blue Text
                    : (isDark ? Colors.white : Colors.black87),
                fontSize: 15,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: GoogleFonts.notoSans(
                    color: isSender
                        ? Colors.blue.shade900.withValues(alpha: 0.5)
                        : (isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade500),
                    fontSize: 10,
                  ),
                ),
                if (isFailed) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.error_outline, size: 12, color: Colors.red),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSendMessage() async {
    final content = _msgController.text.trim();
    if (content.isEmpty) return;

    final targetUpi = widget.args['upi'];

    setState(() => _isSending = true);

    // 1. Optimistic Update (Zero Latency)
    final tempMsg = {
      'id': 'temp-${DateTime.now().millisecondsSinceEpoch}',
      'sender_upi_id': _myUpi,
      'receiver_upi_id': targetUpi,
      'content': content,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'type': 'message',
      'amount': 0.0,
      'status': 'SUCCESS',
    };

    setState(() {
      _messages.insert(0, tempMsg);
      _msgController.clear();
    });

    // 2. Network Sync (Background)
    try {
      await _api.sendMessageOptimistic(targetUpi, content, tempMsg);
    } catch (_) {
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m['id'] == tempMsg['id']);
          if (index != -1) {
            _messages[index]['status'] = 'FAILED';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('conversation.send_failed') ??
                  "Failed to send message",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  // ──── PAYMENT REQUEST ITEM ────
  Widget _buildPaymentRequestItem(Map<String, dynamic> req, bool isDark) {
    final bool isRequester = req['requester_upi_id'] == _myUpi;
    final String status = req['status'] ?? 'pending';
    final amount = req['amount'];
    final dt = _parseTimestamp(req['timestamp']?.toString());
    final timeStr = _formatSmartDate(dt);

    final description = req['description'] ?? '';
    final bool isHighlighted =
        _highlightRequestId != null &&
        req['id']?.toString() == _highlightRequestId.toString();

    // Status styling
    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'paid':
        statusColor = Colors.green;
        // statusIcon = Icons.check_circle;
        statusLabel = 'Paid';
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        // statusIcon = Icons.cancel;
        statusLabel = req['cancelled_by'] == 'requester'
            ? 'Withdrawn'
            : 'Declined';
        break;
      default:
        statusColor = const Color(0xFFE65100); // Dark Orange
        // statusIcon = Icons.currency_rupee_rounded;
        statusLabel = 'Requested';
    }

    return Align(
      alignment: isRequester ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(20),
        width: MediaQuery.of(context).size.width * 0.75,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2630) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isHighlighted
                ? const Color(0xFF00B9F1)
                : (isDark ? Colors.white10 : Colors.grey.shade200),
            width: isHighlighted ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isRequester
                        ? 'You requested'
                        : '${req['requester_name'] ?? 'Someone'} requested',
                    style: GoogleFonts.notoSans(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.notoSans(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '₹${formatAmount(amount)}',
              style: GoogleFonts.notoSans(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: GoogleFonts.notoSans(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Action buttons for pending requests
            if (status == 'pending') ...[
              Row(
                children: [
                  // Cancel button (for both requester and payer)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleCancelRequest(req),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.white70
                            : Colors.grey.shade700,
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        isRequester ? 'Withdraw' : 'Decline',
                        style: GoogleFonts.notoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // Pay button (only for payer)
                  if (!isRequester) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        onPressed: () => _handlePayRequest(req),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B9F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Pay',
                          style: GoogleFonts.notoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ] else ...[
              // Completed/Cancelled State
              Text(
                status == 'paid'
                    ? "Request paid on $timeStr"
                    : "Request $status on $timeStr",
                style: GoogleFonts.notoSans(
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleCancelRequest(Map<String, dynamic> req) async {
    final requestId = req['id'];
    if (requestId == null) return;

    final isRequester = req['requester_upi_id'] == _myUpi;

    final requestTitle = isRequester
        ? (AppLocalizations.of(context)?.translate('requests.withdraw_title') ??
              'Withdraw Request')
        : (AppLocalizations.of(context)?.translate('requests.decline_title') ??
              'Decline Request');

    final requestContent = isRequester
        ? (AppLocalizations.of(
                context,
              )?.translate('requests.withdraw_confirm') ??
              'Are you sure you want to withdraw this payment request?')
        : (AppLocalizations.of(
                context,
              )?.translate('requests.decline_confirm') ??
              'Are you sure you want to decline this payment request?');

    final yesLabel = isRequester
        ? (AppLocalizations.of(context)?.translate('requests.yes_withdraw') ??
              'Yes, Withdraw')
        : (AppLocalizations.of(context)?.translate('requests.yes_decline') ??
              'Yes, Decline');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          requestTitle,
          style: GoogleFonts.notoSans(fontWeight: FontWeight.bold),
        ),
        content: Text(requestContent, style: GoogleFonts.notoSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)?.translate('common.no') ?? 'No',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yesLabel),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _transactionService.cancelPaymentRequest(requestId);
    if (mounted) {
      if (success) {
        _loadData(); // Refresh conversation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRequester
                  ? (AppLocalizations.of(
                          context,
                        )?.translate('requests.withdrawn_success') ??
                        'Request withdrawn')
                  : (AppLocalizations.of(
                          context,
                        )?.translate('requests.declined_success') ??
                        'Request declined'),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('requests.process_failed') ??
                  'Failed to process request',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handlePayRequest(Map<String, dynamic> req) {
    final upi = req['requester_upi_id'];
    final name = req['requester_name'] ?? widget.args['name'];
    final amount = req['amount'];
    final requestId = req['id'];
    final reason = req['reason'] ?? '';

    Navigator.pushNamed(
      context,
      '/amount',
      arguments: {
        'upi': upi,
        'name': name,
        'isRequestPayment': true,
        'paymentRequestId': requestId,
        'prefillAmount': amount,
        'requestReason': reason,
      },
    ).then((_) => _loadData());
  }
}
