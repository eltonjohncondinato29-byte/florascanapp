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
    this.perimeterCm,
    this.aspectRatio,
    this.hsvGreenHue,
  });

  final String leafName;
  final DateTime timestamp;
  final double lengthCm;
  final double widthCm;
  final double areaCm2;
  final int? chlorophyllValue;
  final String status;
  final String fertilizer;

  // Extended morphology fields
  final double? perimeterCm;
  final double? aspectRatio;
  final double? hsvGreenHue;

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
    'perimeterCm': perimeterCm,
    'aspectRatio': aspectRatio,
    'hsvGreenHue': hsvGreenHue,
  };

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
    perimeterCm: (json['perimeterCm'] as num?)?.toDouble(),
    aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
    hsvGreenHue: (json['hsvGreenHue'] as num?)?.toDouble(),
  );
}
