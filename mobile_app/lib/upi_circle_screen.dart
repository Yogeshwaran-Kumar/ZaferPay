import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'widgets/select_member_screen.dart';
import 'package:flutter/services.dart'; // For HapticFeedback

class UPICircleScreen extends StatefulWidget {
  const UPICircleScreen({super.key});

  @override
  State<UPICircleScreen> createState() => _UPICircleScreenState();
}

class _UPICircleScreenState extends State<UPICircleScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _myCircles = [];
  List<dynamic> _joinedCircles = [];
  bool _isChild = false;

  @override
  void initState() {
    super.initState();
    _checkIfChild();
    _loadCircleData();
  }

  void _checkIfChild() {
    final homeData = _apiService.getCachedHomeDataSync();
    if (homeData != null && homeData['user'] != null) {
      final user = homeData['user'];
      _isChild = user['bank_name'] == null;
    }
  }

  Future<void> _loadCircleData() async {
    setState(() => _isLoading = true);
    final data = await _apiService.getCircleStatus();
    setState(() {
      _myCircles = data['my_circles'] ?? [];
      _joinedCircles = data['joined_circles'] ?? [];
      _isLoading = false;
    });
  }

  Future<void> _showInviteDialog() async {
    // 1. Step 1: Select Member using the new screen
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (context) => const SelectMemberScreen()),
    );

    if (result == null || !mounted) return;

    final selectedUpi = result['upi']!;
    final selectedName = result['name']!;

    // 2. Step 2: Show settings dialog for the selected member
    final limitController = TextEditingController(text: "5000");
    String delegationType = "FULL";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              const Text("Circle Settings"),
              const SizedBox(height: 8),
              Text(
                "Inviting $selectedName",
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.blue,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: limitController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Monthly Limit (₹)",
                    prefixText: "₹ ",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Delegation Mode",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: RadioGroup<String>(
                    groupValue: delegationType,
                    onChanged: (v) => setDialogState(() => delegationType = v!),
                    child: Column(
                      children: [
                        RadioListTile<String>.adaptive(
                          title: const Text(
                            "Full (Auto-pay)",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            "Member spends directly within limits",
                          ),
                          value: "FULL",
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>.adaptive(
                          title: const Text(
                            "Partial (Approve)",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text("You approve every payment"),
                          value: "PARTIAL",
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final limit = double.tryParse(limitController.text) ?? 5000.0;

                // Show loading on button
                HapticFeedback.mediumImpact();

                final result = await _apiService.inviteToCircle(
                  selectedUpi,
                  limit,
                  delegationType,
                );

                final bool success = result['success'] ?? false;
                final String message =
                    result['message'] ??
                    (success
                        ? "Invitation Sent!"
                        : "Failed to send invitation");

                if (context.mounted) {
                  Navigator.pop(context); // Close invite dialog

                  if (!success) {
                    // Show premium "alate" (alert) as requested
                    _showPremiumAlert(context, "Action Restricted", message);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 12),
                            Text("Invitation Sent to $selectedName!"),
                          ],
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadCircleData();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Send Invitation"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("UPI Circle"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCircleData,
          ),
        ],
      ),
      floatingActionButton: _isChild
          ? null
          : FloatingActionButton.extended(
              onPressed: _showInviteDialog,
              icon: const Icon(Icons.person_add),
              label: const Text("Add Member"),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCircleData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader("Members in My Circle", Icons.group),
                  if (_myCircles.isEmpty)
                    _buildEmptyState("You haven't added anyone yet.")
                  else
                    ..._myCircles.map(
                      (c) => _buildCircleItem(c, isPrimary: true),
                    ),

                  const SizedBox(height: 24),

                  _buildHeader("Circles I've Joined", Icons.verified_user),
                  if (_joinedCircles.isEmpty)
                    _buildEmptyState(
                      "You are not a member of any other circles.",
                    )
                  else
                    ..._joinedCircles.map(
                      (c) => _buildCircleItem(c, isPrimary: false),
                    ),

                  const SizedBox(height: 80), // Space for FAB
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(msg, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }

  Widget _buildCircleItem(dynamic circle, {required bool isPrimary}) {
    final name = isPrimary
        ? circle['secondary_user_name'] as String
        : circle['primary_user_name'] as String;
    final upi = isPrimary
        ? circle['secondary_user_upi'] as String
        : circle['primary_user_upi'] as String;
    final limit = (circle['monthly_limit'] ?? 0.0).toDouble();
    final spend = (circle['current_monthly_spend'] ?? 0.0).toDouble();
    final progress = limit > 0 ? (spend / limit).clamp(0.0, 1.0) : 0.0;
    final status = circle['status'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withValues(alpha: 0.1),
          radius: 24,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              upi,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (status == 'ACTIVE')
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade100,
                  minHeight: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress > 0.9 ? Colors.red : Colors.blue,
                  ),
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStatusBadge(status),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
        onTap: () {
          if (status == 'ACTIVE') {
            _showMemberSummary(circle, isPrimary);
          } else if (!isPrimary && status == 'PENDING') {
            // Handle pending invite for child
            _showRespondDialog(circle);
          }
        },
      ),
    );
  }

  void _showRespondDialog(dynamic circle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Circle Invitation"),
        content: Text(
          "Do you want to join ${circle['primary_user_name']}'s UPI Circle?",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToInvite(circle['id'], 'REJECT');
            },
            child: const Text("Reject", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToInvite(circle['id'], 'ACCEPT');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }

  void _showMemberSummary(dynamic circle, bool isPrimary) {
    final name = isPrimary
        ? circle['secondary_user_name']
        : circle['primary_user_name'];
    final limit = (circle['monthly_limit'] ?? 0.0).toDouble();
    final spend = (circle['current_monthly_spend'] ?? 0.0).toDouble();
    final remaining = limit - spend;
    final progress = limit > 0 ? (spend / limit).clamp(0.0, 1.0) : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height:
            MediaQuery.of(context).size.height * 0.75, // Slightly more height
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    isPrimary
                                        ? "Child's Spending Summary"
                                        : "My Spending Summary",
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _loadCircleData();
                              },
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.blue,
                              ),
                              tooltip: "Refresh Data",
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 180,
                              height: 180,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 12,
                                backgroundColor: Colors.grey[100],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  progress > 0.9 ? Colors.red : Colors.blue,
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  "₹${spend.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  "Spent",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        _buildSummaryRowWithAction(
                          "Monthly Limit",
                          "₹${limit.toStringAsFixed(0)}",
                          Colors.black,
                          onEdit: () {
                            Navigator.pop(context);
                            _showEditLimitDialog(circle);
                          },
                        ),
                        const Divider(height: 24),
                        _buildSummaryRow(
                          "Remaining",
                          "₹${remaining.toStringAsFixed(0)}",
                          Colors.green,
                        ),
                        const Divider(height: 24),
                        _buildSummaryRow(
                          "Status",
                          circle['status'],
                          circle['status'] == 'ACTIVE'
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (isPrimary && circle['status'] != 'REVOKED') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close details bottom sheet
                        _confirmRemoveMember(circle);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Remove Member",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Close",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditLimitDialog(dynamic circle) {
    final controller = TextEditingController(
      text: circle['monthly_limit'].toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Change Limit for ${circle['secondary_user_name']}"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "New Monthly Limit (₹)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newLimit = double.tryParse(controller.text);
              if (newLimit == null || newLimit <= 0) return;

              final success = await _apiService.updateCircleLimit(
                circle['id'],
                newLimit,
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? "Limit Updated!" : "Failed to update limit",
                    ),
                  ),
                );
                _loadCircleData();
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveMember(dynamic circle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Member"),
        content: Text(
          "Are you sure you want to remove ${circle['secondary_user_name']} from your UPI Circle? They will immediately lose access to spend from your account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await _apiService.removeCircleMember(
                circle['id'],
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? "Member removed successfully!"
                          : "Failed to remove member.",
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) {
                  _loadCircleData();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRowWithAction(
    String label,
    String value,
    Color valueColor, {
    required VoidCallback onEdit,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    if (status == 'ACTIVE') color = Colors.green;
    if (status == 'PENDING') color = Colors.orange;
    if (status == 'REVOKED') color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _respondToInvite(int id, String action) async {
    final success = await _apiService.respondToCircleInvite(id, action);
    if (success) {
      _loadCircleData();
    }
  }

  void _showPremiumAlert(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Colors.blue,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.outfit(fontSize: 16, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                "Understood",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
