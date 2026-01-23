import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'mcc_helper.dart';

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
  Timer? _timer;
  bool _isSelfTransfer = false; // Track if entered UPI is user's own

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

    // Listen for UPI input changes to check self-transfer
    _upiController.addListener(_checkSelfTransfer);

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
    _upiController.removeListener(_checkSelfTransfer);
    _upiController.dispose();
    super.dispose();
  }

  void _checkSelfTransfer() {
    final enteredUpi = _upiController.text.trim();
    final myUpi = _user?['upi_id'];
    setState(() {
      _isSelfTransfer =
          myUpi != null && myUpi == enteredUpi && enteredUpi.isNotEmpty;
    });
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    final user = await _api.getMe();
    final history = await _api.getHistory();
    setState(() {
      if (user != null) {
        _user = user;
      }
      if (history != null) {
        _history = history;
      }
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
                child: QrImageView(
                  data:
                      'upi://pay?pa=${_user!['upi_id']}&pn=${Uri.encodeComponent(_user!['username'])}&mc=${_user!['mcc'] ?? ""}',
                ),
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

  void _sendPayment() {
    final upiId = _upiController.text.trim();

    if (upiId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please enter a UPI ID')));
      }
      return;
    }

    // Check for self-transfer
    final myUpi = _user?['upi_id'];
    if (myUpi != null && myUpi == upiId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot send money to self')),
        );
      }
      return;
    }

    // Navigate to PayScreen with pre-filled UPI
    Navigator.pushNamed(context, '/pay', arguments: {'upi': upiId});
    _upiController.clear();
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6200EE), Color(0xFF3700B3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6200EE).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Available Balance',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(
                          Icons.account_balance_wallet,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '₹ ${_user!['balance'].toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.qr_code,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _user!['upi_id'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // UPI Payment Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _upiController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient UPI ID',
                          hintText: 'e.g., user@bank',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSelfTransfer ? null : _sendPayment,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor:
                                Colors.black, // Dark button for proceed
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey,
                            disabledForegroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _isSelfTransfer ? 'Cannot send to self' : 'Proceed',
                          ),
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
                    Color color;
                    IconData icon;

                    if (tx['status'] == 'BLOCKED') {
                      color = Colors.grey;
                      icon = Icons.block;
                    } else if (tx['status'] == 'FAILED') {
                      color = Colors.red;
                      icon = Icons.error_outline;
                    } else {
                      color = isDebit ? Colors.red : Colors.green;
                      icon = isDebit
                          ? Icons.arrow_outward
                          : Icons.arrow_downward;
                    }

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
        onPressed: () async {
          final scanResult = await Navigator.pushNamed(context, '/scan');
          if (scanResult != null) {
            String scannedUpi = "";
            String? scannedMcc;
            String? scannedName;

            if (scanResult is Map) {
              scannedUpi = scanResult['upi'];
              scannedMcc = scanResult['mcc'];
              scannedName = scanResult['name'];
            } else if (scanResult is String) {
              scannedUpi = scanResult;
            }

            // Check for self-transfer
            final myUpi = _user?['upi_id'];
            if (myUpi != null && myUpi == scannedUpi) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cannot send money to self')),
              );
              return;
            }

            // Show MCC if present

            // Found UPI ID, proceed to Pay
            if (!mounted) return;

            String? category;
            if (scannedMcc != null && scannedMcc.isNotEmpty) {
              category = MccHelper.getDomain(scannedMcc);
            }

            if (!mounted) return;
            final nav = Navigator.of(context);

            final payResult = await nav.pushNamed(
              '/pay',
              arguments: {
                'upi': scannedUpi,
                'name': scannedName,
                'category': category,
              },
            );

            if (payResult != null && payResult is Map<String, dynamic>) {
              setState(() {
                _history.insert(0, payResult);
                if (_user != null) {
                  _user!['balance'] -= payResult['amount'];
                }
              });
            }
          } else {
            // Refresh if came back empty
            if (mounted) _loadData(showLoading: false);
          }
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
