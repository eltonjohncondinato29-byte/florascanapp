part of '../main.dart';

// ==================== CROP SERVICE ====================
/// Service for managing crops, validation, and activity logging
class CropService {
  static const String cropsTable = 'crop_profiles';
  static const String activityLogTable = 'admin_activity_logs';
  static const String cropHistoryTable = 'crop_history';

  // Validation thresholds (configurable)
  static const double highConfidenceThreshold = 80.0;
  static const double mediumConfidenceThreshold = 50.0;
  static const double lowConfidenceThreshold = 0.0;

  // Measurement tolerance percentages
  static const double lengthTolerance = 15.0; // ±15%
  static const double widthTolerance = 15.0; // ±15%
  static const double perimeterTolerance = 15.0; // ±15%
  static const double aspectRatioTolerance = 20.0; // ±20%
  static const double spadTolerance = 10.0; // ±10
  static const double hueTolerance = 30.0; // ±30 degrees

  // ==================== BUILT-IN DEFAULT CROPS ====================
  /// These two crops are always available in the scanner even when
  /// the Supabase database has no admin-created crop profiles yet.
  static final List<CropProfile> _defaultCrops = [
    CropProfile(
      id: 'default_cucumber',
      cropName: 'Cucumber (Cucumis sativus)',
      referenceSpadIndex: 42.5,
      standardLeafLengthCm: 18.0,
      standardLeafWidthCm: 17.0,
      standardLeafColor: 'Dark Green',
      standardLeafPerimeterCm: 55.0,
      standardAspectRatio: 1.06,
      createdBy: 'System',
      createdDate: DateTime(2025, 1, 1),
    ),
    CropProfile(
      id: 'default_robusta_coffee',
      cropName: 'Robusta Coffee',
      referenceSpadIndex: 48.0,
      standardLeafLengthCm: 22.0,
      standardLeafWidthCm: 9.0,
      standardLeafColor: 'Deep Glossy Green',
      standardLeafPerimeterCm: 51.0,
      standardAspectRatio: 2.44,
      createdBy: 'System',
      createdDate: DateTime(2025, 1, 1),
    ),
  ];

  /// Validates if a scanned leaf matches the selected crop
  /// Returns a CropValidationResult with confidence levels
  static Future<CropValidationResult> validateScannedLeaf({
    required CropProfile selectedCrop,
    required double scannedLengthCm,
    required double scannedWidthCm,
    required double scannedPerimeterCm,
    required double scannedAspectRatio,
    required double scannedHue,
    required int? scannedSpad,
    required List<CropProfile> allCrops,
  }) async {
    // Calculate match scores for all crops
    final matches = <CropMatch>[];

    for (final crop in allCrops) {
      final matchPercentage = _calculateMatchPercentage(
        crop: crop,
        scannedLength: scannedLengthCm,
        scannedWidth: scannedWidthCm,
        scannedPerimeter: scannedPerimeterCm,
        scannedAspectRatio: scannedAspectRatio,
        scannedHue: scannedHue,
        scannedSpad: scannedSpad,
      );

      final matchDetails = _calculateMatchDetails(
        crop: crop,
        scannedLength: scannedLengthCm,
        scannedWidth: scannedWidthCm,
        scannedPerimeter: scannedPerimeterCm,
        scannedAspectRatio: scannedAspectRatio,
        scannedHue: scannedHue,
        scannedSpad: scannedSpad,
      );

      matches.add(
        CropMatch(
          cropId: crop.id,
          cropName: crop.cropName,
          matchPercentage: matchPercentage,
          matchDetails: matchDetails,
        ),
      );
    }

    // Sort by match percentage (highest first)
    matches.sort((a, b) => b.matchPercentage.compareTo(a.matchPercentage));

    // Find match for selected crop
    final selectedMatch = matches.firstWhere(
      (m) => m.cropId == selectedCrop.id,
      orElse: () => CropMatch(
        cropId: selectedCrop.id,
        cropName: selectedCrop.cropName,
        matchPercentage: 0.0,
        matchDetails: {},
      ),
    );

    // Determine confidence level
    ConfidenceLevel confidenceLevel;
    if (selectedMatch.matchPercentage >= highConfidenceThreshold) {
      confidenceLevel = ConfidenceLevel.high;
    } else if (selectedMatch.matchPercentage >= mediumConfidenceThreshold) {
      confidenceLevel = ConfidenceLevel.medium;
    } else {
      confidenceLevel = ConfidenceLevel.low;
    }

    return CropValidationResult(
      selectedCropId: selectedCrop.id,
      selectedCropName: selectedCrop.cropName,
      matchPercentage: selectedMatch.matchPercentage,
      allMatches: matches,
      confidenceLevel: confidenceLevel,
    );
  }

