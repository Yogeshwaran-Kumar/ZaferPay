import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _found = false;
  MobileScannerController cameraController = MobileScannerController();

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_found) return;
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
            if (params.containsKey('pa')) {
              result['upi'] = params['pa']!;
            }
            if (params.containsKey('mc')) {
              result['mcc'] = params['mc']!;
            }
            if (params.containsKey('pn')) {
              result['name'] = params['pn']!;
            }
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              cameraController.torchEnabled ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera Scanner
          MobileScanner(controller: cameraController, onDetect: _onDetect),

          // Overlay with colored corners
          CustomPaint(painter: ScannerOverlayPainter(), child: Container()),

          // Bottom section
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
                    Colors.black.withOpacity(0.8),
                    Colors.black,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      // Open gallery to select QR code image
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
      ..color = Colors.black.withOpacity(0.5)
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
    final colors = [
      Colors.red, // Top-left
      Colors.orange, // Top-right
      Colors.blue, // Bottom-left
      Colors.green, // Bottom-right
    ];

    // Draw colored corners
    // Top-left (Red)
    canvas.drawPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(left + cornerLength, top)
        ..lineTo(left + cornerLength, top + cornerThickness)
        ..lineTo(left + cornerThickness, top + cornerThickness)
        ..lineTo(left + cornerThickness, top + cornerLength)
        ..lineTo(left, top + cornerLength)
        ..close(),
      Paint()..color = colors[0],
    );

    // Top-right (Orange)
    canvas.drawPath(
      Path()
        ..moveTo(right, top)
        ..lineTo(right - cornerLength, top)
        ..lineTo(right - cornerLength, top + cornerThickness)
        ..lineTo(right - cornerThickness, top + cornerThickness)
        ..lineTo(right - cornerThickness, top + cornerLength)
        ..lineTo(right, top + cornerLength)
        ..close(),
      Paint()..color = colors[1],
    );

    // Bottom-left (Blue)
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom)
        ..lineTo(left + cornerLength, bottom)
        ..lineTo(left + cornerLength, bottom - cornerThickness)
        ..lineTo(left + cornerThickness, bottom - cornerThickness)
        ..lineTo(left + cornerThickness, bottom - cornerLength)
        ..lineTo(left, bottom - cornerLength)
        ..close(),
      Paint()..color = colors[2],
    );

    // Bottom-right (Green)
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom)
        ..lineTo(right - cornerLength, bottom)
        ..lineTo(right - cornerLength, bottom - cornerThickness)
        ..lineTo(right - cornerThickness, bottom - cornerThickness)
        ..lineTo(right - cornerThickness, bottom - cornerLength)
        ..lineTo(right, bottom - cornerLength)
        ..close(),
      Paint()..color = colors[3],
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
