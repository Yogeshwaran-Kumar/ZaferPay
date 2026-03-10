import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // Added for Clipboard
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart' as fp;
import 'package:gal/gal.dart';
import 'services/app_localizations.dart';
import 'api_service.dart';
import 'mcc_helper.dart';
import 'main.dart';
import 'utils.dart';
import 'language_selection_screen.dart';
import 'cyber_chatbot_screen.dart';
import 'upi_circle_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ProfileScreen({super.key, this.onBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  final _storage = const FlutterSecureStorage();
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final cachedUser = await _api.getCachedMe();
    if (cachedUser != null && mounted) {
      setState(() {
        _user = cachedUser;
        _isLoading = false;
      });
    }

    try {
      final user = await _api.getMe();
      if (mounted && user != null) {
        setState(() {
          _user = user;
          _isLoading = false;
        });
      } else if (mounted && _user == null) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted && _user == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.translate('settings.logout') ??
              'Logout',
        ),
        content: Text(
          AppLocalizations.of(context)?.translate('profile.logout_confirm') ??
              'Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              AppLocalizations.of(context)?.translate('details.cancel') ??
                  'Cancel',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              AppLocalizations.of(context)?.translate('settings.logout') ??
                  'Logout',
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _api.wipeAllCaches();
      await _api.logout();
      await _storage.deleteAll();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context)?.translate('profile.load_failed') ??
                'Failed to load profile',
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.grey.shade400 : Colors.black54;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryTextColor),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _user!['username']?.toUpperCase() ??
                              (AppLocalizations.of(context)
                                      ?.translate('profile.user_placeholder')
                                      ?.toUpperCase() ??
                                  'USER'),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final upiId = _user!['upi_id']?.toString() ?? "";
                            if (upiId.isNotEmpty) {
                              await Clipboard.setData(
                                ClipboardData(text: upiId),
                              );
                              // Removed Snackbar notification per user request
                            }
                          },
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${AppLocalizations.of(context)?.translate('profile.upi_id') ?? "UPI ID"}: ${_user!['upi_id'] ?? ""}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: secondaryTextColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: secondaryTextColor,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              _user!['mobile_number'] ??
                                  _user!['mobile'] ??
                                  _user!['phone_number'] ??
                                  "",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: Colors.blue,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _showQrOverlay(context);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: getAvatarColor(_user!['username']),
                          child: Text(
                            (_user!['username']?[0] ??
                                    (AppLocalizations.of(context)?.translate(
                                          'profile.avatar_placeholder',
                                        ) ??
                                        'U'))
                                .toUpperCase(),
                            style: GoogleFonts.notoSans(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2C)
                                  : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.qr_code_rounded,
                              size: 16,
                              color: primaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                AppLocalizations.of(
                      context,
                    )?.translate('profile.payment_methods') ??
                    'Set up payment methods',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildOptionItem(
              icon: Icons.account_balance_outlined,
              title:
                  AppLocalizations.of(
                    context,
                  )?.translate('profile.bank_account') ??
                  'Bank account',
              subtitle:
                  AppLocalizations.of(
                    context,
                  )?.translate('profile.one_account') ??
                  '1 account',
              onTap: () {
                // Future: Navigate to bank accounts
              },
            ),
            _buildOptionItem(
              icon: Icons.group_outlined,
              title:
                  AppLocalizations.of(
                    context,
                  )?.translate('profile.upi_circle') ??
                  'UPI Circle',
              subtitle:
                  AppLocalizations.of(
                    context,
                  )?.translate('profile.upi_circle_subtitle') ??
                  'Manage shared limits & circle payments',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UPICircleScreen(),
                  ),
                );
              },
            ),

            // Menu Options List
            _buildOptionItem(
              icon: Icons.qr_code_rounded,
              title:
                  AppLocalizations.of(context)?.translate('profile.qr_code') ??
                  'Your QR code',
              onTap: () => _showQrOverlay(context),
            ),
            _buildOptionItem(
              icon: Icons.settings_outlined,
              title:
                  AppLocalizations.of(context)?.translate('settings.title') ??
                  'Settings',
              onTap: () {
                Navigator.pushNamed(context, '/settings');
              },
            ),
            _buildOptionItem(
              icon: Icons.help_outline,
              title:
                  AppLocalizations.of(context)?.translate('profile.get_help') ??
                  'Get help',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CyberChatbotScreen(),
                  ),
                );
              },
            ),
            _buildOptionItem(
              icon: Icons.language,
              title:
                  AppLocalizations.of(context)?.translate('profile.language') ??
                  'Language',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LanguageSelectionScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.logout_rounded,
                color: Colors.red,
                size: 28,
              ),
              title: Text(
                AppLocalizations.of(context)?.translate('settings.logout') ??
                    'Logout',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              onTap: _handleLogout,
            ),

            const SizedBox(height: 40),

            // Powered By Footer
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('common.powered_by') ??
                        "Powered by ZaferPay",
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.grey,
                      letterSpacing: 0.5,
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

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: isDark ? Colors.white70 : Colors.black87),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  size: 24,
                ),
          ],
        ),
      ),
    );
  }

  // Removed _downloadQrCode

  String _getBankLogoUrl(String bankName) {
    final lower = bankName.toLowerCase();
    if (lower.contains('sbi')) {
      return 'https://logo.clearbit.com/onlinesbi.sbi';
    }
    if (lower.contains('axis')) {
      return 'https://logo.clearbit.com/axisbank.com';
    }
    if (lower.contains('icici')) {
      return 'https://logo.clearbit.com/icicibank.com';
    }
    if (lower.contains('hdfc')) {
      return 'https://logo.clearbit.com/hdfcbank.com';
    }
    return 'https://logo.clearbit.com/${lower.replaceAll(' ', '')}.com';
  }

  String _getFullBankName(String bankName) {
    final lower = bankName.toLowerCase();
    final loc = AppLocalizations.of(context);
    if (lower.contains('sbi')) {
      return loc?.translate('profile.bank_sbi') ?? 'State Bank of India';
    }
    if (lower.contains('axis')) {
      return loc?.translate('profile.bank_axis') ?? 'Axis Bank';
    }
    if (lower.contains('icici')) {
      return loc?.translate('profile.bank_icici') ?? 'ICICI Bank';
    }
    if (lower.contains('hdfc')) {
      return loc?.translate('profile.bank_hdfc') ?? 'HDFC Bank';
    }
    return bankName;
  }

  bool isCapturingQr = false;

  Future<void> _handleScanFromProfile(BuildContext context) async {
    Navigator.pop(context); // close the QR modal
    final scanResult = await Navigator.pushNamed(
      context,
      '/scan',
      arguments: _user,
    );
    if (scanResult != null) {
      String scannedUpi = "";
      String? scannedMcc;
      String? scannedName;
      String? scannedAmount;

      if (scanResult is Map) {
        scannedUpi = scanResult['upi'] ?? "";
        scannedMcc = scanResult['mcc'];
        scannedName = scanResult['name'];
        scannedAmount = scanResult['amount'];
      } else if (scanResult is String) {
        scannedUpi = scanResult;
      }

      final myUpi = _user?['upi_id'];
      if (myUpi != null && myUpi == scannedUpi) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('profile.cannot_pay_self') ??
                  'Cannot send money to self',
            ),
          ),
        );
        return;
      }

      if (!context.mounted) return;
      String? category;
      if (scannedMcc != null && scannedMcc.isNotEmpty) {
        category = MccHelper.getDomain(scannedMcc);
      }

      final nav = Navigator.of(context);
      await nav.pushNamed(
        '/amount',
        arguments: {
          'upi': scannedUpi,
          'name': scannedName,
          'category': category,
          'mcc': scannedMcc,
          'senderBalance': _user?['balance'],
          'senderUpi': _user?['upi_id'],
          'payment_source': (scanResult is Map)
              ? scanResult['payment_source']
              : null, // Forward telemetry
          if (scannedAmount != null) 'prefillAmount': scannedAmount,
          if (scannedAmount != null) 'isLockedAmount': true,
        },
      );
    }
  }

  void _showQrOverlay(BuildContext context) {
    if (_user == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF111318) : const Color(0xFFF7F9FC);
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF1F1F1F);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: bgColor, // Full screen modal illusion
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        bool isCopied = false;
        String? qrAmount;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: Scaffold(
                backgroundColor: bgColor,
                resizeToAvoidBottomInset: false,
                body: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Top Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.arrow_back,
                                color: primaryTextColor,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.download_rounded,
                                color: primaryTextColor,
                              ),
                              onPressed: () =>
                                  _downloadQrCodeWithCapture(setModalState),
                            ),
                            Theme(
                              data: Theme.of(context).copyWith(
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                              child: PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: primaryTextColor,
                                ),
                                offset: const Offset(0, 48),
                                color: isDark
                                    ? const Color(0xFF1F1F1F)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 8,
                                onSelected: (value) async {
                                  if (value == 'set_amount') {
                                    final amountController =
                                        TextEditingController(
                                          text: qrAmount ?? '',
                                        );
                                    final result = await showDialog<String>(
                                      context: context,
                                      useSafeArea: false,
                                      builder: (context) {
                                        return StatefulBuilder(
                                          builder: (context, setDialogState) {
                                            return Dialog(
                                              backgroundColor: isDark
                                                  ? const Color(0xFF1F1F1F)
                                                  : Colors.white,
                                              insetPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 24,
                                                    vertical: 24,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                              child: SingleChildScrollView(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    24.0,
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        AppLocalizations.of(
                                                              context,
                                                            )?.translate(
                                                              'profile.enter_amount',
                                                            ) ??
                                                            'Enter amount',
                                                        style: GoogleFonts.notoSans(
                                                          color:
                                                              primaryTextColor,
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 32,
                                                      ),
                                                      Center(
                                                        child: IntrinsicWidth(
                                                          child: TextField(
                                                            controller:
                                                                amountController,
                                                            keyboardType:
                                                                const TextInputType.numberWithOptions(
                                                                  decimal: true,
                                                                ),
                                                            autofocus: true,
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: GoogleFonts.notoSans(
                                                              color:
                                                                  primaryTextColor,
                                                              fontSize: 48,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                            decoration: InputDecoration(
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              prefixText: '₹ ',
                                                              prefixStyle:
                                                                  GoogleFonts.notoSans(
                                                                    color:
                                                                        primaryTextColor,
                                                                    fontSize:
                                                                        48,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w400,
                                                                  ),
                                                              hintText: '0',
                                                              hintStyle:
                                                                  GoogleFonts.notoSans(
                                                                    color: Colors
                                                                        .grey,
                                                                    fontSize:
                                                                        48,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w400,
                                                                  ),
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 32,
                                                      ),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .end,
                                                        children: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                ),
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                    context,
                                                                  )?.translate(
                                                                    'details.cancel',
                                                                  ) ??
                                                                  'Cancel',
                                                              style: GoogleFonts.notoSans(
                                                                color: isDark
                                                                    ? const Color(
                                                                        0xFFA8C7FA,
                                                                      )
                                                                    : const Color(
                                                                        0xFF0b57d0,
                                                                      ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                fontSize: 15,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  amountController
                                                                      .text
                                                                      .trim(),
                                                                ),
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                    context,
                                                                  )?.translate(
                                                                    'details.ok',
                                                                  ) ??
                                                                  'OK',
                                                              style: GoogleFonts.notoSans(
                                                                color: isDark
                                                                    ? const Color(
                                                                        0xFFA8C7FA,
                                                                      )
                                                                    : const Color(
                                                                        0xFF0b57d0,
                                                                      ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                fontSize: 15,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );

                                    if (result != null) {
                                      setModalState(() {
                                        qrAmount = result.isEmpty
                                            ? null
                                            : result;
                                      });
                                    }
                                  } else if (value == 'get_help') {
                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const CyberChatbotScreen(),
                                      ),
                                    );
                                  }
                                },
                                itemBuilder: (BuildContext context) => [
                                  PopupMenuItem<String>(
                                    value: 'set_amount',
                                    child: Text(
                                      AppLocalizations.of(
                                            context,
                                          )?.translate('profile.set_amount') ??
                                          'Set Amount',
                                      style: GoogleFonts.notoSans(
                                        color: primaryTextColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'get_help',
                                    child: Text(
                                      AppLocalizations.of(
                                            context,
                                          )?.translate('profile.get_help') ??
                                          'Get help',
                                      style: GoogleFonts.notoSans(
                                        color: primaryTextColor,
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
                      ),

                      const Spacer(flex: 1),

                      // Main Card area
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.3 : 0.05,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // QR Download Area
                              RepaintBoundary(
                                key: _qrKey,
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.only(
                                    top: 24,
                                    bottom: 12,
                                    left: 16,
                                    right: 16,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Horizontal User Header
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: getAvatarColor(
                                                _user!['username'],
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                _user!['username']?[0]
                                                        .toUpperCase() ??
                                                    '?',
                                                style: GoogleFonts.notoSans(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: Text(
                                              _user!['username']
                                                      ?.toUpperCase() ??
                                                  'USER',
                                              style: GoogleFonts.notoSans(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF1F1F1F),
                                                letterSpacing: 0.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),

                                      // Account Type Badge
                                      Builder(
                                        builder: (context) {
                                          final isPersonal =
                                              MccHelper.isPersonal(
                                                _user!['mcc'],
                                              );
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isPersonal
                                                  ? const Color(
                                                      0xFF1A73E8,
                                                    ) // Google Blue
                                                  : Colors.orange,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isPersonal
                                                      ? Icons.person
                                                      : Icons
                                                            .storefront_outlined,
                                                  size: 18,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  isPersonal
                                                      ? (AppLocalizations.of(
                                                              context,
                                                            )?.translate(
                                                              'profile.personal_account',
                                                            ) ??
                                                            'Personal Account')
                                                      : (AppLocalizations.of(
                                                              context,
                                                            )?.translate(
                                                              'profile.merchant_account',
                                                            ) ??
                                                            'Merchant Account'),
                                                  style: GoogleFonts.notoSans(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // QR Code
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                String qrData =
                                                    'upi://pay?pa=${_user!['upi_id']}&pn=${Uri.encodeComponent(_user!['username'])}&mc=${_user!['mcc'] ?? ""}';
                                                if (qrAmount != null &&
                                                    qrAmount!.isNotEmpty) {
                                                  qrData += '&am=$qrAmount';
                                                }
                                                return QrImageView(
                                                  data: qrData,
                                                  version: QrVersions.auto,
                                                  errorCorrectionLevel:
                                                      QrErrorCorrectLevel.H,
                                                  size: 220.0,
                                                  backgroundColor: Colors.white,
                                                );
                                              },
                                            ),
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.1),
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Image.asset(
                                                  'assets/zaferpay_z.png',
                                                  width: 36,
                                                  height: 36,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Scan text
                                      Text(
                                        AppLocalizations.of(context)?.translate(
                                              'profile.scan_to_pay_msg',
                                            ) ??
                                            "Scan to pay with any UPI app",
                                        style: GoogleFonts.notoSans(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.lerp(
                                            FontWeight.w400,
                                            FontWeight.w500,
                                            0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Bank Info Chip (inside Boundary now)
                                      if (!isCapturingQr &&
                                          _user!['bank_name'] != null &&
                                          _user!['bank_name']
                                              .toString()
                                              .isNotEmpty &&
                                          _user!['bank_name']
                                                  .toString()
                                                  .toLowerCase() !=
                                              'merchant')
                                        Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.1,
                                                  )
                                                : Colors.grey.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: isDark
                                                ? null
                                                : Border.all(
                                                    color: Colors.grey.shade200,
                                                  ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Image.network(
                                                  _getBankLogoUrl(
                                                    _user!['bank_name']
                                                        .toString(),
                                                  ),
                                                  width: 16,
                                                  height: 16,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Icon(
                                                          Icons
                                                              .account_balance_rounded,
                                                          size: 16,
                                                          color: Colors
                                                              .orange
                                                              .shade400,
                                                        );
                                                      },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _getFullBankName(
                                                    _user!['bank_name']
                                                        .toString(),
                                                  ),
                                                  style: GoogleFonts.notoSans(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: const Color(
                                                      0xFF1F1F1F,
                                                    ),
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      if (isCapturingQr)
                                        Column(
                                          children: [
                                            Text(
                                              '${AppLocalizations.of(context)?.translate('profile.upi_id') ?? "UPI ID"}: ${_user!['upi_id'] ?? ""}',
                                              style: GoogleFonts.notoSans(
                                                fontSize: 14,
                                                color: const Color(0xFF1F1F1F),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (qrAmount != null &&
                                                qrAmount!.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                '${AppLocalizations.of(context)?.translate('details.amount') ?? "Amount"}: ₹${double.tryParse(qrAmount!)?.toStringAsFixed(2) ?? qrAmount}',
                                                style: GoogleFonts.notoSans(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        )
                                      else
                                        // Interactive UPI ID line (Copy)
                                        StatefulBuilder(
                                          builder: (context, setInnerState) {
                                            return GestureDetector(
                                              onTap: () async {
                                                final upiId =
                                                    _user!['upi_id']
                                                        ?.toString() ??
                                                    "";
                                                if (upiId.isNotEmpty) {
                                                  await Clipboard.setData(
                                                    ClipboardData(text: upiId),
                                                  );
                                                  setInnerState(
                                                    () => isCopied = true,
                                                  );
                                                  Future.delayed(
                                                    const Duration(seconds: 2),
                                                    () {
                                                      if (mounted) {
                                                        setInnerState(
                                                          () =>
                                                              isCopied = false,
                                                        );
                                                      }
                                                    },
                                                  );
                                                }
                                              },
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '${AppLocalizations.of(context)?.translate('profile.upi_id') ?? "UPI ID"}: ${_user!['upi_id'] ?? ""}${qrAmount != null && qrAmount!.isNotEmpty ? ' | ₹ $qrAmount' : ''}',
                                                      style: GoogleFonts.notoSans(
                                                        fontSize: 14,
                                                        color: const Color(
                                                          0xFF1F1F1F,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),

                                                  const SizedBox(width: 8),
                                                  Icon(
                                                    isCopied
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons.copy_rounded,
                                                    size: 16,
                                                    color: isCopied
                                                        ? Colors.green
                                                        : Colors.grey.shade600,
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const SizedBox(height: 16),

                              // Removed duplicate blocks
                            ],
                          ),
                        ),
                      ),

                      const Spacer(flex: 2),

                      // Actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _handleScanFromProfile(context),
                                icon: const Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.translate('profile.open_scanner') ??
                                      'Open scanner',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  foregroundColor: primaryTextColor,
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  textStyle: GoogleFonts.notoSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _shareQrCodeWithCapture(setModalState),
                                icon: const Icon(Icons.share_rounded, size: 20),
                                label: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.translate('profile.share_qr') ??
                                      'Share QR code',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF6C2BD9,
                                  ), // Purple Brand Color
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  textStyle: GoogleFonts.notoSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Powered By Footer
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('details.powered_by') ??
                                  "Powered by ZaferPay",
                              style: GoogleFonts.notoSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _captureQrAndPerformAction(
    StateSetter setModalState,
    Future<void> Function(Uint8List byteData) action,
  ) async {
    // Hide Interactive Elements & Bank Info
    setModalState(() => isCapturingQr = true);

    // Give the UI a brief moment to rebuild and hide the elements
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          await action(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          );
        }
      }
    } finally {
      // Always restore UI immediately
      if (mounted) {
        setModalState(() => isCapturingQr = false);
      }
    }
  }

  Future<void> _shareQrCodeWithCapture(StateSetter setModalState) async {
    if (_user == null) return;

    final upiId = _user!['upi_id']?.toString() ?? "";
    final name = _user!['username']?.toString() ?? "";
    final mcc = _user!['mcc']?.toString() ?? '0000';

    String link = "upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}";
    if (MccHelper.isMerchant(mcc)) {
      link += "&mc=$mcc&mode=02&purpose=00";
    } else {
      link += "&mode=00";
    }

    final shareText = "Use my UPI ID to pay me: $upiId\n\nLink: $link";

    MyApp.isSharing = true;
    try {
      await _captureQrAndPerformAction(setModalState, (byteData) async {
        final tempDir = await getTemporaryDirectory();
        final filePath =
            '${tempDir.path}/my_qr_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(byteData);

        // ignore: deprecated_member_use
        await fp.Share.shareXFiles([fp.XFile(file.path)], text: shareText);
      });
    } catch (e) {
      debugPrint("Error sharing QR: $e");
    } finally {
      MyApp.isSharing = false;
    }
  }

  Future<void> _downloadQrCodeWithCapture(StateSetter setModalState) async {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.translate('scan.permission_denied') ??
                  'Permission denied to save to gallery',
            ),
          ),
        );
        return;
      }
    }

    await _captureQrAndPerformAction(setModalState, (byteData) async {
      try {
        await Gal.putImageBytes(byteData, album: 'ZaferPay');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)?.translate('profile.qr_saved') ??
                    'QR Code saved to Gallery',
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error saving QR: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)?.translate('common.save_failed') ??
                    'Failed to save QR code',
              ),
            ),
          );
        }
      }
    });
  }
}