  /// Calculates the match percentage between scanned leaf and crop profile
  static double _calculateMatchPercentage({
    required CropProfile crop,
    required double scannedLength,
    required double scannedWidth,
    required double scannedPerimeter,
    required double scannedAspectRatio,
    required double scannedHue,
    required int? scannedSpad,
  }) {
    final scores = <double>[];

    // Length match (25% weight)
    final lengthMatch = _calculateSimilarity(
      actual: scannedLength,
      standard: crop.standardLeafLengthCm,
      tolerance: lengthTolerance,
    );
    scores.add(lengthMatch * 0.25);

    // Width match (25% weight)
    final widthMatch = _calculateSimilarity(
      actual: scannedWidth,
      standard: crop.standardLeafWidthCm,
      tolerance: widthTolerance,
    );
    scores.add(widthMatch * 0.25);

    // Perimeter match (15% weight)
    final perimeterMatch = _calculateSimilarity(
      actual: scannedPerimeter,
      standard: crop.standardLeafPerimeterCm,
      tolerance: perimeterTolerance,
    );
    scores.add(perimeterMatch * 0.15);

    // Aspect ratio match (15% weight)
    final aspectRatioMatch = _calculateSimilarity(
      actual: scannedAspectRatio,
      standard: crop.standardAspectRatio,
      tolerance: aspectRatioTolerance,
    );
    scores.add(aspectRatioMatch * 0.15);

    // Hue/Color match (10% weight)
    final hueMatch = _calculateHueSimilarity(
      actual: scannedHue,
      standardLow: _getHueRangeLow(crop.standardLeafColor),
      standardHigh: _getHueRangeHigh(crop.standardLeafColor),
      tolerance: hueTolerance,
    );
    scores.add(hueMatch * 0.10);

    // SPAD match (10% weight) - only if available
    if (scannedSpad != null) {
      final spadMatch = _calculateSimilarity(
        actual: scannedSpad.toDouble(),
        standard: crop.referenceSpadIndex,
        tolerance: spadTolerance,
      );
      scores.add(spadMatch * 0.10);
    }

    final totalScore = scores.fold<double>(0.0, (sum, score) => sum + score);

    // Normalize to 100 if SPAD wasn't used
    if (scannedSpad == null) {
      return (totalScore / 0.90) * 100;
    }

    return totalScore * 100;
  }

  /// Calculates individual match details for display
  static Map<String, String> _calculateMatchDetails({
    required CropProfile crop,
    required double scannedLength,
    required double scannedWidth,
    required double scannedPerimeter,
    required double scannedAspectRatio,
    required double scannedHue,
    required int? scannedSpad,
  }) {
    final details = <String, String>{};

    details['length'] =
        '${(_calculateSimilarity(actual: scannedLength, standard: crop.standardLeafLengthCm, tolerance: lengthTolerance) * 100).toStringAsFixed(0)}%';
    details['width'] =
        '${(_calculateSimilarity(actual: scannedWidth, standard: crop.standardLeafWidthCm, tolerance: widthTolerance) * 100).toStringAsFixed(0)}%';
    details['perimeter'] =
        '${(_calculateSimilarity(actual: scannedPerimeter, standard: crop.standardLeafPerimeterCm, tolerance: perimeterTolerance) * 100).toStringAsFixed(0)}%';
    details['aspect_ratio'] =
        '${(_calculateSimilarity(actual: scannedAspectRatio, standard: crop.standardAspectRatio, tolerance: aspectRatioTolerance) * 100).toStringAsFixed(0)}%';
    details['color'] =
        '${(_calculateHueSimilarity(actual: scannedHue, standardLow: _getHueRangeLow(crop.standardLeafColor), standardHigh: _getHueRangeHigh(crop.standardLeafColor), tolerance: hueTolerance) * 100).toStringAsFixed(0)}%';

    if (scannedSpad != null) {
      details['spad'] =
          '${(_calculateSimilarity(actual: scannedSpad.toDouble(), standard: crop.referenceSpadIndex, tolerance: spadTolerance) * 100).toStringAsFixed(0)}%';
    }

    return details;
  }

