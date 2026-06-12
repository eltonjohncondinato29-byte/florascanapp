# Developer Integration Guide - Admin Crop Management System

## Overview

This document explains the technical implementation of the Admin Crop Management, Validation, and Activity Log systems for developers who need to understand, maintain, or extend the codebase.

---

## 📂 Code Architecture

### New Source Files

#### 1. `lib/src/crop_data_models.dart`

**Purpose**: Data models for all crop-related entities

**Key Classes:**

- `CropProfile`: Represents a crop reference profile
- `CropValidationResult`: Result of leaf validation against crops
- `CropMatch`: Single crop match in validation results
- `AdminActivityLog`: Audit log entry for admin actions
- `CropHistory`: Historical record of crop changes
- `ConfidenceLevel`: Enum for validation confidence
- `AdminActionType`: Enum for admin action types
- `UserRole`: Enum for user roles (admin/regular)

**Key Methods:**

- `toJson()`: Serialization for database storage
- `fromJson()`: Deserialization from database
- `copyWith()`: Immutable updates for CropProfile

#### 2. `lib/src/crop_service.dart`

**Purpose**: Business logic for crop management and validation

**Key Static Methods:**

**Validation:**

- `validateScannedLeaf()`: Main validation orchestration
- `_calculateMatchPercentage()`: Weighted scoring algorithm
- `_calculateSimilarity()`: Metric similarity scoring
- `_calculateHueSimilarity()`: Circular hue comparison
- `_getHueRangeLow/High()`: Color range lookup

**Database Operations:**

- `fetchAllCrops()`: Get all crops from Supabase
- `fetchCropById()`: Get single crop
- `createCrop()`: Insert new crop with audit
- `updateCrop()`: Modify crop with change tracking
- `deleteCrop()`: Remove crop with deletion logging

**Audit Trail:**

- `logActivity()`: Record admin action
- `recordCropHistory()`: Store crop change event
- `fetchActivityLogs()`: Retrieve activity log entries
- `fetchCropHistory()`: Get crop modification history

**Helper Methods:**

- `_detectChanges()`: Find differences between crops
- `_buildChangeDescription()`: Summarize changes
- `_cropToMap()`: Convert model to dictionary

#### 3. `lib/src/admin_crop_management.dart`

**Purpose**: UI for admin crop management

**Widgets:**

- `AdminCropManagementPage`: Main admin crops screen
- `_AddCropDialog`: Form for creating new crops
- `_EditCropDialog`: Form for modifying crops
- `_CropHistoryPage`: Timeline of crop changes

**Key Features:**

- FutureBuilder for async crop loading
- Expandable crop cards with action menus
- Grid display of crop measurements
- History visualization with change details
- Input validation for all fields

#### 4. `lib/src/admin_activity_log.dart`

**Purpose**: UI for viewing admin activity logs

**Widgets:**

- `AdminActivityLogPage`: Main activity log screen
- Expandable log entries with full details

**Key Features:**

- Real-time activity log viewing
- Filter by action type
- Change tracking for updates
- Before/after value comparison
- Admin attribution for all actions

#### 5. `lib/src/crop_validation_dialog.dart`

**Purpose**: Validation warning/error dialogs for users

**Functions:**

- `showCropValidationDialog()`: Main dialog display function

**Widgets:**

- `_CropValidationDialog`: Detailed dialog content

**Features:**

- Confidence level color coding (green/orange/red)
- Top 3 crop suggestions
- Measurement match percentages
- Blocking UI for low confidence matches
- Allow/continue actions based on confidence

---

## 🔄 Integration Points

### Main.dart Changes

**Imports Added:**

```dart
part 'src/crop_data_models.dart';
part 'src/crop_service.dart';
part 'src/admin_crop_management.dart';
part 'src/admin_activity_log.dart';
part 'src/crop_validation_dialog.dart';
```

**New Global Functions:**

```dart
Future<UserRole> _getUserRole()        // Async user role check
Future<UserRole> getCurrentUserRole()  // Exposed API
```

### Home Page Changes

**State Variables Added:**

```dart
late Future<List<CropProfile>> _cropsFuture;
List<CropProfile> _availableCrops = [];
CropProfile? _selectedCropProfile;
late Future<UserRole> _userRoleFuture;
```

**InitState Updates:**

```dart
_cropsFuture = CropService.fetchAllCrops()...
_userRoleFuture = _getUserRole()
```

**Build Method Updates:**

```dart
// Dynamic tab construction based on user role
final isAdmin = roleSnapshot.data == UserRole.admin;
final adminTabs = isAdmin ? [...] : <Widget>[];
final allTabs = [...baseTabs, ...adminTabs];
```

**Method Updates:**

1. `_analyzeLeafImage()`: Now uses `_selectedCropProfile` instead of hardcoded crop keys
2. `_estimateLeafMeasurements()`: Accepts `CropProfile` instead of string
3. `_saveScanReport()`: Added validation logic before saving
4. `_buildCropSelectorStep()`: Dynamic UI loading crops from database
5. `_buildMorphologyScannerStep()`: Uses dynamic crop name

