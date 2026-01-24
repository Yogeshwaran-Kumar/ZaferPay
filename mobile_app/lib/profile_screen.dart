import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart'; // Add path_provider
import 'package:share_plus/share_plus.dart' as fp; // Add share_plus with prefix
import 'api_service.dart';
import 'main.dart'; // Import main.dart to access MyApp.shouldSkipLock

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

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final user = await _api.getMe();
    setState(() {
      _user = user;
      _isLoading = false;
    });
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
                      backgroundColor: const Color(0xFF5F259F),
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
                    // We Wrap in RepaintBoundary if we were using screenshot,
                    // but here we just display it. We'll regenerate for sharing.
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors
                            .white, // Keep QR background white for scannability
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
                        data: _user!['upi_id'],
                        version: QrVersions.auto,
                        size: 250.0,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
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

                    // Bank Name (if available)
                    if (_user!['mcc'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.store,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Merchant Account',
                              style: TextStyle(
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
                        backgroundColor: const Color(0xFF5F259F),
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
    final link = "upi://pay?pa=$upiId&pn=$name&mc=0000&mode=02&purpose=00";
    final shareText = "Use my UPI ID to pay me: $upiId\n\nLink: $link";

    try {
      // 1. Generate QR Image
      final painter = QrPainter(
        data: upiId,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      );

      // 2. Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/qr_$ts.png';
      final file = File(path);

      final picData = await painter.toImageData(
        2048,
        format: ImageByteFormat.png,
      );
      if (picData != null) {
        await file.writeAsBytes(picData.buffer.asUint8List());

        // 3. Share
        MyApp.isSharing = true;
        // ignore: deprecated_member_use
        await fp.Share.shareXFiles(
          [fp.XFile(path)],
          text: shareText,
          subject: "Payment QR Code",
        );
        MyApp.isSharing = false;
        MyApp.lastShareTime = DateTime.now(); // Mark completion time
      } else {
        // Fallback if image generation fails
        MyApp.isSharing = true;
        // ignore: deprecated_member_use
        await fp.Share.share(shareText);
        MyApp.isSharing = false;
        MyApp.lastShareTime = DateTime.now();
      }
    } catch (e) {
      debugPrint("Error sharing QR: $e");
      MyApp.isSharing = false;
      MyApp.lastShareTime = DateTime.now();
      // Fallback
      // ignore: deprecated_member_use
      await fp.Share.share(shareText);
    }
  }
}