  /// Calculates similarity score (0.0 to 1.0) between actual and standard values
  /// Uses percentage tolerance
  static double _calculateSimilarity({
    required double actual,
    required double standard,
    required double tolerance,
  }) {
    if (standard == 0) return 0.0;

    final difference = (actual - standard).abs();
    final allowedDifference = (standard * tolerance) / 100;

    if (difference <= allowedDifference) {
      return 1.0;
    }

    // Gradual decrease in similarity as difference increases
    final exceedance = difference - allowedDifference;
    final penaltyFactor = 1.0 - (exceedance / standard);

    return max(0.0, penaltyFactor);
  }

  /// Calculates hue similarity considering the circular nature of hue values
  static double _calculateHueSimilarity({
    required double actual,
    required double standardLow,
    required double standardHigh,
    required double tolerance,
  }) {
    // Normalize hue values to 0-360 range
    final normalizedActual = actual % 360;

    // Check if actual hue is within the standard range (with tolerance)
    final lowerBound = (standardLow - tolerance).clamp(0, 360);
    final upperBound = (standardHigh + tolerance).clamp(0, 360);

    if (lowerBound <= upperBound) {
      if (normalizedActual >= lowerBound && normalizedActual <= upperBound) {
        return 1.0;
      }
    } else {
      // Handle wraparound (e.g., red: 350-10)
      if (normalizedActual >= lowerBound || normalizedActual <= upperBound) {
        return 1.0;
      }
    }

    // Calculate penalty for being outside range
    final minDistance = min(
      (normalizedActual - upperBound).abs(),
      (lowerBound - normalizedActual).abs(),
    );

    final maxPenaltyDistance = tolerance * 2;
    final penaltyFactor = 1.0 - (minDistance / maxPenaltyDistance);

    return max(0.0, penaltyFactor);
  }

  /// Gets the low end of hue range for a color name
  static double _getHueRangeLow(String colorName) {
    const colorRanges = {
      'Dark Green': 90.0,
      'Deep Glossy Green': 100.0,
      'Green': 85.0,
      'Light Green': 80.0,
      'Yellow-Green': 60.0,
    };
    return colorRanges[colorName] ?? 90.0;
  }

  /// Gets the high end of hue range for a color name
  static double _getHueRangeHigh(String colorName) {
    const colorRanges = {
      'Dark Green': 140.0,
      'Deep Glossy Green': 150.0,
      'Green': 140.0,
      'Light Green': 150.0,
      'Yellow-Green': 100.0,
    };
    return colorRanges[colorName] ?? 140.0;
  }

