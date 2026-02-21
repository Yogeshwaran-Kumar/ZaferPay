import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobile_app/main.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'package:light_sensor/light_sensor.dart';
import 'dart:async';
import 'mcc_helper.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _found = false;
  bool _isScanning = true; // Toggle between Camera and My QR (UI only)
  MobileScannerController cameraController = MobileScannerController();
  Map<String, dynamic>? _user;
  final GlobalKey _qrKey = GlobalKey();

  // Low light detection
  StreamSubscription? _subscription;
  int _currentLux = 100; // Default to bright
  bool get _isLowLight => _currentLux < 15;

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
    _initLightSensor();
  }

  void _initLightSensor() {
    try {
      _subscription = LightSensor.luxStream().listen((lux) {
        if (mounted) {
          setState(() {
            _currentLux = lux.toInt();
          });
        }
      });
    } catch (e) {
      debugPrint("Light sensor not available: $e");
    }
  }

  PermissionStatus? _permissionStatus;

  Future<void> _checkPermission() async {
    // Request permission explicitly on load
    MyApp.isRequestingPermission = true;
    try {
      final status = await Permission.camera.request();
      setState(() {
        _permissionStatus = status;
      });
    } finally {
      MyApp.isRequestingPermission = false;
      MyApp.lastPermissionRequestTime = DateTime.now();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
        try {
          // ignore: deprecated_member_use
          await Share.shareXFiles([
            XFile(path),
          ], text: 'Use my UPI ID to pay me: $upiId\n\nLink: $upiUri');
        } finally {
          MyApp.isSharing = false;
          MyApp.lastShareTime = DateTime.now();
        }
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

  Future<void> _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 50)); // Small UX delay

      String? result;
      // Use Google ML Kit directly for robust file analysis
      final inputImage = mlkit.InputImage.fromFilePath(image.path);
      final scanner = mlkit.BarcodeScanner(
        formats: [mlkit.BarcodeFormat.qrCode],
      );

      try {
        final barcodes = await scanner.processImage(inputImage);
        for (final barcode in barcodes) {
          if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
            result = barcode.rawValue;
            break;
          }
        }
      } catch (e) {
        debugPrint("ML Kit Error: $e");
      } finally {
        await scanner.close();
      }

      // Dismiss loading
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Pop Dialog
      }

      if (result != null && result.isNotEmpty) {
        _handleScanResult(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No Valid QR code found. Please ensure the image contains a clear QR code.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error reading image: $e')));
      }
    }
  }

  void _handleScanResult(String raw) {
    if (_found) return; // Prevent duplicates
    setState(() => _found = true);

    // Tag the result so downstream screens know this came from a QR scan.
    // This is forwarded to the backend as payment_source='qr_scan' for F57/F58 rules.
    Map<String, String> result = {'upi': raw, 'payment_source': 'qr_scan'};

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
  }

  void _onDetect(BarcodeCapture capture) {
    if (_found || !_isScanning) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _handleScanResult(barcode.rawValue!);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionStatus == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_permissionStatus != PermissionStatus.granted) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                "Camera permission denied",
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checkPermission,
                child: const Text("Grant Permission"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Stack ensures ScannerView (and its Controller) stays mounted/active
      body: Stack(
        children: [
          _buildScannerView(), // Always active in background
          if (!_isScanning)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _buildMyQrView(),
            ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(controller: cameraController, onDetect: _onDetect),

        // Custom Overlay
        CustomPaint(painter: ScannerOverlayPainter(), child: Container()),

        // Low Light Guidance
        if (_isLowLight && _isScanning)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: const Color(0xFF00B9F1).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.flash_on, color: Colors.yellow, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Low light detected. Try using flashlight.",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

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
                      // Try to turn off torch if it was on
                      cameraController.toggleTorch();
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
                  onPressed: _pickImageFromGallery,
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
    final mcc = _user?['mcc'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Construct UPI URI with conditional MCC for Personal vs Merchant
    String upiUri = 'upi://pay?pa=$upiId&pn=$name';
    if (MccHelper.isMerchant(mcc)) {
      // Merchant QR: Include MCC and specific mode
      upiUri += '&mc=$mcc&mode=02&purpose=00';
    } else {
      // Personal QR: Omit MCC, use basic mode if needed
      upiUri += '&mode=00';
    }

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

              // Merchant Account Badge
              if (MccHelper.isMerchant(mcc)) ...[
                const SizedBox(height: 16),
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
                    children: const [
                      Icon(Icons.store, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Merchant Account',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
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
                            ? const Color(0xFF00B9F1).withValues(alpha: 0.5)
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
    final double radius = 24.0; // Rounded corners

    // Draw dark overlay with rounded cutout
    final Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, bottom),
          Radius.circular(radius),
        ),
      );

    path.fillType = PathFillType.evenOdd;

    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, overlayPaint);

    // Corner Configuration
    final double cornerLength = 40;
    final Paint cornerPaint = Paint()
      ..color =
          const Color(0xFF00B9F1) // App Blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw Rounded Corners

    // Top-Left
    final Path tlPath = Path();
    tlPath.moveTo(left, top + cornerLength);
    tlPath.lineTo(left, top + radius);
    tlPath.arcToPoint(
      Offset(left + radius, top),
      radius: Radius.circular(radius),
      clockwise: true,
    );
    tlPath.lineTo(left + cornerLength, top);
    canvas.drawPath(tlPath, cornerPaint);

    // Top-Right
    final Path trPath = Path();
    trPath.moveTo(right - cornerLength, top);
    trPath.lineTo(right - radius, top);
    trPath.arcToPoint(
      Offset(right, top + radius),
      radius: Radius.circular(radius),
      clockwise: true,
    );
    trPath.lineTo(right, top + cornerLength);
    canvas.drawPath(trPath, cornerPaint);

    // Bottom-Right
    final Path brPath = Path();
    brPath.moveTo(right, bottom - cornerLength);
    brPath.lineTo(right, bottom - radius);
    brPath.arcToPoint(
      Offset(right - radius, bottom),
      radius: Radius.circular(radius),
      clockwise: true,
    );
    brPath.lineTo(right - cornerLength, bottom);
    canvas.drawPath(brPath, cornerPaint);

    // Bottom-Left
    final Path blPath = Path();
    blPath.moveTo(left + cornerLength, bottom);
    blPath.lineTo(left + radius, bottom);
    blPath.arcToPoint(
      Offset(left, bottom - radius),
      radius: Radius.circular(radius),
      clockwise: true,
    );
    blPath.lineTo(left, bottom - cornerLength);
    canvas.drawPath(blPath, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