**New Methods:**

- `_buildCropSelectionCard()`: Card UI for crop selection
- `_buildCropInfoRow()`: Info row for crop details
- `_buildBottomNav()`: Updated to include admin tabs
- `_getUserRole()`: Helper to get user role

---

## 🧮 Validation Algorithm

### Weighted Scoring System

Each measurement contributes to the final match percentage:

```
Total Score = (Length × 0.25) + (Width × 0.25) +
              (Perimeter × 0.15) + (AspectRatio × 0.15) +
              (Hue × 0.10) + (SPAD × 0.10)

Match % = Total Score × 100
```

### Similarity Calculation

For each metric:

1. Calculate percentage difference from standard
2. Compare against tolerance threshold
3. Return similarity score (0.0 to 1.0)

```dart
double _calculateSimilarity({
  required double actual,
  required double standard,
  required double tolerance,
}) {
  if (standard == 0) return 0.0;

  final difference = (actual - standard).abs();
  final allowedDifference = (standard * tolerance) / 100;

  if (difference <= allowedDifference) {
    return 1.0;  // Perfect match within tolerance
  }

  // Gradual decrease outside tolerance
  final exceedance = difference - allowedDifference;
  final penaltyFactor = 1.0 - (exceedance / standard);
  return max(0.0, penaltyFactor);
}
```

### Confidence Level Determination

```
if (matchPercentage >= 80.0)
  → ConfidenceLevel.high → Allow save immediately

else if (matchPercentage >= 50.0)
  → ConfidenceLevel.medium → Show dialog, allow user choice

else (matchPercentage < 50.0)
  → ConfidenceLevel.low → Block save, require crop change
```

---

## 🗄️ Database Integration

### Supabase Schema

**Tables:**

- `florascan.crop_profiles`: Crop reference data
- `florascan.admin_activity_logs`: Admin action audit trail
- `florascan.crop_history`: Crop modification timeline

**RLS Policies:**

- Crops: Read for all, write/update/delete for admins only
- Activity Logs: Read for admins, write for system
- History: Read for admins, write for system

### Query Patterns

**Fetch All Crops:**

```dart
await supabase
    .schema('florascan')
    .from('crop_profiles')
    .select()
    .order('crop_name')
```

**Insert Crop:**

```dart
await supabase
    .schema('florascan')
    .from('crop_profiles')
    .insert(cropData.toJson())
```

**Fetch Activity Logs:**

```dart
await supabase
    .schema('florascan')
    .from('admin_activity_logs')
    .select()
    .eq('crop_name', cropName)
    .order('timestamp', ascending: false)
    .limit(limit)
```

---

## 🔐 Security Implementation

### Role-Based Access Control

```dart
// Check user role at runtime
Future<UserRole> _getUserRole() async {
  final user = supabase.auth.currentUser;
  final role = user?.userMetadata?['role'] as String?;
  return role == 'admin' ? UserRole.admin : UserRole.regular;
}

// Conditionally show UI
if (roleSnapshot.data == UserRole.admin) {
  // Show admin tabs
}
```

### Audit Trail Design

Every admin action is logged with:

- Admin ID and name
- Action type (created/updated/deleted)
- Timestamp
- Crop name
- Full change details (for updates)
- Previous and new values

This allows complete traceability and accountability.

### RLS Policies

Database enforces:

1. Regular users can read crops but not modify
2. Admins can create/edit/delete crops
3. Activity logs only visible to admins
4. All operations verified at database level

---

## 🧪 Testing Recommendations

### Unit Tests

**For CropService:**

```dart
// Test similarity calculations
test('calculateSimilarity returns 1.0 within tolerance', () {
  expect(CropService._calculateSimilarity(
    actual: 15.0,
    standard: 15.0,
    tolerance: 15.0,
  ), equals(1.0));
});

// Test validation orchestration
test('validateScannedLeaf returns correct confidence', () async {
  // Create test crops
  // Call validateScannedLeaf
  // Assert confidence levels
});
```

**For Validation Logic:**

```dart
test('High match gives high confidence', () {
  // Test with measurements very similar to crop
  expect(result.confidenceLevel, ConfidenceLevel.high);
});

test('Low match blocks saving', () {
  // Test with very different measurements
  expect(result.isPassed, false);
});
```

### Integration Tests

```dart
test('Admin can create and delete crop', () async {
  // Login as admin
  // Create crop
  // Verify in database
  // Delete crop
  // Verify deletion
});

test('Regular user cannot see admin tabs', () async {
  // Login as regular user
  // Verify admin tabs not visible
});
```

### Manual Testing Checklist

