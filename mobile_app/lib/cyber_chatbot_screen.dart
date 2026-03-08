import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/chatbot_service.dart';
import 'services/app_localizations.dart';

class CyberChatbotScreen extends StatefulWidget {
  const CyberChatbotScreen({super.key});

  @override
  State<CyberChatbotScreen> createState() => _CyberChatbotScreenState();
}

class _CyberChatbotScreenState extends State<CyberChatbotScreen>
    with TickerProviderStateMixin {
  final ChatbotService _chatbotService = ChatbotService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  // Conversation history for Gemini context
  final List<Map<String, String>> _history = [];

  @override
  void initState() {
    super.initState();
    // Add welcome message from localizations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(
              text:
                  AppLocalizations.of(
                    context,
                  )?.translate('chatbot.welcome_text') ??
                  "Hello! 👋 I'm your **Cyber Complaint Assistant**.\n\n"
                      "I can help you with:\n"
                      "• Filing UPI fraud complaints\n"
                      "• Reporting unauthorized transactions\n"
                      "• Contacting the Cyber Crime Helpline\n"
                      "• Understanding your rights\n\n"
                      "How can I help you today?",
              isUser: false,
            ),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = text.trim();
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text: userMessage, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    // Add to history
    _history.add({'role': 'user', 'content': userMessage});

    // Get response from chatbot
    final reply = await _chatbotService.sendMessage(
      userMessage,
      _history,
      context,
    );

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(text: reply, isUser: false));
        _isLoading = false;
      });
      // Add bot reply to history
      _history.add({'role': 'assistant', 'content': reply});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F1115)
          : const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F1115) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00B9F1), Color(0xFF0288D1)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.translate('chatbot.title') ??
                      'Cyber Help',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)?.translate('chatbot.subtitle') ??
                      'UPI Fraud Complaint Assistant',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            height: 1,
          ),
        ),
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isLoading) {
                  return _buildTypingIndicator(isDark);
                }
                return _buildMessageBubble(_messages[index], isDark);
              },
            ),
          ),

          // Quick Suggestions (only show when there's 1 message — the welcome)
          if (_messages.length == 1) _buildQuickSuggestions(isDark),

          // Input Bar
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message, bool isDark) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00B9F1), Color(0xFF0288D1)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF00B9F1)
                    : (isDark ? const Color(0xFF1E2630) : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
                border: !isUser
                    ? Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      )
                    : null,
              ),
              child: _buildFormattedText(
                message.text,
                isUser
                    ? Colors.white
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// Simple markdown-like text rendering for bold (**text**) and bullet points
  Widget _buildFormattedText(String text, Color baseColor) {
    final lines = text.split('\n');
    List<InlineSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));

      String line = lines[i];

      // Process bold markers
      final boldRegex = RegExp(r'\*\*(.*?)\*\*');
      int lastEnd = 0;

      for (final match in boldRegex.allMatches(line)) {
        if (match.start > lastEnd) {
          spans.add(
            TextSpan(
              text: line.substring(lastEnd, match.start),
              style: GoogleFonts.outfit(
                color: baseColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          );
        }
        spans.add(
          TextSpan(
            text: match.group(1),
            style: GoogleFonts.outfit(
              color: baseColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        );
        lastEnd = match.end;
      }

      if (lastEnd < line.length) {
        spans.add(
          TextSpan(
            text: line.substring(lastEnd),
            style: GoogleFonts.outfit(
              color: baseColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00B9F1), Color(0xFF0288D1)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2630) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 300 + (index * 200)),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF00B9F1).withValues(alpha: value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildQuickSuggestions(bool isDark) {
    final suggestions = [
      AppLocalizations.of(context)?.translate('chatbot.suggest_fraud') ??
          '🚨 How to file a UPI fraud complaint?',
      AppLocalizations.of(context)?.translate('chatbot.suggest_helpline') ??
          '📞 What is helpline 1930?',
      AppLocalizations.of(context)?.translate('chatbot.suggest_unauthorized') ??
          '🏦 Report unauthorized transaction',
      AppLocalizations.of(context)?.translate('chatbot.suggest_docs') ??
          '📋 Documents needed for complaint',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions.map((s) {
          return GestureDetector(
            onTap: () => _sendMessage(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2630) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF00B9F1).withValues(alpha: 0.3)
                      : const Color(0xFF00B9F1).withValues(alpha: 0.2),
                ),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                ],
              ),
              child: Text(
                s,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFF00B9F1)
                      : const Color(0xFF0288D1),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161A1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E2630)
                    : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: GoogleFonts.outfit(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                decoration: InputDecoration(
                  hintText:
                      AppLocalizations.of(context)?.translate('chatbot.hint') ??
                      'Ask about UPI fraud complaints...',
                  hintStyle: GoogleFonts.outfit(
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isLoading ? null : () => _sendMessage(_controller.text),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: _isLoading
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF00B9F1), Color(0xFF0288D1)],
                      ),
                color: _isLoading
                    ? (isDark ? Colors.grey.shade800 : Colors.grey.shade300)
                    : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  if (!_isLoading)
                    BoxShadow(
                      color: const Color(0xFF00B9F1).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Icon(
                Icons.send_rounded,
                color: _isLoading
                    ? (isDark ? Colors.grey.shade600 : Colors.grey.shade500)
                    : Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}
