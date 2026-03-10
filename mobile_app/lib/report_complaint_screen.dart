import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'contact_service.dart';
import 'api_service.dart';
import 'cyber_chatbot_screen.dart';

class ReportComplaintScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final String currentUpiId;

  const ReportComplaintScreen({
    super.key,
    required this.transaction,
    required this.currentUpiId,
  });

  @override
  State<ReportComplaintScreen> createState() => _ReportComplaintScreenState();
}

class _ReportComplaintScreenState extends State<ReportComplaintScreen> {
  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();

  List<String> get _complaintReasons => [
    AppLocalizations.of(context)?.translate('details.fraud_txn') ??
        'Fraudulent Transaction',
    AppLocalizations.of(context)?.translate('details.service_not_received') ??
        'Service not received',
    AppLocalizations.of(context)?.translate('details.wrongly_sent') ??
        'Sent to wrong person',
    AppLocalizations.of(context)?.translate('details.unauthorized_txn') ??
        'Unauthorized Transaction',
    AppLocalizations.of(context)?.translate('details.other') ?? 'Other',
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint({
    required String senderName,
    required String senderUpiId,
    required String senderBank,
    required String receiverName,
    required String receiverUpiId,
    required String receiverBank,
    required String transactionDate,
    required String transactionTime,
    required String transactionAmount,
    String? paymentThrough,
  }) async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
                  context,
                )?.translate('details.select_reason_error') ??
                'Please select a reason for the complaint.',
            style: GoogleFonts.notoSans(color: Colors.white),
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    if (_selectedReason ==
            (AppLocalizations.of(context)?.translate('details.other') ??
                'Other') &&
        _otherReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
                  context,
                )?.translate('details.other_reason_error') ??
                'Please provide a description when selecting "Other".',
            style: GoogleFonts.notoSans(color: Colors.white),
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    // Determine the reported user UPI (Receiver UPI)
    final reportedUserUpi = widget.transaction['receiver_upi_id'];

