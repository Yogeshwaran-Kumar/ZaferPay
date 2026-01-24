import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:intl/intl.dart';
import 'transaction_details_screen.dart';

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
    _loadData();
  }

  Future<void> _loadData() async {
    final user = await _api.getMe();
    if (user != null) {
      _myUpi = user['upi_id'];
    }

    final targetUpi = widget.args['upi'];
    // Fetch conversation
    final history = await _api.getConversation(targetUpi);

    if (mounted) {
      setState(() {
        if (history != null) {
          _messages = history;
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
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
            child: _isLoading
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

  Widget _buildMessageItem(Map<String, dynamic> tx, bool isDark) {
    final bool isSender = tx['sender_upi_id'] == _myUpi;
    final bool isSuccess = tx['status'] == 'SUCCESS';
    final amount = tx['amount'];

    // Date formatting
    // If "today", show "Today, HH:mm a"
    // DateTime timestamp from API is UTC typically, need to handle local.
    // Assuming backend string is ISO.
    DateTime dt =
        DateTime.tryParse(tx['timestamp'] ?? "")?.toLocal() ?? DateTime.now();
    final timeStr = DateFormat('d MMM, h:mm a').format(dt);

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          // Inject the known contact name into the transaction data so details screen shows name instead of UPI ID
          final transaction = Map<String, dynamic>.from(tx);
          final contactName = widget.args['name'];

          if (isSender) {
            // I sent money TO the contact
            transaction['receiver_name'] = contactName;
          } else {
            // The contact sent money FROM themselves
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
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          width:
              MediaQuery.of(context).size.width *
              0.75, // Slightly wider for better fit
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade800 : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isSender ? const Radius.circular(16) : Radius.zero,
              bottomRight: isSender ? Radius.zero : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Wrap content
            children: [
              Text(
                isSender
                    ? "Payment to ${widget.args['name']}"
                    : "Payment to you",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (!isSuccess)
                Text(
                  "Payment Failed",
                  style: TextStyle(color: Colors.red[300], fontSize: 13),
                )
              else
                // Payment mode indicator visual
                Text(
                  "Paid via 2Way",
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey,
                    fontSize: 12,
                  ),
                ),

              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      "₹$amount",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSuccess) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 18,
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.error, color: Colors.redAccent, size: 18),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      isSuccess ? "Paid • $timeStr" : "Failed • $timeStr",
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: isDark ? Colors.grey.shade400 : Colors.grey,
                    size: 16,
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
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24,
          ), // Extra bottom padding
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 50,
                    maxHeight: 100,
                  ), // Dynamic height
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey[100],
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: isDark ? Colors.grey.shade700 : Colors.grey[300]!,
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
                          maxLines: null, // Allow multiline
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: "Message...",
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey,
                            ),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _handleSendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF00B9F1)),
                        onPressed: _handleSendMessage,
                        constraints: const BoxConstraints(), // Compact
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  final upi = widget.args['upi'];
                  final name = widget.args['name'];
                  Navigator.pushNamed(
                    context,
                    '/amount',
                    arguments: {'upi': upi, 'name': name},
                  ).then((_) => _loadData()); // Refresh on return
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B9F1), // Brand Blue
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  "Pay",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg, bool isDark) {
    final bool isSender = msg['sender_upi_id'] == _myUpi;
    final String content = msg['content'] ?? "";
    DateTime dt =
        DateTime.tryParse(msg['timestamp'] ?? "")?.toLocal() ?? DateTime.now();
    final timeStr = DateFormat('h:mm a').format(dt);

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isSender
              ? const Color(0xFF00B9F1)
              : (isDark ? Colors.grey.shade800 : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isSender ? const Radius.circular(16) : Radius.zero,
            bottomRight: isSender ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              content,
              style: TextStyle(
                color: isSender
                    ? Colors.white
                    : (isDark ? Colors.white : Colors.black87),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
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
    final success = await _api.sendMessage(targetUpi, content);

    if (success) {
      _msgController.clear();
      _loadData(); // Refresh list to see message
    }
  }
}
