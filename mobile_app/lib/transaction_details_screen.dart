import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'mcc_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobile_app/main.dart';
import 'api_service.dart';
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
      MyApp.isSharing = false; // Ensure reset on error before catch block ends
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
    final isMerchant =
        mcc != null && mcc != '0000' && mcc.toString().trim().isNotEmpty;
    final merchantDomain =
        widget.merchantCategory ??
        (isMerchant ? MccHelper.getDomain(mcc.toString()) : null);

    final senderName =
        transaction['sender_name'] ?? transaction['sender_upi_id'] ?? 'Unknown';
    final receiverName =
        transaction['receiver_name'] ??
        transaction['receiver_upi_id'] ??
        'Unknown';

    // Display Name logic: If I sent it, show "To Receiver". If I received it, show "From Sender".
    final displayName = isDebit ? receiverName : senderName;

    final formattedDate = _formatDate(timestamp);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Theme.of(context).iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Report Flag - Subtle but accessible
          if (status == 'SUCCESS')
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: Theme.of(context).iconTheme.color,
              ),
              onSelected: (value) {
                if (value == 'report') {
                  _showReportDialog(context, transaction);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        color: isDark
                            ? Colors.red.shade300
                            : Colors.red.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Report issue',
                        style: TextStyle(
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: Icon(Icons.share, color: Theme.of(context).iconTheme.color),
            onPressed: _captureAndShare,
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _globalKey,
        child: Container(
          color: Theme.of(
            context,
          ).scaffoldBackgroundColor, // Background for capture
          height: MediaQuery.of(context).size.height, // Capture full height
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Avatar
                CircleAvatar(
                  radius: 36,
                  backgroundColor: isMerchant
                      ? Colors.orange
                      : Colors.deepOrange,
                  child: isMerchant
                      ? const Icon(Icons.store, color: Colors.white, size: 36)
                      : Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                // To/From Text
                Text(
                  isDebit ? 'To $displayName' : 'From $displayName',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                if (merchantDomain != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      merchantDomain,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Amount
                Text(
                  '₹${formatAmount(amount)}',
                  style: GoogleFonts.outfit(
                    fontSize: 48,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 24),
                // Status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      status == 'SUCCESS' ? Icons.check_circle : Icons.error,
                      color: status == 'SUCCESS' ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      status == 'SUCCESS' ? 'Completed' : status,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey.shade300 : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Date
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Divider(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade300,
                        indent: 64,
                        endIndent: 64,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formattedDate, // "9 Jan 2026, 6:22 pm"
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Details Card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
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
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildDetailRow(
                          context,
                          label: 'UPI transaction ID',
                          value: (transaction['transaction_id'] ?? '-')
                              .toString()
                              .replaceAll('TXN', ''), // Clean up ID visually
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark ? Colors.grey.shade800 : null,
                      ),
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
                            const SizedBox(height: 16),
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
                const SizedBox(height: 30),

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
      ),
    );
  }

  void _showReportDialog(
    BuildContext context,
    Map<String, dynamic> transaction,
  ) {
    String? selectedReason;
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Report as Fraud'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why are you reporting this transaction?',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                _buildReasonOption(
                  context,
                  'not_me',
                  'I didn\'t make this transaction',
                  selectedReason,
                  (value) => setState(() => selectedReason = value),
                ),
                _buildReasonOption(
                  context,
                  'wrong_amount',
                  'Amount is incorrect',
                  selectedReason,
                  (value) => setState(() => selectedReason = value),
                ),
                _buildReasonOption(
                  context,
                  'unknown_receiver',
                  'I don\'t know this person',
                  selectedReason,
                  (value) => setState(() => selectedReason = value),
                ),
                _buildReasonOption(
                  context,
                  'other',
                  'Other reason',
                  selectedReason,
                  (value) => setState(() => selectedReason = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _submitFraudReport(
                        context,
                        transaction['transaction_id'],
                        selectedReason!,
                        descriptionController.text,
                      );
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Submit Report',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonOption(
    BuildContext context,
    String value,
    String label,
    String? selectedReason,
    Function(String) onChanged,
  ) {
    return RadioListTile<String>(
      value: value,
      groupValue: selectedReason,
      onChanged: (v) => onChanged(v!),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Future<void> _submitFraudReport(
    BuildContext context,
    String transactionId,
    String reason,
    String description,
  ) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Use ApiService to report fraud
      final apiService = ApiService();
      final result = await apiService.reportFraud(
        transactionId: transactionId,
        reason: reason,
        description: description.isEmpty ? null : description,
      );

      // Hide loading
      if (context.mounted) Navigator.pop(context);

      // Show result
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Report submitted'),
            backgroundColor: result['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit report'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        if (value.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
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
      // Backend returns Local Time (naive). Do NOT force UTC 'Z'.
      final dt = DateTime.parse(timestamp).toLocal();
      // Format: "9 Jan 2026, 6:22 pm"
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (e) {
      return timestamp;
    }
  }
}
