import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _user;
  List<dynamic> _history = [];
  bool _isLoading = true;

  // New fields for UPI payment
  final _upiController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isProcessingPayment = false;
  Timer? _timer;

  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Start polling every 2 seconds
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _loadData(showLoading: false);
      }
    });

    // Listen for forced logout
    _authSubscription = _api.authStateChanges.listen((_) {
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSubscription?.cancel();
    _upiController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    final user = await _api.getMe();
    final history = await _api.getHistory();
    setState(() {
      _user = user;
      _history = history;
      _isLoading = false;
    });
  }

  void _showMyQr() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Center(child: Text("My QR Code")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_user != null)
              SizedBox(
                height: 200,
                width: 200,
                child: QrImageView(data: _user!['upi_id']),
              ),
            const SizedBox(height: 16),
            Text(
              _user?['upi_id'] ?? '',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close"),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPayment() async {
    final upiId = _upiController.text.trim();
    final amountText = _amountController.text.trim();

    if (upiId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please enter a UPI ID')));
      }
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid amount')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isProcessingPayment = true);
    }

    try {
      final result = await _api.createTransaction(upiId, amount);
      if (mounted) {
        if (result.containsKey('detail')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: ${result['detail']}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment sent successfully!')),
          );
          _upiController.clear();
          _amountController.clear();

          // Optimistic Update: Add to history immediately
          setState(() {
            _history.insert(0, result);
            // Optional: Update balance locally if possible, but API fetch will fix it in background
            if (_user != null) {
              _user!['balance'] -= amount;
            }
          });

          // No need to manually call _loadData here, the poller will catch the confirmed state shortly.
          // This prevents a race condition where the rapid fetch might return old data.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return const Scaffold(body: Center(child: Text("Failed to load user")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: TextStyle(fontSize: 14)),
            Text(
              _user!['username'],
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code), onPressed: _showMyQr),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _api.logout();
              if (!mounted) return;
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(showLoading: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance Card
              Card(
                color: Theme.of(context).primaryColor,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Available Balance',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹ ${_user!['balance'].toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'UPI ID: ${_user!['upi_id']}',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // UPI Payment Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Money',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _upiController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient UPI ID',
                          hintText: 'e.g., user@bank',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          labelText: 'Amount (₹)',
                          hintText: '0.00',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessingPayment ? null : _sendPayment,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isProcessingPayment
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Send Payment'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Recent Transactions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (_history.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text("No transactions yet"),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final tx = _history[index];
                    final isDebit = tx['sender_upi_id'] == _user!['upi_id'];
                    final color = tx['status'] == 'BLOCKED'
                        ? Colors.grey
                        : (isDebit ? Colors.red : Colors.green);
                    final icon = tx['status'] == 'BLOCKED'
                        ? Icons.block
                        : (isDebit
                              ? Icons.arrow_outward
                              : Icons.arrow_downward);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.1),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(
                          isDebit
                              ? 'To: ${tx['receiver_upi_id']}'
                              : 'From: ${tx['sender_upi_id']}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx['timestamp']),
                            if (tx['risk_score'] != 'SAFE')
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tx['risk_score'] == 'HIGH'
                                      ? Colors.red.shade100
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Risk: ${tx['risk_score']}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: tx['risk_score'] == 'HIGH'
                                        ? Colors.red
                                        : Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isDebit ? '-' : '+'} ₹${tx['amount']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            Text(
                              tx['status'],
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, '/scan').then((scanResult) {
            if (scanResult != null && scanResult is String) {
              // Found UPI ID, proceed to Pay
              Navigator.pushNamed(
                context,
                '/pay',
                arguments: {'upi': scanResult},
              ).then((payResult) {
                if (payResult != null && payResult is Map<String, dynamic>) {
                  setState(() {
                    _history.insert(0, payResult);
                    if (_user != null) {
                      _user!['balance'] -= payResult['amount'];
                    }
                  });
                }
                // Poller will update eventually
              });
            } else {
              // User came back from scan without scanning (or just refresh)
              _loadData(showLoading: false);
            }
          });
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan & Pay'),
        backgroundColor: Colors.black, // Dark accent
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