    if (reportedUserUpi == null || reportedUserUpi == 'Unknown') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
                  context,
                )?.translate('details.identify_account_error') ??
                'Unable to identify the reported account.',
            style: GoogleFonts.notoSans(color: Colors.white),
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ApiService().submitComplaint(
        transactionId:
            widget.transaction['id'] ?? widget.transaction['transaction_id'],
        reportedUserUpi: reportedUserUpi,
        reason: _selectedReason!,
        description: _otherReasonController.text.trim(),
        senderName: senderName,
        senderUpiId: senderUpiId,
        senderBank: senderBank,
        receiverName: receiverName,
        receiverUpiId: receiverUpiId,
        receiverBank: receiverBank,
        transactionDate: transactionDate,
        transactionTime: transactionTime,
        transactionAmount: transactionAmount,
        paymentThrough: paymentThrough,
      );

      if (!mounted) return;

      Navigator.of(context).pop(); // Remove loading indicator

      if (!result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ??
                  (AppLocalizations.of(
                        context,
                      )?.translate('details.error_generic') ??
                      'Failed to submit complaint. Please try again.'),
              style: GoogleFonts.notoSans(color: Colors.white),
            ),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }

      // Show success dialog, then launch cyber crime link
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green.shade600,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  AppLocalizations.of(
                        context,
                      )?.translate('details.complaint_success') ??
                      'Complaint Submitted\nSuccessfully!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(
                        context,
                      )?.translate('details.complaint_success_msg') ??
                      'Your complaint has been submitted to ZaferPay. You will now be redirected to the Cyber Crime portal to file an official report.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop(); // Close dialog
                      // Launch the cyber crime website
                      launchUrl(
                        Uri.parse(
                          'https://cybercrime.gov.in/Webform/Crime_AuthoLogin.aspx?rnt=5',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                      // Pop complaint screen so user returns to transaction details
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B9F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.continue_portal') ??
                          'Continue to Cyber Crime Portal',
                      style: GoogleFonts.notoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(); // Close dialog
                    Navigator.of(
                      context,
                    ).pop(); // Go back to transaction details
                  },
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('details.go_back') ??
                        'Go Back',
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Remove loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.translate('details.error_generic') ??
                'An error occurred. Please try again.',
            style: GoogleFonts.notoSans(color: Colors.white),
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String formatName(String rawName) {
      if (rawName == 'Unknown') return rawName;
      String name = rawName;
      if (name.contains('@')) {
        name = name.split('@')[0];
      }

      // If the name is just a 10 digit number, try to resolve it from local contacts
      if (RegExp(r'^\d{10}$').hasMatch(name)) {
        try {
          final contacts = ContactService.instance.contacts;
          for (final c in contacts) {
            for (final p in c.phones) {
              final normalized = p.number.replaceAll(RegExp(r'\D'), '');
              if (normalized.endsWith(name)) {
                return c.displayName;
              }
            }
          }
        } catch (_) {
          // Ignore if contacts aren't loaded or available
        }
      }

      return name;
    }

    // Get fresh current user data to override stale cached transaction names
    final currentUser = ApiService().getUserSync();
    final currentUsername = currentUser?['username'];
    final isCurrentUserSender =
        transaction['sender_upi_id'] == widget.currentUpiId;
    final isCurrentUserReceiver =
        transaction['receiver_upi_id'] == widget.currentUpiId;

    final senderNameRaw = isCurrentUserSender && currentUsername != null
        ? currentUsername
        : (transaction['sender_full_name'] ??
              transaction['sender_name'] ??
              transaction['sender_upi_id'] ??
              (AppLocalizations.of(context)?.translate('amount.unknown') ??
                  'Unknown'));
    final senderName = formatName(senderNameRaw);

    final senderUpiId = transaction['sender_upi_id'] ?? 'Unknown';

    final receiverNameRaw = isCurrentUserReceiver && currentUsername != null
        ? currentUsername
        : (transaction['receiver_full_name'] ??
              transaction['receiver_name'] ??
              transaction['receiver_upi_id'] ??
              'Unknown');
    final receiverName = formatName(receiverNameRaw);
    final receiverUpiId =
        transaction['receiver_upi_id'] ??
        (AppLocalizations.of(context)?.translate('amount.unknown') ??
            'Unknown');

    // Helper function to extract bank name from UPI ID
    String getLocalizedBankFromUpi(BuildContext context, String upiId) {
      final loc = AppLocalizations.of(context);
      if (upiId == 'Unknown' || !upiId.contains('@')) {
        return loc?.translate('profile.bank_unknown') ?? 'Unknown Bank';
      }
      final suffix = upiId.split('@').last.toLowerCase();
      if (suffix.contains('sbi')) {
        return loc?.translate('profile.bank_sbi') ?? 'State Bank of India';
      }
      if (suffix.contains('hdfc') || suffix.contains('okhdfc')) {
        return loc?.translate('profile.bank_hdfc') ?? 'HDFC Bank';
      }
      if (suffix.contains('icici') ||
          suffix.contains('okicici') ||
          suffix.contains('ibl')) {
        return loc?.translate('profile.bank_icici') ?? 'ICICI Bank';
      }
      if (suffix.contains('axis') ||
          suffix.contains('okaxis') ||
          suffix.contains('axl')) {
        return loc?.translate('profile.bank_axis') ?? 'Axis Bank';
      }
      if (suffix.contains('ybl')) return 'Yes Bank';
      if (suffix.contains('ikwik')) return 'Kwik (MobiKwik)';
      if (suffix.contains('paytm')) return 'Paytm Payments Bank';
      if (suffix.contains('sib')) return 'South Indian Bank';
      return suffix.toUpperCase(); // Fallback to just showing the suffix
    }

    final senderBank =
        (transaction['sender_bank_name'] != null &&
            transaction['sender_bank_name'] != 'Unknown')
        ? transaction['sender_bank_name']
        : getLocalizedBankFromUpi(context, senderUpiId);

    final receiverBank =
        (transaction['receiver_bank_name'] != null &&
            transaction['receiver_bank_name'] != 'Unknown')
        ? transaction['receiver_bank_name']
        : getLocalizedBankFromUpi(context, receiverUpiId);
    final transactionId = (transaction['transaction_id'] ?? '-')
        .toString()
        .replaceAll('TXN', '');

    // Parse transaction date and time from timestamp
    String transactionDate = '-';
    String transactionTime = '-';
    final rawTimestamp = transaction['timestamp'];
    if (rawTimestamp != null) {
      try {
        final dt = DateTime.parse(rawTimestamp.toString()).toLocal();
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        transactionDate =
            '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
        final hour = dt.hour > 12
            ? dt.hour - 12
            : (dt.hour == 0 ? 12 : dt.hour);
        final amPm = dt.hour >= 12 ? 'PM' : 'AM';
        transactionTime =
            '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} $amPm';
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)?.translate('details.submit_complaint') ??
              'Report Complaint',
          style: GoogleFonts.notoSans(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: isDark ? Colors.white : Colors.black87,
              ),
              offset: const Offset(0, 48),
              color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              onSelected: (value) {
                if (value == 'get_help') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CyberChatbotScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'get_help',
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('details.get_help') ??
                        'Get help',
                    style: GoogleFonts.notoSans(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.sender_name') ??
                          'Sender Name',
                      senderName,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.sender_upi') ??
                          'Sender UPI ID',
                      senderUpiId,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.receiver_name') ??
                          'Receiver Name',
                      receiverName,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.receiver_upi') ??
                          'Receiver UPI ID',
                      receiverUpiId,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.txn_id_label') ??
                          'Transaction ID',
                      transactionId,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.txn_date') ??
                          'Transaction Date',
                      transactionDate,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.txn_time') ??
                          'Transaction Time',
                      transactionTime,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.sender_bank') ??
                          'Sender Bank name',
                      senderBank,
                      isDark,
                    ),
                    _buildDetailRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.receiver_bank') ??
                          'Receiver Bank name',
                      receiverBank,
                      isDark,
                    ),

                    // Pay Through (UPI Circle or Self)
                    Builder(
                      builder: (context) {
                        final initiatedByName =
                            transaction['initiated_by_name'];
                        final payThrough = initiatedByName != null
                            ? (AppLocalizations.of(context)?.translate(
                                    'details.upi_circle_by',
                                    arguments: {'name': initiatedByName},
                                  ) ??
                                  'UPI Circle by $initiatedByName')
                            : (AppLocalizations.of(
                                    context,
                                  )?.translate('details.self') ??
                                  'Self');
                        return _buildDetailRow(
                          AppLocalizations.of(
                                context,
                              )?.translate('details.pay_through') ??
                              'Pay Through',
                          payThrough,
                          isDark,
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    _buildFormRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.reason_label') ??
                          'Reason for complaint',
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: isDark ? Colors.grey.shade900 : Colors.white,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedReason,
                            hint: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('details.select_reason') ??
                                  'Select a reason',
                              style: GoogleFonts.notoSans(
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                            isExpanded: true,
                            dropdownColor: isDark
                                ? Colors.grey.shade900
                                : Colors.white,
                            icon: Icon(
                              Icons.keyboard_arrow_down,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                            ),
                            items: _complaintReasons.map((String reason) {
                              return DropdownMenuItem<String>(
                                value: reason,
                                child: Text(
                                  reason,
                                  style: GoogleFonts.notoSans(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedReason = newValue;
                              });
                            },
                          ),
                        ),
                      ),
                      isDark,
                    ),

                    _buildFormRow(
                      AppLocalizations.of(
                            context,
                          )?.translate('details.description') ??
                          'Description',
                      TextField(
                        controller: _otherReasonController,
                        maxLines: 4,
                        style: GoogleFonts.notoSans(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              _selectedReason ==
                                  (AppLocalizations.of(
                                        context,
                                      )?.translate('details.other') ??
                                      'Other')
                              ? (AppLocalizations.of(
                                      context,
                                    )?.translate('details.required') ??
                                    'Required')
                              : (AppLocalizations.of(
                                      context,
                                    )?.translate('details.optional') ??
                                    'Optional'),
                          hintStyle: GoogleFonts.notoSans(
                            color: isDark
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ),
                      isDark,
                    ),

                    const SizedBox(height: 32),

                    // Warning Alert Box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('details.complaint_warning') ??
                                  'If you fill this, it will not be filed as a complaint in cyber crime. You must file manually in the cyber crime website after clicking the Submit Complaint button.',
                              style: GoogleFonts.notoSans(
                                color: isDark
                                    ? Colors.red.shade200
                                    : Colors.red.shade800,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Fixed Bottom Action Area
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('common.cancel') ??
                                'Cancel',
                            style: GoogleFonts.notoSans(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _submitComplaint(
                            senderName: senderName,
                            senderUpiId: senderUpiId,
                            senderBank: senderBank,
                            receiverName: receiverName,
                            receiverUpiId: receiverUpiId,
                            receiverBank: receiverBank,
                            transactionDate: transactionDate,
                            transactionTime: transactionTime,
                            transactionAmount: (transaction['amount'] ?? 0)
                                .toString(),
                            paymentThrough:
                                transaction['initiated_by_name'] != null
                                ? 'UPI Circle by ${transaction['initiated_by_name']}'
                                : 'Self',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('details.submit_complaint') ??
                                'Submit Complaint',
                            style: GoogleFonts.notoSans(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('common.powered_by') ??
                        'Powered by ZaferPay',
                    style: GoogleFonts.notoSans(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowLabel(String label, bool isDark, {bool alignTop = false}) {
    return Padding(
      padding: EdgeInsets.only(top: alignTop ? 12.0 : 0.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              style: GoogleFonts.notoSans(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.visible,
            ),
          ),
          Text(
            ':   ',
            style: GoogleFonts.notoSans(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRowLabel(label, isDark),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.notoSans(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormRow(String label, Widget child, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRowLabel(label, isDark, alignTop: true),
          Expanded(child: child),
        ],
      ),
    );
  }
}
