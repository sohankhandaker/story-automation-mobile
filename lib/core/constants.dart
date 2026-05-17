class AppConstants {
  // ── Change this to your Render.com URL after deployment ──────────────────
  // Android emulator reaches host machine via 10.0.2.2
  // Change to your Render URL before building the stakeholder APK
  static const String baseUrl = 'https://story-automation-api.onrender.com';

  // Status display names
  static const Map<String, String> statusLabels = {
    'Backlog': 'Backlog',
    'Ready': 'Ready',
    'In Progress': 'In Progress',
    'In Review': 'In Review',
    'Changes Requested': 'Changes Requested',
    'Done': 'Done',
  };

  // Status colors (hex strings mapped in the widget layer)
  static const Map<String, int> statusColors = {
    'Backlog': 0xFF9E9E9E,
    'Ready': 0xFF2196F3,
    'In Progress': 0xFFFF9800,
    'In Review': 0xFF9C27B0,
    'Changes Requested': 0xFFF44336,
    'Done': 0xFF4CAF50,
  };

  static const Map<String, int> priorityColors = {
    'Low': 0xFF4CAF50,
    'Medium': 0xFF2196F3,
    'High': 0xFFFF9800,
    'Critical': 0xFFF44336,
  };

  static const int pollIntervalSeconds = 5;
}