- [ ] Admin can add crops
- [ ] Crops appear in crop selector immediately
- [ ] Validation works for high/medium/low confidence
- [ ] Activity log records all actions
- [ ] Crop history shows changes
- [ ] Regular users can't see admin tabs
- [ ] Regular users can't access crop management
- [ ] Deleted crops don't appear in selector
- [ ] Edited crop measurements are used in validation

---

## 🔧 Customization Guide

### Adjusting Validation Thresholds

Edit `lib/src/crop_service.dart`:

```dart
class CropService {
  static const double highConfidenceThreshold = 80.0;  // Increase to 85 for stricter
  static const double mediumConfidenceThreshold = 50.0; // Decrease to 40 for looser

  static const double lengthTolerance = 15.0;  // Adjust in percentage
  static const double widthTolerance = 15.0;
  // ... etc
}
```

### Adding New Metrics

To add a new measurement (e.g., leaf thickness):

1. Add field to `CropProfile`:

```dart
final double standardLeafThicknessMm;
```

2. Update UI forms to input the field

3. Add to validation calculation:

```dart
// Add to _calculateMatchPercentage
final thicknessMatch = _calculateSimilarity(...);
scores.add(thicknessMatch * 0.05); // Add 5% weight
```

4. Update weighting in other metrics

5. Run validation tests

### Custom Color Ranges

Update hue ranges in `_getHueRangeLow/High()`:

```dart
static double _getHueRangeLow(String colorName) {
  const colorRanges = {
    'Dark Green': 90.0,
    'Custom Color': 120.0,  // Add new color
    // ...
  };
  return colorRanges[colorName] ?? 90.0;
}
```

### Changing UI Colors

Update in `home_page.dart`:

```dart
const kGreenDark = Color(0xFF1B5E20);   // Modify colors
const kGreenMid = Color(0xFF2E7D32);
// ... etc
```

---

## 📊 Performance Considerations

### Database Queries

**Optimization:**

- Crops list uses ORDER BY index (indexed on crop_name)
- Activity logs use timestamp descending (indexed)
- History uses crop_id (foreign key indexed)

**Pagination:**
Not currently implemented but easy to add:

```dart
.range(page * limit, (page + 1) * limit)
```

### UI Performance

- FutureBuilder loads data asynchronously
- Crops list uses ListView (virtual scrolling)
- Activity log expandable tiles prevent building all details upfront

### Caching

Current implementation refetches data each time:

- To add caching, store in State variables
- Invalidate on changes
- Consider `Provider` or `Riverpod` for production

---

## 🚀 Deployment Checklist

- [ ] Database tables created with correct schema
- [ ] RLS policies configured and tested
- [ ] All indexes created for performance
- [ ] Admin users have role in metadata
- [ ] Initial crops seeded (cucumber, coffee)
- [ ] App rebuilt for release
- [ ] Tested on real devices
- [ ] Admin features verified working
- [ ] Activity log tested for correct entries
- [ ] Validation tested with various measurements
- [ ] Browser console cleared of errors
- [ ] Network tab shows successful API calls

---

## 📚 Code Quality

### Lint Issues

- All code passes Flutter analyzer
- No unused imports
- Consistent naming conventions
- Comments on complex logic

### Best Practices

- Immutable models with copyWith
- Async/await for database calls
- Proper error handling with try/catch
- Input validation before database operations
- Secure storage for sensitive data

---

## 🔗 Dependency Analysis

**External Packages Used:**

- supabase_flutter: Database and auth
- camera: Leaf scanning
- flutter_blue_plus: Bluetooth SPAD meter
- flutter_secure_storage: Secure local storage

**Internal Dependencies:**

- CropService used by home_page.dart
- CropValidationDialog used by \_saveScanReport()
- Admin pages instantiated in build() method

---

## 🐛 Known Issues & Limitations

### Current Limitations

1. **No offline mode**: Crops must be fetched from Supabase
2. **No real-time sync**: Activity logs won't update until refresh
3. **No batch operations**: Can only add/edit one crop at a time
4. **Limited validation**: Doesn't use image recognition for hue

### Future Improvements

1. Offline-first sync with local cache
2. WebSocket updates for real-time logs
3. Bulk crop import/export
4. ML-based color detection
5. Mobile app performance optimization

---

## 📞 Debugging

### Common Issues

**Issue: Crops not loading**

```
Solution: Check Supabase connection, verify schema exists
```

**Issue: Validation always high confidence**

```
Solution: Check if crop measurements are too broad, reduce tolerances
```

**Issue: Activity log not updating**

```
Solution: Verify RLS policies allow read, check browser console for errors
```

### Debug Logging

Add to `crop_service.dart`:

```dart
debugPrint('Crops loaded: ${crops.length}');
debugPrint('Validation match: ${result.matchPercentage}%');
```

---

## 📖 References

- [Supabase Flutter Docs](https://supabase.com/docs/reference/dart)
- [Flutter Widgets Catalog](https://flutter.dev/docs/development/ui/widgets)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)

---

**Document Version**: 1.0.0
**Last Updated**: May 31, 2026
**Maintainer**: Development Team
