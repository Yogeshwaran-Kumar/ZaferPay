import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:intl/intl.dart';
import 'transaction_details_screen.dart';
import 'utils.dart'; // Add import

class ConversationScreen extends StatefulWidget {
  final Map<String, dynamic> args;

  const ConversationScreen({super.key, required this.args});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _api = ApiService();
  List<dynamic> _messages = [];
  bool _isLoading = true;
  String? _myUpi;
  final TextEditingController _msgController = TextEditingController();

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
      _messages = List.from(
        cached,
      ); // Create copy to avoid reference aliasing bugs
      _isLoading = false; // Render immediately!
    }

    // Always fetch fresh data in background
    _loadData();
  }

  Future<void> _loadData() async {
    final targetUpi = widget.args['upi'];

    // 0. Instant Cache Load (Zero Latency) - Disk Priority
    if (_myUpi == null) {
      final me = await _api.getCachedMe();
      if (mounted && me != null) {
        setState(() => _myUpi = me['upi_id']);
      }
    }

    final cachedHistory = await _api.getCachedConversation(targetUpi);
    if (mounted && cachedHistory != null) {
      setState(() {
        _messages = List.from(cachedHistory); // Copy
        _isLoading = false; // Show content immediately
      });
    }

    // 1. Fetch Fresh Data (Background)
    // Get current user details for context (Network Verification)
    final user = await _api.getMe();
    if (mounted && user != null) {
      setState(() => _myUpi = user['upi_id']);
    }

    // Fetch latest messages
    final history = await _api.getConversation(targetUpi);

    if (mounted) {
      setState(() {
        if (history != null) {
          _messages = List.from(history); // Copy
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.args['name'] ?? "User";
    final upiId = widget.args['upi'] ?? "";
    final initial = name.isNotEmpty ? name[0].toUpperCase() : "?";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Same colors as home screen for consistency if we want
    final List<Color> avatarColors = [
      const Color(0xFFE57373),
      const Color(0xFFBA68C8),
      const Color(0xFF7986CB),
      const Color(0xFF4FC3F7),
      const Color(0xFF4DB6AC),
      const Color(0xFF81C784),
      const Color(0xFFFFB74D),
      const Color(0xFFA1887F),
      const Color(0xFF90A4AE),
    ];
    final color = avatarColors[name.hashCode.abs() % avatarColors.length];

    // Ensure consistent background color for seamless merging
    final bgColor = isDark ? const Color(0xFF0F1115) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0.5,
        leading: BackButton(color: Theme.of(context).iconTheme.color),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.args['isMerchant'] != true)
                    Text(
                      widget.args['mobile'] ?? upiId,
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: true, // Chat style: bottom up
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      if (item['type'] == 'message') {
                        return _buildChatBubble(item, isDark);
                      }
                      return _buildMessageItem(item, isDark);
                    },
                  ),
          ),
          _buildBottomBar(isDark),
        ],
      ),
    );
  }

  DateTime _parseTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return DateTime.now();
    try {
      // Handle timestamps correctly
      // If it ends with Z, it's already ISO UTC.
      // If not, we assume it's Naive UTC (from backend) and append Z.
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
      return "Today, ${DateFormat('h:mm a').format(dt)}";
    } else if (date == yesterday) {
      return "Yesterday, ${DateFormat('h:mm a').format(dt)}";
    } else {
      return DateFormat('d MMM, h:mm a').format(dt);
    }
  }

  Widget _buildMessageItem(Map<String, dynamic> tx, bool isDark) {
    final bool isSender = tx['sender_upi_id'] == _myUpi;
    final bool isSuccess = tx['status'] == 'SUCCESS';
    final amount = tx['amount'];

    // Use smart date formatting handles UTC/Local issues
    final dt = _parseTimestamp(tx['timestamp']);
    final timeStr = _formatSmartDate(dt);

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
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          padding: const EdgeInsets.all(20),
          width: MediaQuery.of(context).size.width * 0.65, // Decreased width
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2630) : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.grey.withValues(
                    alpha: 0.05,
                  ), // Reduced shadow since we have color
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
            ],
            border: isDark
                ? Border.all(color: Colors.white10)
                : Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSender
                    ? "Payment to ${widget.args['name']}"
                    : "Payment to you",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tx['note'] != null && tx['note'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    tx['note'].toString().toUpperCase(),
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "₹",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatAmount(amount), // Smart Amount
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!isSuccess)
                Row(
                  children: [
                    const Icon(Icons.error, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "Payment Failed",
                      style: TextStyle(color: Colors.red[300], fontSize: 13),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.greenAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Paid • $timeStr",
                          style: TextStyle(
                            color: isDark ? Colors.grey.shade400 : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: isDark
                          ? Colors.grey.shade600
                          : Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F1115) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        child: Row(
          children: [
            ElevatedButton(
              onPressed: () {
                final upi = widget.args['upi'];
                final name = widget.args['name'];
                Navigator.pushNamed(
                  context,
                  '/amount',
                  arguments: {'upi': upi, 'name': name},
                ).then((_) => _loadData());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B9F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                elevation: 0,
              ),
              child: const Text(
                "Pay",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  // Transparent background in dark mode as requested
                  color: isDark ? Colors.transparent : Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: "Message...",
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey.shade500 : Colors.grey,
                          ),
                          border: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _handleSendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, size: 20),
                      color: const Color(0xFF00B9F1),
                      onPressed: _handleSendMessage,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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

  Widget _buildChatBubble(Map<String, dynamic> msg, bool isDark) {
    final bool isSender = msg['sender_upi_id'] == _myUpi;
    final String content = msg['content'] ?? "";
    final dt = _parseTimestamp(msg['timestamp']);
    final timeStr = _formatSmartDate(dt);

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isSender
              ? const Color(0xFF00B9F1)
              : (isDark ? const Color(0xFF1E2630) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isSender
                ? const Radius.circular(20)
                : const Radius.circular(4),
            bottomRight: isSender
                ? const Radius.circular(4)
                : const Radius.circular(20),
          ),
          boxShadow: (!isSender && !isDark)
              ? [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
          border: isDark && !isSender
              ? Border.all(color: Colors.white10)
              : null,
        ),
        child: Column(
          crossAxisAlignment: isSender
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: TextStyle(
                color: isSender
                    ? Colors.white
                    : (isDark ? Colors.white : Colors.black87),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                color: isSender
                    ? Colors.white70
                    : (isDark ? Colors.grey.shade400 : Colors.grey),
                fontSize: 10,
              ),
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

    // 1. Optimistic Update (Zero Latency)
    final tempMsg = {
      'id': 'temp-${DateTime.now().millisecondsSinceEpoch}',
      'sender_upi_id': _myUpi,
      'receiver_upi_id': targetUpi,
      'content': content,
      'timestamp': DateTime.now().toUtc().toIso8601String(), // Correct UTC
      'type': 'message',
      'amount': 0.0,
      'status': 'SUCCESS', // Optimistically assume success
    };

    setState(() {
      _messages.insert(0, tempMsg); // Add to UI instantly
      _msgController.clear();
    });

    // 2. Network Sync (Background)
    try {
      // We pass the tempMsg to API so it can cache it immediately too
      await _api.sendMessageOptimistic(targetUpi, content, tempMsg);
    } catch (_) {
      // If failed, mark as failed in UI (optional, for now we keep it simple)
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m['id'] == tempMsg['id']);
          if (index != -1) {
            _messages[index]['status'] = 'FAILED';
          }
        });
      }
    }
  }
}
