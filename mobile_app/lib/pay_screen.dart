import 'package:flutter/material.dart';
import 'api_service.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  late String _receiverUpi;
  String? _receiverName;
  final ApiService _api = ApiService();
  final _amountController = TextEditingController();
  bool _isLoadingName = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _receiverUpi = args?['upi'] ?? '';
    if (_isLoadingName) {
      _fetchReceiverName();
    }
  }

  Future<void> _fetchReceiverName() async {
    final info = await _api.lookupUser(_receiverUpi);
    if (mounted) {
      setState(() {
        if (info != null) {
          _receiverName = info['username'];
        }
        _isLoadingName = false;
      });
    }
  }

  Future<void> _onPayPressed() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid amount")));
      return;
    }

    final result = await Navigator.pushNamed(
      context,
      '/payment-pin',
      arguments: {'receiverUpi': _receiverUpi, 'amount': amount},
    );

    if (result != null && result is Map<String, dynamic>) {
      if (mounted) {
        _showResultDialog(result);
      }
    }
  }

  void _showResultDialog(Map<String, dynamic> result) {
    if (result.containsKey('detail')) {
      // Error from backend
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['detail'])));
      return;
    }

    final status = result['status'];
    final risk = result['risk_score'];

    // Determine color and icon
    Color color = Colors.green;
    IconData icon = Icons.check_circle;
    String title = "Payment Successful";

    if (status == "BLOCKED") {
      color = Colors.red;
      icon = Icons.block;
      title = "Transaction Blocked";
    } else if (status == "FAILED") {
      color = Colors.red;
      icon = Icons.error_outline;
      title = "Insufficient Balance";
    } else if (risk == "WARN") {
      color = Colors.orange;
      icon = Icons.warning;
      title = "Warning Detected";
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            Icon(icon, size: 60, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Amount: ₹${result['amount']}"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Risk Level:"),
                      Text(
                        risk,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text("Status:"), Text(status)],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context); // Close Dialog
              Navigator.pop(context, result); // Go back to Home with result
            },
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Make Payment")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey.shade200,
              child: Text(
                _receiverName != null && _receiverName!.isNotEmpty
                    ? _receiverName![0].toUpperCase()
                    : (_receiverUpi.isNotEmpty
                          ? _receiverUpi[0].toUpperCase()
                          : '?'),
                style: const TextStyle(fontSize: 32),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Paying to", style: TextStyle(color: Colors.grey)),
            Text(
              _receiverName ?? _receiverUpi,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_receiverName != null)
              Text(
                _receiverUpi,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            const SizedBox(height: 40),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                prefixText: "₹ ",
                hintText: "0",
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _onPayPressed,
              icon: const Icon(Icons.send),
              label: const Text("Pay Now"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
