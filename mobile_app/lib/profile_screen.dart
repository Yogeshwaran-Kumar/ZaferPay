import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as fp;
import 'api_service.dart';
import 'mcc_helper.dart';
import 'main.dart';
import 'utils.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ProfileScreen({super.key, this.onBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  final GlobalKey _qrKey = GlobalKey(); // Add GlobalKey

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    // 1. Try to load from cache immediately
    final cachedUser = await _api.getCachedMe();
    if (cachedUser != null && mounted) {
      setState(() {
        _user = cachedUser;
        _isLoading = false;
      });
    }

    // 2. Fetch fresh data from network in background
    try {
      final user = await _api.getMe();
      if (mounted && user != null) {
        setState(() {
          _user = user;
          _isLoading = false;
        });
      } else if (mounted && _user == null) {
        // Only set error if we have no data at all
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted && _user == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('Failed to load profile')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        actions: [],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // User Avatar and Name
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: getAvatarColor(_user!['username']),
                      child: Text(
                        _user!['username'][0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _user!['username'],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // QR Code
                    // Wrapped in RepaintBoundary for sharing capture
                    RepaintBoundary(
                      key: _qrKey,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data:
                              'upi://pay?pa=${_user!['upi_id']}&pn=${Uri.encodeComponent(_user!['username'])}&mc=${_user!['mcc'] ?? ""}',
                          version: QrVersions.auto,
                          size: 250.0,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Scan to pay text
                    Text(
                      'Scan to pay with any UPI app',
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Account Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: MccHelper.isMerchant(_user!['mcc'])
                            ? Colors.orange.shade700
                            : Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            MccHelper.isMerchant(_user!['mcc'])
                                ? Icons.store
                                : Icons.person,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            MccHelper.isMerchant(_user!['mcc'])
                                ? 'Merchant Account'
                                : 'Personal Account',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // UPI ID
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'UPI ID: ${_user!['upi_id']}',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.copy,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.black54,
                            size: 16,
                          ),
                          onPressed: () {
                            // Copy to clipboard logic would go here
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('UPI ID copied!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom buttons
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : Colors.grey.shade200,
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Simple navigate for scanner
                        Navigator.pushNamed(context, '/scan');
                      },
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text('Open scanner'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.color,
                        side: BorderSide(
                          color: isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade400,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareQrCode,
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('Share QR code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF673AB7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareQrCode() async {
    if (_user == null) return;

    final upiId = _user!['upi_id'];
    final name = _user!['username'];
    final mcc = _user!['mcc'] ?? '0000';

    String link = "upi://pay?pa=$upiId&pn=$name";
    if (MccHelper.isMerchant(mcc)) {
      link += "&mc=$mcc&mode=02&purpose=00";
    } else {
      link += "&mode=00";
    }

    final shareText = "Use my UPI ID to pay me: $upiId\n\nLink: $link";

    File? fileToShare;

    try {
      // Capture QR image from the widget
      RenderRepaintBoundary boundary =
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();

        // Save to temporary file
        final tempDir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = '${tempDir.path}/my_qr_$ts.png';
        final file = File(path);
        await file.writeAsBytes(pngBytes);
        fileToShare = file;
      }
    } catch (e) {
      debugPrint("Error capturing QR: $e");
    }

    // Share logic
    MyApp.isSharing = true;
    try {
      if (fileToShare != null) {
        // ignore: deprecated_member_use
        await fp.Share.shareXFiles(
          [fp.XFile(fileToShare.path)],
          text: shareText,
          subject: "Payment QR Code",
        );
      } else {
        // ignore: deprecated_member_use
        await fp.Share.share(shareText);
      }
    } catch (e) {
      debugPrint("Error sharing: $e");
      // Fallback to text if file share failed
      if (fileToShare != null) {
        try {
          // ignore: deprecated_member_use
          await fp.Share.share(shareText);
        } catch (_) {}
      }
    } finally {
      MyApp.isSharing = false;
      MyApp.lastShareTime = DateTime.now();
    }
  }
}