  /// Fetches all crop profiles from the database
  static Future<List<CropProfile>> fetchAllCrops() async {
    try {
      debugPrint('🌱 Fetching crops from crop_profiles...');

      // FIX: was `supabase.order('crop_name')` which called .order() directly
      // on SupabaseClient — must be chained on a table query builder instead.
      final response = await supabase
          .from(cropsTable)
          .select()
          .order('crop_name');

      debugPrint('✅ Response type: ${response.runtimeType}');
      debugPrint('✅ Response: $response');

      final crops = (response as List<dynamic>)
          .map((json) => CropProfile.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('✅ Loaded ${crops.length} crops');
      return crops;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching crops: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return [];
    }
  }

  /// Fetches crops for the scanner — merges built-in defaults with database crops.
  ///
  /// Rules:
  /// • A DB crop with the **exact same name** as a default silently replaces the
  ///   default, so admins can override reference measurements without duplication.
  /// • A DB crop whose name is a **simplified prefix** of a default crop name is
  ///   silently excluded in favour of the richer default entry.
  ///   e.g. DB "Cucumber" is dropped when default "Cucumber (Cucumis sativus)"
  ///   already exists, preventing duplicate cards in the scanner list.
  /// • Falls back to the default list alone if the DB is unreachable.
  static Future<List<CropProfile>> fetchCropsForScanning() async {
    final dbCrops = await fetchAllCrops();

    // Remove DB crops that are a simplified/prefix version of a default name.
    // Exact-name matches are intentionally kept here (handled in the merge step).
    final filteredDbCrops = dbCrops.where((dbCrop) {
      final dbName = dbCrop.cropName.toLowerCase().trim();
      return !_defaultCrops.any((defaultCrop) {
        final defaultName = defaultCrop.cropName.toLowerCase().trim();
        // Skip exact matches — those are handled below (DB overrides default).
        if (defaultName == dbName) return false;
        // Filter out if the default name starts with the DB name followed by
        // a space, '(' or ' (' — catching patterns like "Cucumber (Cucumis …)".
        return defaultName.startsWith('$dbName ') ||
            defaultName.startsWith('$dbName(') ||
            defaultName.startsWith('$dbName (');
      });
    }).toList();

    final filteredDbCropNames = filteredDbCrops
        .map((c) => c.cropName.toLowerCase())
        .toSet();

    final merged = <CropProfile>[
      // Include a default only when no remaining DB crop has the same name.
      ..._defaultCrops.where(
        (c) => !filteredDbCropNames.contains(c.cropName.toLowerCase()),
      ),
      ...filteredDbCrops,
    ]..sort((a, b) => a.cropName.compareTo(b.cropName));

    return merged;
  }

  /// Fetches a single crop by ID
  static Future<CropProfile?> fetchCropById(String cropId) async {
    try {
      final response = await supabase
          .from(cropsTable)
          .select()
          .eq('id', cropId)
          .single();

      return CropProfile.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching crop: $e');
      return null;
    }
  }

  /// Creates a new crop profile
  static Future<CropProfile?> createCrop({
    required String cropName,
    required double referenceSpadIndex,
    required double standardLeafLengthCm,
    required double standardLeafWidthCm,
    required String standardLeafColor,
    required double standardLeafPerimeterCm,
    required double standardAspectRatio,
    required String adminId,
    required String adminName,
  }) async {
    try {
      final cropId = DateTime.now().millisecondsSinceEpoch.toString();
      final now = DateTime.now();

      final cropData = CropProfile(
        id: cropId,
        cropName: cropName,
        referenceSpadIndex: referenceSpadIndex,
        standardLeafLengthCm: standardLeafLengthCm,
        standardLeafWidthCm: standardLeafWidthCm,
        standardLeafColor: standardLeafColor,
        standardLeafPerimeterCm: standardLeafPerimeterCm,
        standardAspectRatio: standardAspectRatio,
        createdBy: adminName,
        createdDate: now,
      );

      await supabase.from(cropsTable).insert(cropData.toJson());

      // Log activity
      await logActivity(
        adminId: adminId,
        adminName: adminName,
        actionType: AdminActionType.createdCrop,
        cropName: cropName,
      );

      // Record history
      await recordCropHistory(
        cropId: cropId,
        cropName: cropName,
        eventType: CropHistoryEventType.created,
        adminId: adminId,
        adminName: adminName,
        description: 'Crop profile created with reference measurements',
      );

      return cropData;
    } catch (e) {
      debugPrint('Error creating crop: $e');
      return null;
    }
  }

  /// Updates an existing crop profile
  static Future<CropProfile?> updateCrop({
    required String cropId,
    required String cropName,
    required double referenceSpadIndex,
    required double standardLeafLengthCm,
    required double standardLeafWidthCm,
    required String standardLeafColor,
    required double standardLeafPerimeterCm,
    required double standardAspectRatio,
    required String adminId,
    required String adminName,
  }) async {
    try {
      // Get current crop for comparison
      final currentCrop = await fetchCropById(cropId);
      if (currentCrop == null) return null;

      final now = DateTime.now();

      final updatedCropData = currentCrop.copyWith(
        cropName: cropName,
        referenceSpadIndex: referenceSpadIndex,
        standardLeafLengthCm: standardLeafLengthCm,
        standardLeafWidthCm: standardLeafWidthCm,
        standardLeafColor: standardLeafColor,
        standardLeafPerimeterCm: standardLeafPerimeterCm,
        standardAspectRatio: standardAspectRatio,
        lastModifiedBy: adminName,
        lastModifiedDate: now,
      );

      await supabase
          .from(cropsTable)
          .update(updatedCropData.toJson())
          .eq('id', cropId);

      // Detect changes
      final changes = _detectChanges(currentCrop, updatedCropData);

      // Log activity
      await logActivity(
        adminId: adminId,
        adminName: adminName,
        actionType: AdminActionType.updatedCrop,
        cropName: cropName,
        changeDescription: _buildChangeDescription(changes),
        previousValues: _cropToMap(currentCrop),
        newValues: _cropToMap(updatedCropData),
      );

      // Record history
      await recordCropHistory(
        cropId: cropId,
        cropName: cropName,
        eventType: CropHistoryEventType.updated,
        adminId: adminId,
        adminName: adminName,
        previousValues: _cropToMap(currentCrop),
        newValues: _cropToMap(updatedCropData),
        description: 'Crop profile updated: $changes',
      );

      return updatedCropData;
    } catch (e) {
      debugPrint('Error updating crop: $e');
      return null;
    }
  }

  /// Deletes a crop profile
  static Future<bool> deleteCrop({
    required String cropId,
    required String cropName,
    required String adminId,
    required String adminName,
  }) async {
    try {
      // Get crop for history
      final crop = await fetchCropById(cropId);
      if (crop == null) return false;

      await supabase.from(cropsTable).delete().eq('id', cropId);

      // Log activity
      await logActivity(
        adminId: adminId,
        adminName: adminName,
        actionType: AdminActionType.deletedCrop,
        cropName: cropName,
      );

      // Record history
      await recordCropHistory(
        cropId: cropId,
        cropName: cropName,
        eventType: CropHistoryEventType.deleted,
        adminId: adminId,
        adminName: adminName,
        previousValues: _cropToMap(crop),
        description: 'Crop profile deleted',
      );

      return true;
    } catch (e) {
      debugPrint('Error deleting crop: $e');
      return false;
    }
  }

  /// Logs an administrative action
  static Future<void> logActivity({
    required String adminId,
    required String adminName,
    required AdminActionType actionType,
    required String cropName,
    String? changeDescription,
    Map<String, dynamic>? previousValues,
    Map<String, dynamic>? newValues,
  }) async {
    try {
      final activityId = DateTime.now().millisecondsSinceEpoch.toString();

      final activityLog = AdminActivityLog(
        id: activityId,
        adminId: adminId,
        adminName: adminName,
        actionType: actionType,
        cropName: cropName,
        timestamp: DateTime.now(),
        changeDescription: changeDescription,
        previousValues: previousValues,
        newValues: newValues,
      );

      await supabase.from(activityLogTable).insert(activityLog.toJson());
    } catch (e) {
      debugPrint('Error logging activity: $e');
    }
  }

  /// Records a crop history event
  static Future<void> recordCropHistory({
    required String cropId,
    required String cropName,
    required CropHistoryEventType eventType,
    required String adminId,
    required String adminName,
    Map<String, dynamic>? previousValues,
    Map<String, dynamic>? newValues,
    String? description,
  }) async {
    try {
      final historyId = DateTime.now().millisecondsSinceEpoch.toString();

      final history = CropHistory(
        id: historyId,
        cropId: cropId,
        cropName: cropName,
        eventType: eventType,
        adminId: adminId,
        adminName: adminName,
        timestamp: DateTime.now(),
        previousValues: previousValues,
        newValues: newValues,
        description: description,
      );

      await supabase.from(cropHistoryTable).insert(history.toJson());
    } catch (e) {
      debugPrint('Error recording crop history: $e');
    }
  }

  /// Fetches activity logs for a crop
  static Future<List<AdminActivityLog>> fetchActivityLogs({
    int limit = 100,
    String? cropName,
  }) async {
    try {
      var query = supabase
          .from(activityLogTable)
          .select()
          .order('timestamp', ascending: false);

      // Note: Filtering by crop_name is optional; we fetch all logs for now

      final response = await query.limit(limit);

      return (response as List<dynamic>)
          .map(
            (json) => AdminActivityLog.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('Error fetching activity logs: $e');
      return [];
    }
  }

  /// Fetches crop history
  static Future<List<CropHistory>> fetchCropHistory({
    required String cropId,
    int limit = 50,
  }) async {
    try {
      final response = await supabase
          .from(cropHistoryTable)
          .select()
          .eq('crop_id', cropId)
          .order('timestamp', ascending: false)
          .limit(limit);

      return (response as List<dynamic>)
          .map((json) => CropHistory.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching crop history: $e');
      return [];
    }
  }

  /// Converts CropProfile to Map for history tracking
  static Map<String, dynamic> _cropToMap(CropProfile crop) => {
    'crop_name': crop.cropName,
    'reference_spad_index': crop.referenceSpadIndex,
    'standard_leaf_length_cm': crop.standardLeafLengthCm,
    'standard_leaf_width_cm': crop.standardLeafWidthCm,
    'standard_leaf_color': crop.standardLeafColor,
    'standard_leaf_perimeter_cm': crop.standardLeafPerimeterCm,
    'standard_aspect_ratio': crop.standardAspectRatio,
  };

  /// Detects changes between two crop profiles
  static List<String> _detectChanges(CropProfile oldCrop, CropProfile newCrop) {
    final changes = <String>[];

    if (oldCrop.cropName != newCrop.cropName) {
      changes.add('Crop name: ${oldCrop.cropName} → ${newCrop.cropName}');
    }
    if (oldCrop.referenceSpadIndex != newCrop.referenceSpadIndex) {
      changes.add(
        'SPAD Index: ${oldCrop.referenceSpadIndex} → ${newCrop.referenceSpadIndex}',
      );
    }
    if (oldCrop.standardLeafLengthCm != newCrop.standardLeafLengthCm) {
      changes.add(
        'Leaf Length: ${oldCrop.standardLeafLengthCm}cm → ${newCrop.standardLeafLengthCm}cm',
      );
    }
    if (oldCrop.standardLeafWidthCm != newCrop.standardLeafWidthCm) {
      changes.add(
        'Leaf Width: ${oldCrop.standardLeafWidthCm}cm → ${newCrop.standardLeafWidthCm}cm',
      );
    }
    if (oldCrop.standardLeafColor != newCrop.standardLeafColor) {
      changes.add(
        'Leaf Color: ${oldCrop.standardLeafColor} → ${newCrop.standardLeafColor}',
      );
    }
    if (oldCrop.standardLeafPerimeterCm != newCrop.standardLeafPerimeterCm) {
      changes.add(
        'Leaf Perimeter: ${oldCrop.standardLeafPerimeterCm}cm → ${newCrop.standardLeafPerimeterCm}cm',
      );
    }
    if (oldCrop.standardAspectRatio != newCrop.standardAspectRatio) {
      changes.add(
        'Aspect Ratio: ${oldCrop.standardAspectRatio} → ${newCrop.standardAspectRatio}',
      );
    }

    return changes;
  }

  /// Builds a description of changes
  static String _buildChangeDescription(List<String> changes) {
    if (changes.isEmpty) return 'No changes detected';
    if (changes.length == 1) return changes.first;
    return '${changes.length} fields updated';
  }
}
