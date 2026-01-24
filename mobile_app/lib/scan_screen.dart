import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart'; // Add permission_handler
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _found = false;
  bool _isScanning = true; // Toggle between Camera and My QR
  MobileScannerController cameraController = MobileScannerController();
  Map<String, dynamic>? _user;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _user = args;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      MyApp.isSharing = true;
      await Permission.camera.request();
      MyApp.isSharing = false;
      MyApp.lastShareTime = DateTime.now();
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _shareQrCode(String upiId, String upiUri) async {
    try {
      // Capture QR image
      RenderRepaintBoundary boundary =
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();

        // Get temp directory
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/my_qr_code.png';
        final file = File(path);
        await file.writeAsBytes(pngBytes);

        // Share the image and text
        MyApp.isSharing = true;
        // ignore: deprecated_member_use
        await Share.shareXFiles([
          XFile(path),
        ], text: 'Use my UPI ID to pay me: $upiId\n\nLink: $upiUri');
        MyApp.isSharing = false;
        MyApp.lastShareTime = DateTime.now();
      }
    } catch (e) {
      debugPrint('Error sharing QR code: $e');
      MyApp.isSharing = false;
      MyApp.lastShareTime = DateTime.now();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share QR code')),
        );
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_found || !_isScanning) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() => _found = true);

        String raw = barcode.rawValue!;
        Map<String, String> result = {'upi': raw};

        if (raw.startsWith('upi://')) {
          try {
            final uri = Uri.parse(raw);
            final params = uri.queryParameters;
            if (params.containsKey('pa')) result['upi'] = params['pa']!;
            if (params.containsKey('mc')) result['mcc'] = params['mc']!;
            if (params.containsKey('pn')) result['name'] = params['pn']!;
          } catch (e) {
            debugPrint("Error parsing URI: $e");
          }
        }

        Navigator.pop(context, result);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isScanning ? _buildScannerView() : _buildMyQrView(),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(controller: cameraController, onDetect: _onDetect),

        // Custom Overlay
        CustomPaint(painter: ScannerOverlayPainter(), child: Container()),

        // Top Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Scan QR Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Torch Icon
                  ValueListenableBuilder(
                    valueListenable: cameraController,
                    builder: (context, state, child) {
                      final isTorchOn = state.torchState == TorchState.on;
                      return IconButton(
                        icon: Icon(
                          isTorchOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                        ),
                        onPressed: () => cameraController.toggleTorch(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom Section
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                  Colors.black,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // QR Icon to switch to My QR (2nd image style)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isScanning = false;
                      // Turn off torch when leaving scanner
                      cameraController
                          .switchCamera(); // workaround or ensure torch off
                      // Ideally just set state, but if torch was on, it might stay on?
                      // cameraController.toggleTorch() if on.
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.qr_code, color: Colors.white),
                        SizedBox(width: 8),
                        Text("My QR", style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Gallery feature coming soon!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Upload from gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Scan any QR code to pay',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Google Pay • PhonePe • PayTM • UPI',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMyQrView() {
    final upiId = _user?['upi_id'] ?? 'user@upi';
    final name = _user?['username'] ?? 'User';
    final mobile = _user?['mobile_number'] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Construct UPI URI
    final upiUri = 'upi://pay?pa=$upiId&pn=$name&mc=0000&mode=02&purpose=00';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Theme.of(context).iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFF00B9F1),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'UPI ID: $upiId',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              if (mobile.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Mobile: $mobile',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // QR Code - Keep white background for readability
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: QrImageView(
                    data: upiUri,
                    version: QrVersions.auto,
                    size: 280,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Open Scanner Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _isScanning = true);
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Open scanner'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : Colors.black,
                        side: BorderSide(
                          color: isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade400,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Share QR Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _shareQrCode(upiId, upiUri);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Share QR code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF5F259F).withValues(alpha: 0.5)
                            : const Color(0xFFE8F0FE),
                        foregroundColor: isDark
                            ? Colors.white
                            : const Color(0xFF1A73E8),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter for colored corner overlay
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scanAreaSize = size.width * 0.7;
    final double left = (size.width - scanAreaSize) / 2;
    final double top = (size.height - scanAreaSize) / 2;
    final double right = left + scanAreaSize;
    final double bottom = top + scanAreaSize;

    // Draw dark overlay
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(Rect.fromLTRB(left, top, right, bottom))
        ..fillType = PathFillType.evenOdd,
      overlayPaint,
    );

    // Corner length and thickness
    final double cornerLength = 40;
    final double cornerThickness = 6;

    // Define corner colors
    final color = const Color(0xFF00B9F1); // Single UI Color (Blue)

    // Draw colored corners
    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(left + cornerLength, top)
        ..lineTo(left + cornerLength, top + cornerThickness)
        ..lineTo(left + cornerThickness, top + cornerThickness)
        ..lineTo(left + cornerThickness, top + cornerLength)
        ..lineTo(left, top + cornerLength)
        ..close(),
      Paint()..color = color,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(right, top)
        ..lineTo(right - cornerLength, top)
        ..lineTo(right - cornerLength, top + cornerThickness)
        ..lineTo(right - cornerThickness, top + cornerThickness)
        ..lineTo(right - cornerThickness, top + cornerLength)
        ..lineTo(right, top + cornerLength)
        ..close(),
      Paint()..color = color,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom)
        ..lineTo(left + cornerLength, bottom)
        ..lineTo(left + cornerLength, bottom - cornerThickness)
        ..lineTo(left + cornerThickness, bottom - cornerThickness)
        ..lineTo(left + cornerThickness, bottom - cornerLength)
        ..lineTo(left, bottom - cornerLength)
        ..close(),
      Paint()..color = color,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom)
        ..lineTo(right - cornerLength, bottom)
        ..lineTo(right - cornerLength, bottom - cornerThickness)
        ..lineTo(right - cornerThickness, bottom - cornerThickness)
        ..lineTo(right - cornerThickness, bottom - cornerLength)
        ..lineTo(right, bottom - cornerLength)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
