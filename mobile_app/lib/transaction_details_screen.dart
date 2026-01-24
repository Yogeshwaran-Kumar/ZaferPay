import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class TransactionDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final String currentUpiId;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
    required this.currentUpiId,
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

        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(file.path)]);
      }
    } catch (e) {
      debugPrint('Error sharing: $e');
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
                  backgroundColor:
                      Colors.deepOrange, // Matches the "V" orange circle style
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
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
                const SizedBox(height: 8),
                // Amount
                Text(
                  '₹$amount',
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
                // Footer branding/text (Optional, but adds to the look)
                Text(
                  'Powered by 2Way',
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
      // Backend returns UTC (e.g. "2026-01-24T12:00:00") but potentially without 'Z'.
      // If we parse directly, Dart might treat it as local.
      // We force it to be parsed as UTC by appending 'Z' if missing.
      String timeStr = timestamp;
      if (!timeStr.endsWith('Z')) {
        timeStr += 'Z';
      }

      final dt = DateTime.parse(timeStr).toLocal();
      // Format: "9 Jan 2026, 6:22 pm"
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (e) {
      return timestamp;
    }
  }
}
