part of '../main.dart';

// ==================== LEAF SCAN REPORT DATA MODEL ====================
class LeafScanReport {
  LeafScanReport({
    required this.leafName,
    required this.timestamp,
    required this.lengthCm,
    required this.widthCm,
    required this.areaCm2,
    required this.chlorophyllValue,
    required this.status,
    required this.fertilizer,
  });

  final String leafName;
  final DateTime timestamp;
  final double lengthCm;
  final double widthCm;
  final double areaCm2;
  final int? chlorophyllValue;
  final String status;
  final String fertilizer;

  // Convert to JSON for storage
  /// Converts LeafScanReport to JSON for secure storage
  Map<String, dynamic> toJson() => {
    'leafName': leafName,
    'timestamp': timestamp.toIso8601String(),
    'lengthCm': lengthCm,
    'widthCm': widthCm,
    'areaCm2': areaCm2,
    'chlorophyllValue': chlorophyllValue,
    'status': status,
    'fertilizer': fertilizer,
  };

  // Create from JSON
  /// Creates LeafScanReport from JSON data
  factory LeafScanReport.fromJson(Map<String, dynamic> json) => LeafScanReport(
    leafName: json['leafName'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    lengthCm: (json['lengthCm'] as num).toDouble(),
    widthCm: (json['widthCm'] as num).toDouble(),
    areaCm2: (json['areaCm2'] as num).toDouble(),
    chlorophyllValue: (json['chlorophyllValue'] as num?)?.toInt(),
    status: json['status'] as String? ?? 'Leaf scanned',
    fertilizer:
        json['fertilizer'] as String? ??
        'Chlorophyll sensor not connected yet.',
  );
}

// --- Main Home ----------------------------------------------------------------
