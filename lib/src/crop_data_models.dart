part of '../main.dart';

// ==================== CROP PROFILE DATA MODEL ====================
/// Represents a standard crop profile with reference measurements
class CropProfile {
  CropProfile({
    required this.id,
    required this.cropName,
    required this.referenceSpadIndex,
    required this.standardLeafLengthCm,
    required this.standardLeafWidthCm,
    required this.standardLeafColor,
    required this.standardLeafPerimeterCm,
    required this.standardAspectRatio,
    required this.createdBy,
    required this.createdDate,
    this.lastModifiedBy,
    this.lastModifiedDate,
  });

  final String id;
  final String cropName;
  final double referenceSpadIndex; // Chlorophyll SPAD value
  final double standardLeafLengthCm;
  final double standardLeafWidthCm;
  final String standardLeafColor; // e.g., "Dark Green", "Deep Glossy Green"
  final double standardLeafPerimeterCm;
  final double standardAspectRatio; // Length / Width
  final String createdBy; // Admin name
  final DateTime createdDate;
  final String? lastModifiedBy; // Admin name
  final DateTime? lastModifiedDate;

  /// Converts CropProfile to JSON for database storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'crop_name': cropName,
    'reference_spad_index': referenceSpadIndex,
    'standard_leaf_length_cm': standardLeafLengthCm,
    'standard_leaf_width_cm': standardLeafWidthCm,
    'standard_leaf_color': standardLeafColor,
    'standard_leaf_perimeter_cm': standardLeafPerimeterCm,
    'standard_aspect_ratio': standardAspectRatio,
    'created_by': createdBy,
    'created_date': createdDate.toIso8601String(),
    'last_modified_by': lastModifiedBy,
    'last_modified_date': lastModifiedDate?.toIso8601String(),
  };

  /// Creates CropProfile from JSON data.
  /// Uses null-safe defaults so rows inserted directly in Supabase
  /// (missing optional columns) do not throw a silent TypeError.
  factory CropProfile.fromJson(Map<String, dynamic> json) => CropProfile(
    id: json['id'] as String,
    cropName: json['crop_name'] as String,
    referenceSpadIndex:
        (json['reference_spad_index'] as num?)?.toDouble() ?? 0.0,
    standardLeafLengthCm:
        (json['standard_leaf_length_cm'] as num?)?.toDouble() ?? 0.0,
    standardLeafWidthCm:
        (json['standard_leaf_width_cm'] as num?)?.toDouble() ?? 0.0,
    standardLeafColor: json['standard_leaf_color'] as String? ?? 'Dark Green',
    standardLeafPerimeterCm:
        (json['standard_leaf_perimeter_cm'] as num?)?.toDouble() ?? 0.0,
    standardAspectRatio:
        (json['standard_aspect_ratio'] as num?)?.toDouble() ?? 1.0,
    createdBy: json['created_by'] as String? ?? 'Unknown',
    createdDate: json['created_date'] != null
        ? DateTime.parse(json['created_date'] as String)
        : DateTime(2025, 1, 1),
    lastModifiedBy: json['last_modified_by'] as String?,
    lastModifiedDate: json['last_modified_date'] != null
        ? DateTime.parse(json['last_modified_date'] as String)
        : null,
  );

  /// Creates a copy of this crop profile with modified fields
  CropProfile copyWith({
    String? id,
    String? cropName,
    double? referenceSpadIndex,
    double? standardLeafLengthCm,
    double? standardLeafWidthCm,
    String? standardLeafColor,
    double? standardLeafPerimeterCm,
    double? standardAspectRatio,
    String? createdBy,
    DateTime? createdDate,
    String? lastModifiedBy,
    DateTime? lastModifiedDate,
  }) => CropProfile(
    id: id ?? this.id,
    cropName: cropName ?? this.cropName,
    referenceSpadIndex: referenceSpadIndex ?? this.referenceSpadIndex,
    standardLeafLengthCm: standardLeafLengthCm ?? this.standardLeafLengthCm,
    standardLeafWidthCm: standardLeafWidthCm ?? this.standardLeafWidthCm,
    standardLeafColor: standardLeafColor ?? this.standardLeafColor,
    standardLeafPerimeterCm:
        standardLeafPerimeterCm ?? this.standardLeafPerimeterCm,
    standardAspectRatio: standardAspectRatio ?? this.standardAspectRatio,
    createdBy: createdBy ?? this.createdBy,
    createdDate: createdDate ?? this.createdDate,
    lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    lastModifiedDate: lastModifiedDate ?? this.lastModifiedDate,
  );
}

