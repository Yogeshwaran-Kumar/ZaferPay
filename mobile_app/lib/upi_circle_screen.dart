import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'widgets/select_member_screen.dart';
import 'services/app_localizations.dart';

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
              Text(
                AppLocalizations.of(
                      context,
                    )?.translate('circle.settings_title') ??
                    "Circle Settings",
              ),
              const SizedBox(height: 8),
              Text(
                (AppLocalizations.of(context)?.translate('circle.inviting') ??
                        "Inviting {name}")
                    .replaceAll('{name}', selectedName),
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
                    labelText:
                        AppLocalizations.of(
                          context,
                        )?.translate('circle.monthly_limit') ??
                        "Monthly Limit (₹)",
                    prefixText: "₹ ",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(
                          context,
                        )?.translate('circle.delegation_mode') ??
                        "Delegation Mode",
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
                          title: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.full_auto') ??
                                "Full (Auto-pay)",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.full_desc') ??
                                "Member spends directly within limits",
                          ),
                          value: "FULL",
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>.adaptive(
                          title: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.partial_approve') ??
                                "Partial (Approve)",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.partial_desc') ??
                                "You approve every payment",
                          ),
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
              child: Text(
                AppLocalizations.of(context)?.translate('common.cancel') ??
                    "Cancel",
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final limit = double.tryParse(limitController.text) ?? 5000.0;

                // Navigate to PIN setup screen
                if (!context.mounted) return;

                final pinResult =
                    await Navigator.pushNamed(
                          context,
                          '/upi-circle-setup-pin',
                          arguments: {
                            'secondaryUpi': selectedUpi,
                            'secondaryName': selectedName,
                            'limit': limit,
                            'delegationType': delegationType,
                          },
                        )
                        as Map<String, dynamic>?;

                if (pinResult == null || !context.mounted) return;

                final bool success = pinResult['success'] ?? false;
                final String message = pinResult['message'] ?? "";

                Navigator.pop(context); // Close invite settings dialog

                if (!success && message.isNotEmpty) {
                  _showPremiumAlert(
                    context,
                    AppLocalizations.of(
                          context,
                        )?.translate('circle.action_restricted') ??
                        "Action Restricted",
                    message,
                  );
                } else if (success) {
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
                          Text(
                            (AppLocalizations.of(
                                      context,
                                    )?.translate('circle.invitation_sent') ??
                                    "Invitation Sent to {name}!")
                                .replaceAll("{name}", selectedName),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadCircleData();
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
              child: Text(
                AppLocalizations.of(
                      context,
                    )?.translate('circle.send_invitation') ??
                    "Send Invitation",
              ),
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
        title: Text(
          AppLocalizations.of(context)?.translate('circle.title') ??
              "UPI Circle",
        ),
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
              label: Text(
                AppLocalizations.of(context)?.translate('circle.add_member') ??
                    "Add Member",
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isChild
          ? _buildChildView()
          : RefreshIndicator(
              onRefresh: _loadCircleData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(
                    AppLocalizations.of(
                          context,
                        )?.translate('circle.members_in_circle') ??
                        "Members in My Circle",
                    Icons.group,
                  ),
                  if (_myCircles.isEmpty)
                    _buildEmptyState(
                      AppLocalizations.of(
                            context,
                          )?.translate('circle.added_none') ??
                          "You haven't added anyone yet.",
                    )
                  else
                    ..._myCircles.map(
                      (c) => _buildCircleItem(c, isPrimary: true),
                    ),

                  const SizedBox(height: 24),

                  _buildHeader(
                    AppLocalizations.of(
                          context,
                        )?.translate('circle.circles_joined') ??
                        "Circles I've Joined",
                    Icons.verified_user,
                  ),
                  if (_joinedCircles.isEmpty)
                    _buildEmptyState(
                      AppLocalizations.of(
                            context,
                          )?.translate('circle.member_of_none') ??
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

  Widget _buildChildView() {
    if (_joinedCircles.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCircleData,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.group_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(
                    context,
                  )?.translate('circle.not_part_of_any') ??
                  "You are not part of any UPI Circle yet.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Filter to get active/pending circles (skip revoked ones)
    final activeCircles = _joinedCircles
        .where((c) => c['status'] == 'ACTIVE' || c['status'] == 'PENDING')
        .toList();

    if (activeCircles.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCircleData,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.group_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(
                    context,
                  )?.translate('circle.not_part_of_active') ??
                  "You are not part of any active UPI Circle.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final circle = activeCircles.first;
    final parentName = circle['primary_user_name'] as String;
    final parentUpi = circle['primary_user_upi'] as String;
    final limit = (circle['monthly_limit'] ?? 0.0).toDouble();
    final spend = (circle['current_monthly_spend'] ?? 0.0).toDouble();
    final remaining = limit - spend;
    final progress = limit > 0 ? (spend / limit).clamp(0.0, 1.0) : 0.0;
    final status = circle['status'] as String;
    final delegationType = circle['delegation_type'] as String? ?? 'FULL';

    return RefreshIndicator(
      onRefresh: _loadCircleData,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Parent Info Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      radius: 24,
                      child: Text(
                        parentName.isNotEmpty
                            ? parentName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.my_upi_circle') ??
                                "My UPI Circle",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            parentName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            parentUpi,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // White-themed badge for visibility on blue
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Spending Progress Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                // Circular progress
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
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
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.translate('circle.spent') ??
                              "Spent",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Details rows
                _buildChildDetailRow(
                  AppLocalizations.of(
                        context,
                      )?.translate('circle.limit_label') ??
                      "Monthly Limit",
                  "₹${limit.toStringAsFixed(0)}",
                  Colors.black,
                ),
                const SizedBox(height: 14),
                _buildChildDetailRow(
                  AppLocalizations.of(context)?.translate('circle.remaining') ??
                      "Remaining",
                  "₹${remaining.toStringAsFixed(0)}",
                  remaining > 0 ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 14),
                _buildChildDetailRow(
                  AppLocalizations.of(
                        context,
                      )?.translate('circle.payment_mode') ??
                      "Payment Mode",
                  delegationType == 'FULL'
                      ? (AppLocalizations.of(
                              context,
                            )?.translate('circle.auto_pay') ??
                            "Auto-pay")
                      : (AppLocalizations.of(
                              context,
                            )?.translate('circle.requires_approval') ??
                            "Requires Approval"),
                  delegationType == 'FULL' ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),

          // Pending invites (if any other circles are pending)
          if (_joinedCircles.length > 1) ...[
            const SizedBox(height: 24),
            ...(_joinedCircles
                .skip(1)
                .where((c) => c['status'] == 'PENDING')
                .map((c) => _buildCircleItem(c, isPrimary: false))),
          ],
        ],
      ),
    );
  }

  Widget _buildChildDetailRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
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
        title: Text(
          AppLocalizations.of(context)?.translate('circle.invitation') ??
              "Circle Invitation",
        ),
        content: Text(
          (AppLocalizations.of(context)?.translate('circle.join_confirm') ??
                  "Do you want to join {name}'s UPI Circle?")
              .replaceAll("{name}", circle['primary_user_name']),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToInvite(circle['id'], 'REJECT');
            },
            child: Text(
              AppLocalizations.of(context)?.translate('circle.reject') ??
                  "Reject",
              style: const TextStyle(color: Colors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToInvite(circle['id'], 'ACCEPT');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(
              AppLocalizations.of(context)?.translate('circle.accept') ??
                  "Accept",
            ),
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
                                        ? (AppLocalizations.of(
                                                context,
                                              )?.translate(
                                                'circle.child_summary',
                                              ) ??
                                              "Child's Spending Summary")
                                        : (AppLocalizations.of(
                                                context,
                                              )?.translate(
                                                'circle.my_summary',
                                              ) ??
                                              "My Spending Summary"),
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
                              tooltip:
                                  AppLocalizations.of(
                                    context,
                                  )?.translate('circle.refresh_data') ??
                                  "Refresh Data",
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
                                Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.translate('circle.spent') ??
                                      "Spent",
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        if (isPrimary)
                          _buildSummaryRowWithAction(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.limit_label') ??
                                "Monthly Limit",
                            "₹${limit.toStringAsFixed(0)}",
                            Colors.black,
                            onEdit: () {
                              Navigator.pop(context);
                              _showEditMemberDialog(
                                circle,
                                isPrimary: isPrimary,
                              );
                            },
                          )
                        else
                          _buildSummaryRow(
                            AppLocalizations.of(
                                  context,
                                )?.translate('circle.limit_label') ??
                                "Monthly Limit",
                            "₹${limit.toStringAsFixed(0)}",
                            Colors.black,
                          ),
                        const Divider(height: 24),
                        _buildSummaryRow(
                          AppLocalizations.of(
                                context,
                              )?.translate('circle.remaining') ??
                              "Remaining",
                          "₹${remaining.toStringAsFixed(0)}",
                          Colors.green,
                        ),
                        const Divider(height: 24),
                        _buildSummaryRow(
                          AppLocalizations.of(
                                context,
                              )?.translate('circle.status') ??
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
                      child: Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('circle.remove_member') ??
                            "Remove Member",
                        style: const TextStyle(
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
                    child: Text(
                      AppLocalizations.of(context)?.translate('common.close') ??
                          "Close",
                      style: const TextStyle(
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

  void _showEditMemberDialog(dynamic circle, {bool isPrimary = true}) {
    final controller = TextEditingController(
      text: circle['monthly_limit']?.toString() ?? "5000",
    );
    String delegationType = circle['delegation_type'] ?? "FULL";
    int? selectedPrimaryId = circle['primary_user_id'];
    List<dynamic> myAccounts = [];
    bool isLoadingAccounts = true;

    // Only fetch accounts for parent (funding account selection)
    if (isPrimary) {
      _apiService.getMyAllAccounts().then((accounts) {
        if (mounted) {
          myAccounts = accounts;
          isLoadingAccounts = false;
        }
      });
    } else {
      isLoadingAccounts = false;
    }

    final dialogTitle = isPrimary
        ? "Edit Circle for ${circle['secondary_user_name']}"
        : "Edit My Circle Settings";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // If accounts were fetched, trigger a rebuild of the dialog content
          if (isPrimary && isLoadingAccounts && myAccounts.isEmpty) {
            _apiService.getMyAllAccounts().then((accounts) {
              if (mounted) {
                setDialogState(() {
                  myAccounts = accounts;
                  isLoadingAccounts = false;
                });
              }
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(dialogTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppLocalizations.of(
                            context,
                          )?.translate('circle.delegation_mode') ??
                          "Delegation Mode",
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
                      onChanged: (v) =>
                          setDialogState(() => delegationType = v!),
                      child: Column(
                        children: [
                          RadioListTile<String>.adaptive(
                            title: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('circle.auto_pay') ??
                                  "Full (Auto-pay)",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('circle.full_auto_desc') ??
                                  "Member spends directly within limits",
                            ),
                            value: "FULL",
                          ),
                          const Divider(height: 1),
                          RadioListTile<String>.adaptive(
                            title: Text(
                              AppLocalizations.of(context)?.translate(
                                    'circle.partial_approve_title',
                                  ) ??
                                  "Partial (Approve)",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.translate('circle.partial_approve_desc') ??
                                  "You approve every payment",
                            ),
                            value: "PARTIAL",
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Only show Funding Account for parent
                  if (isPrimary) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('circle.funding_account') ??
                            "Funding Account",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoadingAccounts)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      )
                    else if (myAccounts.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: selectedPrimaryId,
                            items: myAccounts.map((account) {
                              return DropdownMenuItem<int>(
                                value: account['id'],
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      account['upi_id'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      account['bank_name'] ?? "Unknown Bank",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setDialogState(() => selectedPrimaryId = v);
                            },
                          ),
                        ),
                      )
                    else
                      Text(
                        AppLocalizations.of(
                              context,
                            )?.translate('circle.using_current_account') ??
                            "Using current account",
                        style: const TextStyle(color: Colors.grey),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  AppLocalizations.of(context)?.translate('common.cancel') ??
                      "Cancel",
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newLimit = double.tryParse(controller.text);
                  if (newLimit == null || newLimit <= 0) return;

                  // Navigate to PIN setup screen for update
                  if (!context.mounted) return;

                  final pinResult =
                      await Navigator.pushNamed(
                            context,
                            '/upi-circle-setup-pin',
                            arguments: {
                              'secondaryUpi': isPrimary
                                  ? circle['secondary_user_upi']
                                  : circle['primary_user_upi'],
                              'secondaryName': isPrimary
                                  ? circle['secondary_user_name']
                                  : circle['primary_user_name'],
                              'limit': newLimit,
                              'delegationType': delegationType,
                              'primaryUserId': isPrimary
                                  ? selectedPrimaryId
                                  : null,
                              'isUpdate': true,
                              'circleId': circle['id'],
                            },
                          )
                          as Map<String, dynamic>?;

                  if (pinResult == null || !context.mounted) return;

                  final bool success = pinResult['success'] ?? false;
                  final String message = pinResult['message'] ?? "";

                  Navigator.pop(context); // Close the edit dialog

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      content: Row(
                        children: [
                          Icon(
                            success ? Icons.check_circle : Icons.error,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            message.isNotEmpty
                                ? message
                                : (success
                                      ? (AppLocalizations.of(
                                              context,
                                            )?.translate(
                                              'circle.update_success',
                                            ) ??
                                            "Circle Updated!")
                                      : (AppLocalizations.of(
                                              context,
                                            )?.translate(
                                              'circle.update_failed',
                                            ) ??
                                            "Failed to update circle")),
                          ),
                        ],
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );

                  if (success) {
                    _loadCircleData();
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)?.translate('common.update') ??
                      "Update",
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmRemoveMember(dynamic circle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(
                context,
              )?.translate('circle.remove_member_title') ??
              "Remove Member",
        ),
        content: Text(
          AppLocalizations.of(context)?.translate(
                'circle.remove_confirm_desc',
                arguments: {'name': circle['secondary_user_name']},
              ) ??
              "Are you sure you want to remove ${circle['secondary_user_name']} from your UPI Circle? They will immediately lose access to spend from your account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)?.translate('common.cancel') ??
                  "Cancel",
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              // Navigate to PIN setup screen for removal
              if (!context.mounted) return;

              final pinResult =
                  await Navigator.pushNamed(
                        context,
                        '/upi-circle-setup-pin',
                        arguments: {
                          'secondaryUpi': circle['secondary_user_upi'],
                          'secondaryName': circle['secondary_user_name'],
                          'limit': (circle['monthly_limit'] ?? 0.0).toDouble(),
                          'isRemove': true,
                          'circleId': circle['id'],
                        },
                      )
                      as Map<String, dynamic>?;

              if (pinResult == null || !context.mounted) return;

              final bool success = pinResult['success'] ?? false;
              final String message = pinResult['message'] ?? "";

              Navigator.pop(context); // Close the confirmation dialog

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  content: Row(
                    children: [
                      Icon(
                        success ? Icons.check_circle : Icons.error,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        message.isNotEmpty
                            ? message
                            : (success
                                  ? (AppLocalizations.of(
                                          context,
                                        )?.translate('circle.member_removed') ??
                                        "Member Removed!")
                                  : (AppLocalizations.of(
                                          context,
                                        )?.translate('circle.fail_remove') ??
                                        "Failed to remove member")),
                      ),
                    ],
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );

              if (success) {
                _loadCircleData();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              AppLocalizations.of(context)?.translate('common.remove') ??
                  "Remove",
            ),
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
                AppLocalizations.of(context)?.translate('common.understood') ??
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
