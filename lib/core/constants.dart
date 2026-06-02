import 'package:flutter/foundation.dart';

class AppConstants {
  static const _prodUrl = 'https://story-automation-api.onrender.com';
  // Local backend via Android emulator — only used in debug builds.
  // Switch _debugUrl to _prodUrl if you want debug to hit production too.
  static const _debugUrl = 'https://story-automation-api.onrender.com';

  // Release builds always use _prodUrl — no accidental local URLs in APK.
  static const String baseUrl = kReleaseMode ? _prodUrl : _debugUrl;

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
