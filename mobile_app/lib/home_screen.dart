import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'mcc_helper.dart';
import 'contacts_screen.dart';

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
    super.dispose();
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
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: () => _loadData(showLoading: false),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // 1. Large Scan QR Button (Top)
                GestureDetector(
                  onTap: () async {
                    final scanResult = await Navigator.pushNamed(
                      context,
                      '/scan',
                    );
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

                      final myUpi = _user?['upi_id'];
                      if (myUpi != null && myUpi == scannedUpi) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cannot send money to self'),
                          ),
                        );
                        return;
                      }

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

                      if (payResult != null &&
                          payResult is Map<String, dynamic>) {
                        setState(() {
                          _history.insert(0, payResult);
                          if (_user != null) {
                            _user!['balance'] -= payResult['amount'];
                          }
                        });
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFE3F2FD),
                          const Color(0xFFF3E5F5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.blue.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.1),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            size: 48,
                            color: Color(0xFF00B9F1),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Scan any QR Code',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00B9F1),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pay to any UPI app',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // 2. Search Bar Section
                Text(
                  'Or pay to contact',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade100,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _upiController,
                          decoration: InputDecoration(
                            hintText: 'Pay by name or phone number',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendPayment(),
                        ),
                      ),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF00B9F1),
                        child: Text(
                          _user!['username'][0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // 3. Quick Actions
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildQuickActionItem(
                      icon: Icons.phone_android,
                      label: 'Recharge',
                      color: Colors.blue.shade600,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coming soon!')),
                        );
                      },
                    ),
                    _buildQuickActionItem(
                      icon: Icons.lightbulb_outline,
                      label: 'Electricity',
                      color: Colors.orange.shade600,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coming soon!')),
                        );
                      },
                    ),
                    _buildQuickActionItem(
                      icon: Icons.tv,
                      label: 'DTH',
                      color: Colors.purple.shade600,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coming soon!')),
                        );
                      },
                    ),
                    _buildQuickActionItem(
                      icon: Icons.receipt_long,
                      label: 'Bills',
                      color: Colors.green.shade600,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coming soon!')),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // 4. People Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'People',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ContactsScreen(),
                          ),
                        );
                        if (result != null && result is Map) {
                          final upi = result['upi'];
                          final name = result['name'];
                          if (!mounted) return;
                          Navigator.pushNamed(
                            context,
                            '/pay',
                            arguments: {'upi': upi, 'name': name},
                          );
                        }
                      },
                      child: const Text('View all'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // Contact selector
                      _buildPersonAvatar(
                        icon: Icons.person_add,
                        label: 'Select\nContact',
                        color: Colors.grey.shade300,
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ContactsScreen(),
                            ),
                          );
                          if (result != null && result is Map) {
                            final upi = result['upi'];
                            final name = result['name'];
                            if (!mounted) return;
                            Navigator.pushNamed(
                              context,
                              '/pay',
                              arguments: {'upi': upi, 'name': name},
                            );
                          }
                        },
                      ),
                      // Recent contacts from history
                      ..._getRecentContacts().map(
                        (contact) => _buildPersonAvatar(
                          label: contact['name'] ?? 'Unknown',
                          color: _getColorFromName(
                            contact['name'] ?? 'Unknown',
                          ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/pay',
                              arguments: {
                                'upi': contact['upi'],
                                'name': contact['name'],
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // See Your Transactions Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Navigate to money tab via logic or just show message
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Go to Money tab for transactions'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('See Your Transactions'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00B9F1), // Blue
                      side: const BorderSide(color: Color(0xFF00B9F1)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 80), // Bottom padding
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Local helper for quick actions circles
  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // Helper widget builders

  Widget _buildPersonAvatar({
    IconData? icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color,
              child: icon != null
                  ? Icon(icon, color: Colors.white)
                  : Text(
                      label.isNotEmpty ? label[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _getRecentContacts() {
    // Get unique contacts from history
    final Set<String> seenUpi = {};
    final List<Map<String, String>> contacts = [];

    for (var tx in _history) {
      final myUpi = _user?['upi_id'];
      final bool isDebit = tx['sender_upi_id'] == myUpi;
      final String otherUpi = isDebit
          ? tx['receiver_upi_id']
          : tx['sender_upi_id'];

      if (!seenUpi.contains(otherUpi) && contacts.length < 10) {
        seenUpi.add(otherUpi);
        contacts.add({
          'upi': otherUpi,
          'name': otherUpi.split('@')[0], // Extract name from UPI
        });
      }
    }

    return contacts;
  }

  Color _getColorFromName(String name) {
    // Generate a color based on the name's hash code
    final hash = name.hashCode;
    final colors = [
      const Color(0xFF5F259F),
      const Color(0xFFE91E63),
      const Color(0xFF00BCD4),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFF3F51B5),
      const Color(0xFF009688),
    ];
    return colors[hash % colors.length];
  }
}