// ==================== CROP VALIDATION RESULT ====================
/// Result of validating scanned leaf against crop profiles
class CropValidationResult {
  CropValidationResult({
    required this.selectedCropId,
    required this.selectedCropName,
    required this.matchPercentage,
    required this.allMatches,
    required this.confidenceLevel,
  });

  final String selectedCropId;
  final String selectedCropName;
  final double matchPercentage; // 0-100
  final List<CropMatch> allMatches; // Sorted by confidence
  final ConfidenceLevel confidenceLevel;

  /// Determines if the validation passed
  bool get isPassed => matchPercentage >= 75.0;
}

/// Represents a potential crop match for a scanned leaf
class CropMatch {
  CropMatch({
    required this.cropId,
    required this.cropName,
    required this.matchPercentage,
    required this.matchDetails,
  });

  final String cropId;
  final String cropName;
  final double matchPercentage; // 0-100
  final Map<String, String>
  matchDetails; // e.g., {"length": "92%", "width": "88%"}
}

/// Confidence levels for crop validation
enum ConfidenceLevel {
  high, // >= 80% match
  medium, // 50-80% match
  low, // < 50% match
}

// ==================== ACTIVITY LOG DATA MODEL ====================
/// Represents an administrative action logged in the system
class AdminActivityLog {
  AdminActivityLog({
    required this.id,
    required this.adminId,
    required this.adminName,
    required this.actionType,
    required this.cropName,
    required this.timestamp,
    this.changeDescription,
    this.previousValues,
    this.newValues,
    this.deviceIpAddress,
  });

  final String id;
  final String adminId; // User ID from Supabase Auth
  final String adminName; // Display name of admin
  final AdminActionType actionType;
  final String cropName; // Name of the affected crop
  final DateTime timestamp;
  final String? changeDescription; // Summary of changes
  final Map<String, dynamic>? previousValues; // For updates
  final Map<String, dynamic>? newValues; // For updates
  final String? deviceIpAddress; // Optional device/IP info

  /// Converts AdminActivityLog to JSON for database storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'admin_id': adminId,
    'admin_name': adminName,
    'action_type': actionType.name,
    'crop_name': cropName,
    'timestamp': timestamp.toIso8601String(),
    'change_description': changeDescription,
    'previous_values': previousValues,
    'new_values': newValues,
    'device_ip_address': deviceIpAddress,
  };

  /// Creates AdminActivityLog from JSON data
  factory AdminActivityLog.fromJson(Map<String, dynamic> json) =>
      AdminActivityLog(
        id: json['id'] as String,
        adminId: json['admin_id'] as String,
        adminName: json['admin_name'] as String,
        actionType: AdminActionType.values.byName(
          json['action_type'] as String,
        ),
        cropName: json['crop_name'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        changeDescription: json['change_description'] as String?,
        previousValues: json['previous_values'] as Map<String, dynamic>?,
        newValues: json['new_values'] as Map<String, dynamic>?,
        deviceIpAddress: json['device_ip_address'] as String?,
      );
}

/// Types of admin actions that can be logged
enum AdminActionType { createdCrop, updatedCrop, deletedCrop }

// ==================== CROP HISTORY DATA MODEL ====================
/// Represents a historical record of crop profile changes
class CropHistory {
  CropHistory({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.eventType,
    required this.adminId,
    required this.adminName,
    required this.timestamp,
    this.previousValues,
    this.newValues,
    this.description,
  });

  final String id;
  final String cropId;
  final String cropName;
  final CropHistoryEventType eventType;
  final String adminId;
  final String adminName;
  final DateTime timestamp;
  final Map<String, dynamic>? previousValues;
  final Map<String, dynamic>? newValues;
  final String? description;

  /// Converts CropHistory to JSON for database storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'crop_id': cropId,
    'crop_name': cropName,
    'event_type': eventType.name,
    'admin_id': adminId,
    'admin_name': adminName,
    'timestamp': timestamp.toIso8601String(),
    'previous_values': previousValues,
    'new_values': newValues,
    'description': description,
  };

  /// Creates CropHistory from JSON data
  factory CropHistory.fromJson(Map<String, dynamic> json) => CropHistory(
    id: json['id'] as String,
    cropId: json['crop_id'] as String,
    cropName: json['crop_name'] as String,
    eventType: CropHistoryEventType.values.byName(json['event_type'] as String),
    adminId: json['admin_id'] as String,
    adminName: json['admin_name'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    previousValues: json['previous_values'] as Map<String, dynamic>?,
    newValues: json['new_values'] as Map<String, dynamic>?,
    description: json['description'] as String?,
  );
}

/// Types of crop history events
enum CropHistoryEventType { created, updated, deleted }

// ==================== USER ROLE ENUM ====================
/// User role for access control
enum UserRole { admin, regular }
