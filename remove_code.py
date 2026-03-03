import sys

file_path = r'c:\Users\Dell\SafePay\mobile_app\lib\spend_analysis_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove import 'api_service.dart';
content = content.replace("import 'api_service.dart';\n", "")

# 2. Remove final _api = ApiService();
content = content.replace("  final _api = ApiService();\n\n", "")
content = content.replace("  final _api = ApiService();\n", "")

# 3. Replace didUpdateWidget
old_did_update = """  @override
  void didUpdateWidget(SpendAnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculate if history length changed OR if spending limit settings changed.
    // This ensures the limit card updates live when a new transaction comes in.
    final historyChanged =
        oldWidget.history.length != widget.history.length ||
        oldWidget.user['spending_limit'] != widget.user['spending_limit'] ||
        oldWidget.user['spending_limit_period'] !=
            widget.user['spending_limit_period'];
    if (historyChanged) {
      _calculateDataForMonth();
    }
  }"""
new_did_update = """  @override
  void didUpdateWidget(SpendAnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history.length != widget.history.length) {
      _calculateDataForMonth();
    }
  }"""
content = content.replace(old_did_update, new_did_update)

# 4. Change AppBar title
content = content.replace("'Spending Limit',", "'Spend Analysis',")

# 5. Remove _buildSpendingLimitCard(isDark),
content = content.replace("              // Spending Limit Card\n              _buildSpendingLimitCard(isDark),\n\n", "")

# 6. Delete all methods from _getFrequencyLabel to the end.
idx = content.find("  String _getFrequencyLabel(int p) {")
if idx != -1:
    content = content[:idx] + "}\n"

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done')
