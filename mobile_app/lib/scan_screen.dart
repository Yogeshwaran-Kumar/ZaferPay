import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _found = false;

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
            // Fallback to raw string if parsing fails
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
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
