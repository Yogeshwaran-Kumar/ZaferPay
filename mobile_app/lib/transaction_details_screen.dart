import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'mcc_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobile_app/main.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/transaction_service.dart';
import 'services/user_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'utils.dart';

class TransactionDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final String currentUpiId;
  final String? merchantCategory;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
    required this.currentUpiId,
    this.merchantCategory,
  });

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen> {
  final GlobalKey _globalKey = GlobalKey();

  // Dependency Injection (Manual)
  final _apiClient = ApiClient();
  late final _authService = AuthService(_apiClient);
  late final _userService = UserService(_apiClient);
  late final _transactionService = TransactionService(
    _apiClient,
    _authService,
    _userService,
  );

  // Request state tracking
  String? _requestStatus; // null, "pending", "paid", "cancelled"
  int? _existingRequestId;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
  }

  Future<void> _checkExistingRequest() async {
    final txId = widget.transaction['transaction_id']?.toString();
    if (txId == null || txId.isEmpty) {
      // setState(() => _isLoadingRequestStatus = false); // Removed
      return;
    }

    final result = await _transactionService.getRequestForTransaction(txId);
    if (mounted) {
      setState(() {
        // _isLoadingRequestStatus = false; // Removed
        if (result != null &&
            result['exists'] == true &&
            result['request'] != null) {
          _requestStatus = result['request']['status'];
          _existingRequestId = result['request']['id'];
        }
      });
    }
  }

  Future<void> _captureAndShare() async {
    try {
      RenderRepaintBoundary boundary =
          _globalKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();

        final tempDir = await getTemporaryDirectory();
        final file = await File(
          '${tempDir.path}/transaction_receipt.png',
        ).create();
        await file.writeAsBytes(pngBytes);

        MyApp.isSharing = true;
        try {
          // ignore: deprecated_member_use
          await Share.shareXFiles([XFile(file.path)]);
        } finally {
          MyApp.isSharing = false;
          MyApp.lastShareTime = DateTime.now();
        }
      }
    } catch (e) {
      debugPrint('Error sharing: $e');
      MyApp.isSharing = false;
    }
  }

  /// Determine button visibility based on request status
  bool get _showRequestButton {
    // Show immediately (don't wait for loading). Hide only if pending/paid.
    return _requestStatus == null || _requestStatus == 'cancelled';
  }

  bool get _showReportButton {
    if (_requestStatus == 'paid') return false;

    final transaction = widget.transaction;
    final currentUpiId = widget.currentUpiId;
    final isDebit = transaction['sender_upi_id'] == currentUpiId;

    if (isDebit) {
      // User is Sender: Always show report button
      return true;
    } else {
      // User is Receiver: Show ONLY if Business Account
      // The transaction stores 'receiver_mcc' which belongs to the Receiver (Me)
      final myMcc = transaction['receiver_mcc'];
      return MccHelper.isMerchant(myMcc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final currentUpiId = widget.currentUpiId;

    final isDebit = transaction['sender_upi_id'] == currentUpiId;
    final amount = transaction['amount'];
    final status = transaction['status'];
    final timestamp = transaction['timestamp'];

    // Merchant Logic
    final mcc = isDebit
        ? transaction['receiver_mcc']
        : transaction['sender_mcc'];
    final isMerchant = MccHelper.isMerchant(mcc);
    final merchantDomain =
        widget.merchantCategory ??
        (isMerchant ? MccHelper.getDomain(mcc.toString()) : null);

    final senderName =
        transaction['sender_name'] ?? transaction['sender_upi_id'] ?? 'Unknown';
    final receiverName =
        transaction['receiver_name'] ??
        transaction['receiver_upi_id'] ??
        'Unknown';

    // Display Name logic
    final displayName = isDebit ? receiverName : senderName;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final formattedDate = _formatDate(timestamp);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.share_outlined,
              color: isDark ? Colors.white : Colors.black87,
              size: 22,
            ),
            onPressed: _captureAndShare,
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _globalKey,
        child: Container(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          child: Column(
            children: [
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 32),

                      // ──── Avatar Circle ────
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: getAvatarColor(displayName),
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.outfit(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ──── Direction + Name ────
                      Text(
                        isDebit ? 'To $displayName' : 'From $displayName',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ──── Amount ────
                      Text(
                        '₹${formatAmount(amount)}',
                        style: GoogleFonts.outfit(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ──── Status Badge ────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status == 'SUCCESS'
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: status == 'SUCCESS'
                                ? const Color(0xFF34A853)
                                : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status == 'SUCCESS' ? 'Completed' : 'Failed',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ──── Date ────
                      Text(
                        formattedDate,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600,
                        ),
                      ),

                      // ──── Risk Score (sender only, non-SAFE) ────
                      if (isDebit == true &&
                          transaction['risk_score'] != null &&
                          transaction['risk_score'] != 'SAFE' &&
                          transaction['risk_score'] != 'null')
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: transaction['risk_score'] == 'WARN'
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Risk: ${transaction['risk_score']}',
                              style: TextStyle(
                                color: transaction['risk_score'] == 'WARN'
                                    ? Colors.orange
                                    : Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                      // ──── Merchant Category Badge ────
                      if (merchantDomain != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade900
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              merchantDomain,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),

                      // ──── Pending Request Banner ────
                      if (_requestStatus == 'pending')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.amber.withValues(alpha: 0.08)
                                  : const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : const Color(0xFFFFE082),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.hourglass_top_rounded,
                                  color: Colors.amber.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Payment request pending',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.amber.shade300
                                          : Colors.amber.shade800,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isDebit && _existingRequestId != null)
                                  TextButton(
                                    onPressed: () => _cancelRequest(),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red.shade400,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'Withdraw',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 32),

                      // ──── Details Card ────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Transaction ID
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: _buildDetailRow(
                                context,
                                label: 'UPI transaction ID',
                                value: (transaction['transaction_id'] ?? '-')
                                    .toString()
                                    .replaceAll('TXN', ''),
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300,
                            ),
                            // To / From
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDetailRow(
                                    context,
                                    label: 'To: $receiverName',
                                    value: transaction['receiver_upi_id'] ?? '',
                                  ),
                                  const SizedBox(height: 12),
                                  _buildDetailRow(
                                    context,
                                    label: 'From: $senderName',
                                    value: transaction['sender_upi_id'] ?? '',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ──── Action Buttons (GPay‑style outlined) ────
                      if ((isDebit && !isMerchant && _showRequestButton) ||
                          (status == 'SUCCESS' && _showReportButton))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              // Request for amount
                              if (isDebit && !isMerchant && _showRequestButton)
                                Expanded(
                                  child: _buildActionChip(
                                    icon: Icons.currency_rupee_rounded,
                                    label: 'Request for amount',
                                    iconColor: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    labelColor: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    borderColor: isDark
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade400,
                                    onTap: () => _showRequestDialog(
                                      context,
                                      transaction,
                                      currentUpiId,
                                    ),
                                  ),
                                ),

                              // Spacer
                              if (isDebit &&
                                  !isMerchant &&
                                  _showRequestButton &&
                                  status == 'SUCCESS' &&
                                  _showReportButton)
                                const SizedBox(width: 12),

                              // Report complete
                              if (status == 'SUCCESS' && _showReportButton)
                                Expanded(
                                  child: _buildActionChip(
                                    icon: Icons.error_outline_rounded,
                                    label: 'Report complete',
                                    iconColor: isDark
                                        ? Colors.red.shade300
                                        : Colors.red.shade600,
                                    labelColor: isDark
                                        ? Colors.red.shade300
                                        : Colors.red.shade600,
                                    borderColor: isDark
                                        ? Colors.red.shade800.withValues(
                                            alpha: 0.5,
                                          )
                                        : Colors.red.shade200,
                                    onTap: () {
                                      launchUrl(
                                        Uri.parse(
                                          'https://cybercrime.gov.in/Webform/Crime_AuthoLogin.aspx?rnt=5',
                                        ),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 28),

                      // ──── Footer ────
                      Text(
                        'Powered by SafePay',
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──── Outlined action chip – GPay style ────
  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color labelColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        if (value.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(
              value,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _cancelRequest() async {
    if (_existingRequestId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Request'),
        content: const Text(
          'Are you sure you want to withdraw this payment request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _transactionService.cancelPaymentRequest(
      _existingRequestId!,
    );

    if (mounted) {
      if (success) {
        setState(() {
          _requestStatus = 'cancelled';
          _existingRequestId = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request withdrawn')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to withdraw request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ──────────────────────────────────────────────
  //  Request Money Bottom Sheet  – Clean GPay style
  // ──────────────────────────────────────────────
  void _showRequestDialog(
    BuildContext context,
    Map<String, dynamic> transaction,
    String currentUpiId,
  ) {
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountController = TextEditingController(
      text: transaction['amount'].toString(),
    );
    final noteController = TextEditingController();

    final senderUpi = transaction['sender_upi_id'];
    final receiverUpi = transaction['receiver_upi_id'];
    final targetUpi = (senderUpi == currentUpiId) ? receiverUpi : senderUpi;
    final targetName = (senderUpi == currentUpiId)
        ? (transaction['receiver_name'] ?? receiverUpi)
        : (transaction['sender_name'] ?? senderUpi);
    final targetInitial = (targetName as String).isNotEmpty
        ? targetName[0].toUpperCase()
        : '?';

    String selectedReason = 'wrongly_sent';
    bool isLoading = false;

    final reasons = {
      'wrongly_sent': 'Wrongly Sent',
      'wrong_amount': 'Wrong Amount',
      'other': 'Other',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Drag Handle ──
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Avatar ──
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: getAvatarColor(targetName),
                          ),
                          child: Center(
                            child: Text(
                              targetInitial,
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── Title ──
                        Text(
                          'Request Money',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'from $targetName',
                          style: GoogleFonts.outfit(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Reason Chips ──
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Reason',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: reasons.entries.map((entry) {
                            final isSelected = selectedReason == entry.key;
                            return ChoiceChip(
                              label: Text(entry.value),
                              selected: isSelected,
                              selectedColor: const Color(
                                0xFF00B9F1,
                              ).withValues(alpha: 0.15),
                              backgroundColor: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade100,
                              labelStyle: GoogleFonts.outfit(
                                color: isSelected
                                    ? const Color(0xFF00B9F1)
                                    : (isDark
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade700),
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? const Color(0xFF00B9F1)
                                    : Colors.transparent,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              onSelected: (_) {
                                setSheetState(() => selectedReason = entry.key);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // ── Amount Input ──
                        TextField(
                          controller: amountController,
                          readOnly: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: GoogleFonts.outfit(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            labelStyle: GoogleFonts.outfit(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            prefixText: '₹ ',
                            prefixStyle: GoogleFonts.outfit(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.grey.shade900
                                : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF00B9F1),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Note Input ──
                        TextField(
                          controller: noteController,
                          maxLength: 100,
                          onChanged: (val) => setSheetState(
                            () {},
                          ), // Trigger rebuild for validation
                          style: GoogleFonts.outfit(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: selectedReason == 'other'
                                ? 'Note (Required)'
                                : 'Note (Optional)',
                            labelStyle: GoogleFonts.outfit(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.grey.shade900
                                : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF00B9F1),
                                width: 2,
                              ),
                            ),
                            counterStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Action Buttons ──
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isLoading
                                    ? null
                                    : () => Navigator.pop(sheetContext),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade400,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.outfit(
                                    color: isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed:
                                    (isLoading ||
                                        (selectedReason == 'other' &&
                                            noteController.text.trim().isEmpty))
                                    ? null
                                    : () async {
                                        final amount = double.tryParse(
                                          amountController.text,
                                        );
                                        if (amount == null || amount <= 0) {
                                          ScaffoldMessenger.of(
                                            sheetContext,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Enter a valid amount',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        setSheetState(() => isLoading = true);

                                        final result = await _transactionService
                                            .requestMoney(
                                              payerUpiId: targetUpi,
                                              amount: amount,
                                              reason: selectedReason,
                                              description:
                                                  noteController.text.isEmpty
                                                  ? null
                                                  : noteController.text,
                                              originalTransactionId:
                                                  transaction['transaction_id']
                                                      ?.toString(),
                                            );

                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext);
                                        }

                                        // Wait slightly for modal animation to ensure parent context is active
                                        await Future.delayed(
                                          const Duration(milliseconds: 100),
                                        );

                                        if (!mounted) return;

                                        if (result['success'] == true) {
                                          setState(() {
                                            _requestStatus = 'pending';
                                            _existingRequestId =
                                                result['data']?['id'];
                                          });

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                'Request sent successfully!',
                                              ),
                                              backgroundColor:
                                                  Colors.green.shade600,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                result['message'] ??
                                                    'Failed to send request',
                                              ),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00B9F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  elevation: 0,
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'Send Request',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
