part of '../main.dart';

// ==================== HOME PAGE / MAIN APP TABS ====================
class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.onSignOut,
    required this.onThemeChanged,
    required this.isDarkMode,
  });

  final String title;
  final Future<void> Function() onSignOut;
  final Function(bool) onThemeChanged;
  final bool isDarkMode;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _leafNameController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final Map<DeviceIdentifier, BluetoothDevice> _foundDevices = {};

  // Camera-related variables
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCameraActive = false;

  int _selectedIndex = 0;
  bool _isScanning = false;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected'; // ignore: unused_field
  int? _chlorophyllValue;
  final List<LeafScanReport> _reports = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // Leaf identification and analysis variables
  bool _isAnalyzing = false;
  bool _fieldsLocked = false;
  String? _capturedImagePath;

  // Extended morphology metrics (populated after scan)
  double? _perimeterCm;
  double? _areaCm2;
  double? _aspectRatio;
  double? _hsvGreenHue;

  // Pre-scan crop selection state
  String? _selectedCrop; // ignore: unused_field
  bool _showCropSelector = true;
  late Future<List<CropProfile>> _cropsFuture;
  List<CropProfile> _availableCrops = [];
  CropProfile? _selectedCropProfile;

  // Save success notice below scanner frame
  bool _showSaveSuccess = false;

  // User role for admin features
  late Future<UserRole> _userRoleFuture;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _initializeCamera();
    _cropsFuture = CropService.fetchCropsForScanning().then((crops) {
      if (mounted) {
        setState(() => _availableCrops = crops);
      }
      return crops;
    });
    _userRoleFuture = _getUserRole();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _leafNameController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _cameraController?.dispose();
    _saveReports();
    super.dispose();
  }

  /// Gets the user's role
  Future<UserRole> _getUserRole() async {
    return getCurrentUserRole();
  }

  /// Generates user-specific storage key for leaf scan reports
  String _getUserReportsKey() {
    final userId = supabase.auth.currentUser?.id ?? 'unknown';
    return 'leaf_scan_reports_$userId';
  }

  /// Saves all leaf scan reports to secure storage (user-specific)
  Future<void> _saveReports() async {
    final jsonList = _reports.map((r) => r.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await appSecureStorage.write(key: _getUserReportsKey(), value: jsonString);
  }

  /// Loads all leaf scan reports from secure storage (user-specific)
  Future<void> _loadReports() async {
    try {
      final jsonString = await appSecureStorage.read(key: _getUserReportsKey());
      if (jsonString != null && jsonString.isNotEmpty) {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        if (mounted) {
          setState(() {
            _reports.clear();
            _reports.addAll(
              jsonList.map(
                (json) => LeafScanReport.fromJson(json as Map<String, dynamic>),
              ),
            );
          });
        }
      }
    } catch (_) {
      // Silently handle error loading reports
    }
  }

  /// Starts Bluetooth scan to find nearby leaf measurement devices
  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _foundDevices.clear();
      _connectionStatus = 'Scanning for SPAD-style devices...';
    });

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        for (var result in results) {
          final device = result.device;
          if (device.platformName.isNotEmpty ||
              result.advertisementData.advName.isNotEmpty) {
            _foundDevices[device.remoteId] = device;
          }
        }
        _connectionStatus = _foundDevices.isEmpty
            ? 'Scanning... no matching devices yet.'
            : 'Select a device from the list below.';
      });
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    } catch (error) {
      setState(() => _connectionStatus = 'Bluetooth scan failed: $error');
    } finally {
      setState(() {
        _isScanning = false;
        if (_foundDevices.isEmpty) {
          _connectionStatus = 'No Chlorophyll meter found. Please try again.';
        }
      });
    }
  }

  /// Connects to a selected Bluetooth device and discovers its services
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      final services = await device.discoverServices();
      BluetoothCharacteristic? readableCharacteristic;

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.read) {
            readableCharacteristic = characteristic;
            break;
          }
        }
        if (readableCharacteristic != null) break;
      }

      setState(() {
        _isConnected = true;
        _connectionStatus =
            'Connected to ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}';
      });
    } catch (error) {
      setState(() {
        _isConnected = false;
        _connectionStatus = 'Device connection failed: $error';
      });
    }
  }

  /// Initializes the camera for leaf scanning
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty && mounted) {
        final camera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
        await _setupCamera(camera);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  /// Sets up the camera controller
  Future<void> _setupCamera(CameraDescription camera) async {
    try {
      final oldController = _cameraController;
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await oldController?.dispose();

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _isCameraActive = false;
        });
      }
      debugPrint('Error setting up camera: $e');
    }
  }

  /// Opens camera to scan the leaf
  Future<void> _openCameraToScanLeaf() async {
    if (_isCameraActive &&
        _isCameraInitialized &&
        _cameraController?.value.isInitialized == true) {
      return;
    }

    final currentStatus = await Permission.camera.status;
    final cameraStatus = currentStatus.isGranted
        ? currentStatus
        : await Permission.camera.request();

    if (!cameraStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to scan leaves'),
          ),
        );
      }
      return;
    }

    if (!_isCameraInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      await _initializeCamera();
    }

    if (!mounted) return;

    if (!_isCameraInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera is not ready')));
      }
      return;
    }

    setState(() {
      _isCameraActive = true;
      _isAnalyzing = false;
      _capturedImagePath = null;
      _showSaveSuccess = false;
      _connectionStatus = 'Position a leaf in frame.';
    });
  }

  /// Stops the camera preview
  void _stopCamera() {
    if (!_isCameraActive || !mounted) return;
    setState(() {
      _isCameraActive = false;
    });
  }

  /// Clears all extended morphology metrics
  void _clearMorphologyMetrics() {
    _areaCm2 = null;
    _perimeterCm = null;
    _aspectRatio = null;
    _hsvGreenHue = null;
  }

  /// Captures an image from the camera for leaf analysis
  Future<void> _captureLeafImage() async {
    if (_isAnalyzing) return;

    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }

      final capturedImage = await _cameraController!.takePicture();

      if (!mounted) return;
      setState(() {
        _isAnalyzing = true;
        _capturedImagePath = capturedImage.path;
        _leafNameController.clear();
        _lengthController.clear();
        _widthController.clear();
        _chlorophyllValue = null;
        _fieldsLocked = false;
        _showSaveSuccess = false;
        _clearMorphologyMetrics();
        _connectionStatus = 'Analyzing leaf...';
      });

      final analysis = await _analyzeLeafImage(capturedImage.path);

      if (analysis == null) {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _connectionStatus =
                'No leaf detected. Ensure the leaf fills the frame and use a matte blue or black card as background.';
            _fieldsLocked = false;
            _chlorophyllValue = null;
            _leafNameController.clear();
            _lengthController.clear();
            _widthController.clear();
            _clearMorphologyMetrics();
            _isCameraActive = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️  No leaf detected. Place a matte blue or black card behind the leaf and try again.',
              ),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _leafNameController.text = analysis.leafType;
          _lengthController.text = analysis.lengthCm.toStringAsFixed(1);
          _widthController.text = analysis.widthCm.toStringAsFixed(1);
          _areaCm2 = analysis.areaCm2;
          _perimeterCm = analysis.perimeterCm;
          _aspectRatio = analysis.aspectRatio;
          _hsvGreenHue = analysis.hsvGreenHue;
          _chlorophyllValue = null;
          _fieldsLocked = true;
          _isAnalyzing = false;
          _connectionStatus = 'Leaf scanned successfully!';
          _isCameraActive = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${analysis.leafType} scanned. L: ${analysis.lengthCm}cm, W: ${analysis.widthCm}cm',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing image: $e');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error capturing image: $e')));
      }
    }
  }

  /// Generates fertilizer recommendation based on chlorophyll level
  String _fertilizerRecommendation(int value) {
    if (value >= 55) return 'Healthy leaf - no extra fertilizer required.';
    if (value >= 40) {
      return 'Moderate chlorophyll - use balanced NPK fertilizer.';
    }
    return 'Low chlorophyll - apply nitrogen-rich fertilizer.';
  }

  /// Determines leaf health status based on chlorophyll
  String _leafHealthStatus(int value) {
    if (value >= 55) return 'Healthy';
    if (value >= 40) return 'Mild stress';
    return 'Needs attention';
  }

  /// Analyzes the captured frame for leaf morphology using the pre-selected crop type.
  Future<_LeafScanAnalysis?> _analyzeLeafImage(String imagePath) async {
    try {
      if (imagePath.isEmpty || _selectedCropProfile == null) return null;

      final capturedProfile = await _createLeafProfileFromFile(imagePath);
      await Future<void>.delayed(const Duration(milliseconds: 650));

      if (!capturedProfile.hasLeafCandidate) {
        return null;
      }

      final measurements = _estimateLeafMeasurements(
        _selectedCropProfile!,
        capturedProfile,
      );

      return _LeafScanAnalysis(
        leafType: _selectedCropProfile!.cropName,
        lengthCm: measurements['length']!,
        widthCm: measurements['width']!,
        areaCm2: measurements['areaCm2']!,
        perimeterCm: measurements['perimeterCm']!,
        aspectRatio: measurements['aspectRatio']!,
        hsvGreenHue: measurements['hsvGreenHue']!,
      );
    } catch (e) {
      debugPrint('Error analyzing leaf: $e');
      return null;
    }
  }

  Future<_LeafImageProfile> _createLeafProfileFromFile(String imagePath) async {
    return _createLeafProfile(await File(imagePath).readAsBytes());
  }

  Future<_LeafImageProfile> _createLeafProfile(List<int> imageBytes) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(imageBytes),
      targetWidth: 180,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pixelData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (pixelData == null) return _LeafImageProfile.empty();

    final width = image.width;
    final height = image.height;
    final bytes = pixelData.buffer.asUint8List();
    final hueBins = List<double>.filled(12, 0);

    var leafPixels = 0;
    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    var hueTotal = 0.0;
    var saturationTotal = 0.0;
    var valueTotal = 0.0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = (y * width + x) * 4;
        final r = bytes[index];
        final g = bytes[index + 1];
        final b = bytes[index + 2];
        final hsv = _rgbToHsv(r, g, b);
        final hue = hsv[0];
        final saturation = hsv[1];
        final value = hsv[2];

        final isGreenLeafPixel =
            hue >= 50 &&
            hue <= 175 &&
            saturation >= 0.16 &&
            value >= 0.10 &&
            g >= r * 0.88 &&
            g >= b * 0.70;

        if (!isGreenLeafPixel) continue;

        leafPixels++;
        minX = min(minX, x);
        minY = min(minY, y);
        maxX = max(maxX, x);
        maxY = max(maxY, y);
        hueTotal += hue;
        saturationTotal += saturation;
        valueTotal += value;

        final bin = (((hue - 50) / 125) * hueBins.length)
            .floor()
            .clamp(0, hueBins.length - 1)
            .toInt();
        hueBins[bin] += 1;
      }
    }

    if (leafPixels == 0) return _LeafImageProfile.empty();

    final bboxWidth = maxX - minX + 1;
    final bboxHeight = maxY - minY + 1;
    final bboxArea = bboxWidth * bboxHeight;
    final totalPixels = width * height;
    final longSide = max(bboxWidth, bboxHeight).toDouble();
    final shortSide = max(1, min(bboxWidth, bboxHeight)).toDouble();

    for (var i = 0; i < hueBins.length; i++) {
      hueBins[i] = hueBins[i] / leafPixels;
    }

    return _LeafImageProfile(
      leafPixelCount: leafPixels,
      greenCoverage: leafPixels / totalPixels,
      bboxCoverage: bboxArea / totalPixels,
      fillRatio: leafPixels / bboxArea,
      longToShortRatio: longSide / shortSide,
      meanHue: hueTotal / leafPixels,
      meanSaturation: saturationTotal / leafPixels,
      meanValue: valueTotal / leafPixels,
      hueHistogram: hueBins,
    );
  }

  List<double> _rgbToHsv(int red, int green, int blue) {
    final r = red / 255.0;
    final g = green / 255.0;
    final b = blue / 255.0;
    final maxValue = max(r, max(g, b));
    final minValue = min(r, min(g, b));
    final delta = maxValue - minValue;

    var hue = 0.0;
    if (delta != 0) {
      if (maxValue == r) {
        hue = 60 * (((g - b) / delta) % 6);
      } else if (maxValue == g) {
        hue = 60 * (((b - r) / delta) + 2);
      } else {
        hue = 60 * (((r - g) / delta) + 4);
      }
    }
    if (hue < 0) hue += 360;

    final saturation = maxValue == 0 ? 0.0 : delta / maxValue;
    return [hue, saturation, maxValue];
  }

  Map<String, double> _estimateLeafMeasurements(
    CropProfile cropProfile,
    _LeafImageProfile profile,
  ) {
    final sizeSignal = ((profile.bboxCoverage - 0.05) / 0.45)
        .clamp(0.0, 1.0)
        .toDouble();
    final ratioSignal = ((profile.longToShortRatio - 1.0) / 2.8)
        .clamp(0.0, 1.0)
        .toDouble();
    final signal = (sizeSignal * 0.45 + ratioSignal * 0.55)
        .clamp(0.0, 1.0)
        .toDouble();

    // Use the standard measurements from the crop profile
    // Scale based on the detected signal
    final minLength = cropProfile.standardLeafLengthCm * 0.7;
    final maxLength = cropProfile.standardLeafLengthCm * 1.3;
    final length = minLength + (signal * (maxLength - minLength));

    final minWidth = cropProfile.standardLeafWidthCm * 0.7;
    final maxWidth = cropProfile.standardLeafWidthCm * 1.3;
    final width = minWidth + (signal * (maxWidth - minWidth));

    final areaCm2 = double.parse((pi / 4 * length * width).toStringAsFixed(2));
    final a = length / 2;
    final b = width / 2;
    final h = pow(a - b, 2) / pow(a + b, 2);
    final perimeterCm = double.parse(
      (pi * (a + b) * (1 + (3 * h) / (10 + sqrt(4 - 3 * h)))).toStringAsFixed(
        2,
      ),
    );
    final aspectRatio = double.parse(
      (width > 0 ? length / width : 0).toStringAsFixed(2),
    );
    final hsvGreenHue = double.parse(profile.meanHue.toStringAsFixed(1));

    return {
      'length': double.parse(length.toStringAsFixed(1)),
      'width': double.parse(width.toStringAsFixed(1)),
      'areaCm2': areaCm2,
      'perimeterCm': perimeterCm,
      'aspectRatio': aspectRatio,
      'hsvGreenHue': hsvGreenHue,
    };
  }

  // ==================== SAVE SCAN REPORT WITH VALIDATION ====================
  Future<void> _saveScanReport() async {
    // Capture before any await to avoid use_build_context_synchronously lint.
    final messenger = ScaffoldMessenger.of(context);

    final name = _leafNameController.text.trim();
    final lengthCm = double.tryParse(_lengthController.text) ?? 0;
    final widthCm = double.tryParse(_widthController.text) ?? 0;
    final chlorophyll = _chlorophyllValue;

    if (name.isEmpty ||
        lengthCm <= 0 ||
        widthCm <= 0 ||
        _selectedCropProfile == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please scan a supported leaf first.')),
      );
      return;
    }

    // ========== CROP VALIDATION ==========
    // Perform validation against selected crop
    final validationResult = await CropService.validateScannedLeaf(
      selectedCrop: _selectedCropProfile!,
      scannedLengthCm: lengthCm,
      scannedWidthCm: widthCm,
      scannedPerimeterCm: _perimeterCm ?? 0,
      scannedAspectRatio: _aspectRatio ?? 0,
      scannedHue: _hsvGreenHue ?? 0,
      scannedSpad: chlorophyll,
      allCrops: _availableCrops,
    );

    // Check confidence level and act accordingly
    if (validationResult.confidenceLevel == ConfidenceLevel.low) {
      // LOW CONFIDENCE: Prevent saving, require user to select correct crop
      if (!mounted) return;

      final shouldContinue = await showCropValidationDialog(
        context,
        validationResult,
      );

      // Guard after the second await before touching context/messenger.
      if (!mounted) return;
      if (!shouldContinue) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Scan cancelled. Please select the correct crop.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else if (validationResult.confidenceLevel == ConfidenceLevel.medium) {
      // MEDIUM CONFIDENCE: Show warning dialog, allow user to continue or cancel
      if (!mounted) return;

      final shouldContinue = await showCropValidationDialog(
        context,
        validationResult,
      );

      // Guard after the second await before touching context/messenger.
      if (!mounted) return;
      if (!shouldContinue) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Scan cancelled by user.')),
        );
        return;
      }
    }
    // HIGH CONFIDENCE: Continue without dialog

    final areaCm2 =
        _areaCm2 ??
        double.parse((pi / 4 * lengthCm * widthCm).toStringAsFixed(2));

    // Build the full report including all morphology fields
    final report = LeafScanReport(
      leafName: name,
      timestamp: DateTime.now(),
      lengthCm: lengthCm,
      widthCm: widthCm,
      areaCm2: areaCm2,
      chlorophyllValue: chlorophyll,
      status: chlorophyll == null
          ? 'Leaf scanned'
          : _leafHealthStatus(chlorophyll),
      fertilizer: chlorophyll == null
          ? 'Chlorophyll sensor not connected yet.'
          : _fertilizerRecommendation(chlorophyll),
      perimeterCm: _perimeterCm,
      aspectRatio: _aspectRatio,
      hsvGreenHue: _hsvGreenHue,
    );

    // ── Step 1: Save locally & update UI immediately ──
    setState(() {
      _reports.insert(0, report);
      _showSaveSuccess = true;
      _fieldsLocked = false;
      _leafNameController.clear();
      _lengthController.clear();
      _widthController.clear();
      _chlorophyllValue = null;
      _clearMorphologyMetrics();
      _connectionStatus = 'Saved!';
    });
    await _saveReports();

    // Auto-hide the success notice after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSaveSuccess = false);
    });

    // ── Step 2: Attempt cloud upload (non-blocking) ──
    try {
      final scanData = <String, dynamic>{
        'leaf_classification': name,
        'leaf_size_cm2': areaCm2,
        'user_id':
            supabase.auth.currentUser?.id ??
            '00000000-0000-0000-0000-000000000000',
      };

      if (chlorophyll != null) {
        scanData.addAll({
          'chlorophyll_content': chlorophyll,
          'raw_red_signal': 0,
          'raw_nir_signal': 0,
        });
      }

      await supabase.from('leaf_scans').insert(scanData);
    } catch (e) {
      // Cloud upload failed, but local save already succeeded
      debugPrint('Cloud upload failed (local save OK): $e');
    }
  }

  /// Updates selected tab index to switch between different app screens
  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 2) {
        _showCropSelector = true;
        _selectedCrop = null;
      }
    });
    if (index != 2) {
      _stopCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserRole>(
      future: _userRoleFuture,
      builder: (context, roleSnapshot) {
        final isAdmin = roleSnapshot.data == UserRole.admin;

        final baseTabs = [
          _buildDashboardTab(),
          _buildHistoryTab(),
          _buildScanTab(),
          _buildReportsTab(),
          _buildProfileTab(),
        ];

        final adminTabs = isAdmin
            ? [
                AdminCropManagementPage(
                  onCropChanged: () {
                    setState(() {
                      _cropsFuture = CropService.fetchCropsForScanning().then((
                        crops,
                      ) {
                        if (mounted) {
                          setState(() => _availableCrops = crops);
                        }
                        return crops;
                      });
                    });
                  },
                ),
                const AdminActivityLogPage(),
              ]
            : <Widget>[];

        final allTabs = [...baseTabs, ...adminTabs];

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7F5),
          body: allTabs[_selectedIndex],
          bottomNavigationBar: _buildBottomNav(isAdmin, baseTabs.length),
        );
      },
    );
  }

  /// Updates the bottom nav to include admin items for admin users
  Widget _buildBottomNav(bool isAdmin, int baseTabCount) {
    // Base items (always 5)
    final baseItems = [
      {'icon': Icons.home_filled, 'label': 'Dashboard'},
      {'icon': Icons.history, 'label': 'History'},
      {'icon': Icons.qr_code_scanner, 'label': ''},
      {'icon': Icons.bar_chart_rounded, 'label': 'Reports'},
      {'icon': Icons.person_outline, 'label': 'Profile'},
    ];

    // Admin items only append to the right
    final adminItems = isAdmin
        ? [
            {'icon': Icons.local_florist, 'label': 'Crops'},
            {'icon': Icons.assignment_outlined, 'label': 'Activity'},
          ]
        : <Map<String, dynamic>>[];

    final allItems = [...baseItems, ...adminItems];
    final scannerIndex = 2;

    return _selectedIndex == scannerIndex
        ? const SizedBox.shrink()
        : Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: List.generate(allItems.length, (i) {
                final isCenter = i == scannerIndex;
                final isSelected = _selectedIndex == i;
                final icon = allItems[i]['icon'] as IconData;
                final label = allItems[i]['label'] as String;

                if (isCenter) {
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _selectTab(i),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: kGreenMid,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: kGreenMid.withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  );
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectTab(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: isSelected
                              ? kGreenMid
                              : const Color(0xFFB0BEC5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? kGreenMid
                                : const Color(0xFFB0BEC5),
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
  }

  // ==================== DASHBOARD TAB ====================
  Widget _buildDashboardTab() {
    final user = supabase.auth.currentUser;
    final username =
        user?.userMetadata?['username'] as String? ??
        user?.email?.split('@').first ??
        'Researcher';
    final latestReport = _reports.isNotEmpty ? _reports.first : null;
    final latestChlorophyll = latestReport?.chlorophyllValue;
    final recentReports = _reports.take(3).toList();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: kGreenMid.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Image.asset(
                            'assets/images/FloraScan - Logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const Icon(
                              Icons.eco,
                              color: kGreenMid,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'FLORA SCAN',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: kGreenDark,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: kTextMid,
                            size: 22,
                          ),
                          onPressed: () => _showSettingsBottomSheet(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Welcome, ${_capitalize(username)}!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _selectTab(2),
                    child: _dashCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Scan',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: kTextDark,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  latestChlorophyll != null
                                      ? '$latestChlorophyll'
                                      : '--',
                                  style: const TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w800,
                                    color: kTextDark,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Chl Index',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: kTextMid,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  latestReport != null
                                      ? 'Last Updated ${_formatDate(latestReport.timestamp)}'
                                      : 'No scan yet',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: kTextLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 56,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.devices_other,
                              color: kTextMid,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _dashCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Activity',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (recentReports.isEmpty)
                          const Text(
                            'No activity yet. Save a scan to build history.',
                            style: TextStyle(fontSize: 13, color: kTextLight),
                          )
                        else
                          ...recentReports.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 5.0),
                              child: Text(
                                '${r.leafName}  |  ${_formatDate(r.timestamp)}  |  Chl Index: ${_chlorophyllLabel(r)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextMid,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _dashCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device Status',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _isConnected
                                    ? kGreenPale
                                    : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.devices,
                                color: _isConnected ? kGreenMid : kTextMid,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Device ID: ${_isConnected ? 'Er-F-IOT-001' : 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kTextMid,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Battery: ${_isConnected ? '95%' : '--'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kTextMid,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text(
                                      'Connection: ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: kTextMid,
                                      ),
                                    ),
                                    Text(
                                      _isConnected ? 'Stable' : 'Not Connected',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _isConnected
                                            ? kGreenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              'Scan History',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
          ),
          Expanded(
            child: _reports.isEmpty
                ? const Center(
                    child: Text(
                      'No scans yet. Start scanning to see your history.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTextLight, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final r = _reports[index];
                      final hasChlorophyll = r.chlorophyllValue != null;
                      final statusColor = r.status == 'Healthy'
                          ? kGreenMid
                          : r.status == 'Leaf scanned'
                          ? kTextLight
                          : Colors.orange;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  r.leafName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: kTextDark,
                                  ),
                                ),
                                Text(
                                  _formatTime(r.timestamp),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: kTextLight,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: kDivider),
                            const SizedBox(height: 8),
                            _buildHistoryMetricsGrid(r),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: kDivider),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Chlorophyll Index',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: kTextMid,
                                  ),
                                ),
                                Text(
                                  _chlorophyllLabel(r),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: hasChlorophyll
                                        ? kGreenDark
                                        : kTextLight,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Status',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: kTextMid,
                                  ),
                                ),
                                Text(
                                  r.status,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryMetricsGrid(LeafScanReport r) {
    final metrics = <(String, String)>[
      ('Length', '${r.lengthCm} cm'),
      ('Width', '${r.widthCm} cm'),
      (
        'Proj. Area',
        r.areaCm2 > 0 ? '${r.areaCm2.toStringAsFixed(2)} cm²' : '--',
      ),
      (
        'Perimeter',
        r.perimeterCm != null
            ? '${r.perimeterCm!.toStringAsFixed(2)} cm'
            : '--',
      ),
      (
        'Aspect Ratio',
        r.aspectRatio != null ? r.aspectRatio!.toStringAsFixed(2) : '--',
      ),
      (
        'Hue (HSV)',
        r.hsvGreenHue != null ? '${r.hsvGreenHue!.toStringAsFixed(1)}°' : '--',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const colGap = 8.0;
        final colWidth = (constraints.maxWidth - colGap) / 2;
        return Wrap(
          spacing: colGap,
          runSpacing: 6,
          children: metrics.map((m) {
            final (label, value) = m;
            return SizedBox(
              width: colWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: kTextLight),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextDark,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ==================== SCAN TAB ====================
  Widget _buildScanTab() {
    return _showCropSelector
        ? _buildCropSelectorStep()
        : _buildMorphologyScannerStep();
  }

  // ==================== STEP 1: CROP SELECTOR ====================
  Widget _buildCropSelectorStep() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: kTextMid,
                  ),
                  onPressed: () => _selectTab(0),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22, color: kTextMid),
                  onPressed: () => _selectTab(0),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kGreenMid,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Step 1 of 2',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Select Crop',
                  style: TextStyle(
                    fontSize: 13,
                    color: kTextLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Crop Species',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the crop you are scanning to enable accurate leaf morphology analysis.',
                  style: TextStyle(
                    fontSize: 13,
                    color: kTextLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: FutureBuilder<List<CropProfile>>(
              future: _cropsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading crops: ${snapshot.error}'),
                  );
                }

                final crops = snapshot.data ?? [];

                if (crops.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.grass, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text(
                          'No crops available',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ask an administrator to add crops',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ListView.separated(
                    itemCount: crops.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final crop = crops[index];
                      return _buildCropSelectionCard(crop);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _selectedCropProfile != null
                    ? () {
                        setState(() {
                          _showCropSelector = false;
                          _leafNameController.clear();
                          _lengthController.clear();
                          _widthController.clear();
                          _capturedImagePath = null;
                          _fieldsLocked = false;
                          _showSaveSuccess = false;
                          _clearMorphologyMetrics();
                          _connectionStatus = 'Place leaf in frame.';
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) unawaited(_openCameraToScanLeaf());
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreenMid,
                  disabledBackgroundColor: const Color(0xFFD0D0D0),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a crop selection card
  Widget _buildCropSelectionCard(CropProfile crop) {
    final isSelected = _selectedCropProfile?.id == crop.id;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCropProfile = crop;
          _selectedCrop = crop.cropName;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? kGreenMid : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? kGreenPale : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    crop.cropName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: kGreenMid,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCropInfoRow('SPAD', '${crop.referenceSpadIndex}'),
            _buildCropInfoRow(
              'Leaf',
              '${crop.standardLeafLengthCm}×${crop.standardLeafWidthCm} cm',
            ),
            _buildCropInfoRow('Color', crop.standardLeafColor),
          ],
        ),
      ),
    );
  }

  /// Builds a crop info row for the selection card
  Widget _buildCropInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ==================== STEP 2: MORPHOLOGY SCANNER ====================
  Widget _buildMorphologyScannerStep() {
    final cropLabel = _selectedCropProfile?.cropName ?? 'Leaf';

    final bool isScannedSuccess = _fieldsLocked;
    final bool isAnalyzingNow = _isAnalyzing;
    final Color statusDotColor = isAnalyzingNow
        ? Colors.orange
        : isScannedSuccess
        ? kGreenAccent
        : kGreenAccent;
    final String statusText = isAnalyzingNow
        ? 'Analyzing...'
        : isScannedSuccess
        ? 'Leaf scanned successfully!'
        : _isCameraActive
        ? 'Place leaf in frame'
        : 'Ready to scan';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 12, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: kTextMid,
                  ),
                  onPressed: () => setState(() {
                    _showCropSelector = true;
                    _stopCamera();
                    _fieldsLocked = false;
                    _capturedImagePath = null;
                    _showSaveSuccess = false;
                    _leafNameController.clear();
                    _lengthController.clear();
                    _widthController.clear();
                    _clearMorphologyMetrics();
                    _connectionStatus = 'Disconnected';
                  }),
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kGreenMid,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Step 2 of 2',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: kGreenPale,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: kGreenMid,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _fieldsLocked = false;
                        _capturedImagePath = null;
                        _showSaveSuccess = false;
                        _leafNameController.clear();
                        _lengthController.clear();
                        _widthController.clear();
                        _clearMorphologyMetrics();
                        _connectionStatus = 'Place leaf in frame.';
                        _isAnalyzing = false;
                      });
                      unawaited(_openCameraToScanLeaf());
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Crop title ──
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              cropLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: kTextDark,
                letterSpacing: -0.5,
              ),
            ),
          ),

          // ── Status dot + text ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusDotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: isScannedSuccess ? kGreenMid : kTextMid,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Info banner (tight, no extra space below) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFB8D0FF), width: 1),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Color(0xFF3B72D6),
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Place a blue or black card behind the leaf to isolate it from the background before scanning.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF3B72D6),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Camera / scan frame — EXPANDED to fill available space ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildScannerFrame(),
            ),
          ),

          // ── "Successfully saved!" notice below the frame ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showSaveSuccess
                ? Padding(
                    key: const ValueKey('save_success'),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: kGreenPale,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: kGreenAccent.withValues(alpha: 0.6),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: kGreenMid,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Successfully saved!',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kGreenDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey('save_empty'), height: 6),
          ),

          const SizedBox(height: 6),

          // ── Metrics grid ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildNewMetricsGrid(),
          ),
          const SizedBox(height: 8),

          // ── BT devices list (if any found) ──
          if (_foundDevices.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: _foundDevices.values.map((device) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kGreenLight),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          device.platformName.isNotEmpty
                              ? device.platformName
                              : device.remoteId.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: _isConnected
                              ? null
                              : () => _connectToDevice(device),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Connect',
                            style: TextStyle(fontSize: 11, color: kGreenMid),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── Bottom action row: Scan BT | Capture | Save ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Row(
              children: [
                // Scan Chlorophyll Device
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _startScan,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kGreenMid, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.bluetooth_searching_rounded,
                            size: 18,
                            color: kGreenMid,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isScanning
                                ? 'Searching...'
                                : 'Scan Chlorophyll\nDevice',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: kGreenMid,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Center capture button
                GestureDetector(
                  onTap: _isAnalyzing
                      ? null
                      : (_isCameraActive
                            ? _captureLeafImage
                            : _openCameraToScanLeaf),
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: kGreenMid, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: kGreenMid.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isAnalyzing
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: kGreenMid,
                            ),
                          )
                        : const Icon(
                            Icons.crop_free_rounded,
                            color: kGreenMid,
                            size: 28,
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Save button
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _fieldsLocked ? _saveScanReport : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGreenMid,
                        disabledBackgroundColor: const Color(0xFFD0D0D0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.save_alt_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== METRICS GRID ====================
  Widget _buildNewMetricsGrid() {
    final lengthVal = _lengthController.text.isNotEmpty
        ? '${_lengthController.text} cm'
        : '- - - -';
    final widthVal = _widthController.text.isNotEmpty
        ? '${_widthController.text} cm'
        : '- - - -';
    final areaVal = _areaCm2 != null
        ? '${_areaCm2!.toStringAsFixed(2)} cm²'
        : '- - - -';
    final perimeterVal = _perimeterCm != null
        ? '${_perimeterCm!.toStringAsFixed(2)} cm'
        : '- - - -';
    final aspectVal = _aspectRatio != null
        ? '${_aspectRatio!.toStringAsFixed(2)} L/W'
        : '- - - -';
    final hueVal = _hsvGreenHue != null
        ? '${_hsvGreenHue!.toStringAsFixed(1)}°'
        : '- - - -';
    final chlorophyllVal = _chlorophyllValue != null
        ? '$_chlorophyllValue'
        : '- - - -';

    final leftCol = [
      ('Chlorophyll Index', chlorophyllVal),
      ('Length', lengthVal),
      ('Width', widthVal),
      ('Proj. Area', areaVal),
    ];

    final rightCol = [
      ('Perimeter', perimeterVal),
      ('Aspect Ratio', aspectVal),
      ('Hue (HSV Green)', hueVal),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: leftCol.map((item) {
              return _metricRow(item.$1, item.$2);
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rightCol.map((item) {
              return _metricRow(item.$1, item.$2);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 5,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                color: kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                color: value.contains('- -') ? kTextLight : kTextDark,
                fontWeight: value.contains('- -')
                    ? FontWeight.w400
                    : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SCANNER FRAME ====================
  // Frame now fills the full Expanded height — no more 0.72 cap.
  Widget _buildScannerFrame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth;
        // Use the full available height from the Expanded parent
        final frameHeight = constraints.maxHeight;
        final hasLiveCamera =
            _isCameraActive &&
            _isCameraInitialized &&
            _cameraController?.value.isInitialized == true;
        final frozenFramePath = _capturedImagePath;

        return SizedBox(
          width: frameWidth,
          height: frameHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasLiveCamera)
                  _buildCameraPreview()
                else if (frozenFramePath != null)
                  Image.file(
                    File(frozenFramePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF3A6F43)),
                  )
                else
                  Container(
                    color: const Color(0xFF2E7D32),
                    child: Center(
                      child: Icon(
                        Icons.eco,
                        size: 72,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                CustomPaint(painter: _CornerBracketPainter()),
                if (!hasLiveCamera && frozenFramePath == null)
                  CustomPaint(painter: _LeafGuidePainter()),
                if (_isAnalyzing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.42),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Analyzing leaf...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController;
    final previewSize = controller?.value.previewSize;

    if (controller == null || previewSize == null) {
      return const ColoredBox(color: Color(0xFF3A6F43));
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  // ==================== REPORTS TAB ====================
  Widget _buildReportsTab() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              'Reports',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
          ),
          Expanded(
            child: _reports.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        'No reports yet. Scan a leaf and save to see it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextLight, fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final r = _reports[index];
                      final hasChlorophyll = r.chlorophyllValue != null;
                      final statusColor = r.status == 'Healthy'
                          ? kGreenMid
                          : r.status == 'Leaf scanned'
                          ? kTextLight
                          : Colors.orange;
                      final fertilizerColor = hasChlorophyll
                          ? kGreenMid
                          : Colors.redAccent;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  r.leafName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: kTextDark,
                                  ),
                                ),
                                Text(
                                  _formatTime(r.timestamp),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: kTextLight,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1, color: kDivider),
                            const SizedBox(height: 10),
                            _buildReportMetricsGrid(r),
                            const SizedBox(height: 10),
                            const Divider(height: 1, color: kDivider),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Chlorophyll Index',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: kTextMid,
                                  ),
                                ),
                                Text(
                                  _chlorophyllLabel(r),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: hasChlorophyll
                                        ? kGreenDark
                                        : kTextLight,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Status',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: kTextMid,
                                  ),
                                ),
                                Text(
                                  r.status,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: hasChlorophyll
                                    ? kGreenPale
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: hasChlorophyll
                                      ? kGreenAccent.withValues(alpha: 0.5)
                                      : Colors.redAccent.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    hasChlorophyll
                                        ? Icons.eco_outlined
                                        : Icons.bluetooth_disabled_outlined,
                                    size: 14,
                                    color: fertilizerColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      r.fertilizer,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: fertilizerColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportMetricsGrid(LeafScanReport r) {
    final metrics = [
      (Icons.height_rounded, 'Length (cm)', '${r.lengthCm} cm'),
      (Icons.width_normal_rounded, 'Width (cm)', '${r.widthCm} cm'),
      (
        Icons.crop_free_rounded,
        'Proj. Area',
        r.areaCm2 > 0 ? '${r.areaCm2.toStringAsFixed(2)} cm²' : '--',
      ),
      (
        Icons.rounded_corner_rounded,
        'Perimeter',
        r.perimeterCm != null
            ? '${r.perimeterCm!.toStringAsFixed(2)} cm'
            : '--',
      ),
      (
        Icons.aspect_ratio_rounded,
        'Aspect Ratio',
        r.aspectRatio != null ? r.aspectRatio!.toStringAsFixed(2) : '--',
      ),
      (
        Icons.color_lens_outlined,
        'Hue (HSV)',
        r.hsvGreenHue != null ? '${r.hsvGreenHue!.toStringAsFixed(1)}°' : '--',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics.map((m) {
            final (icon, label, value) = m;
            return SizedBox(
              width: tileWidth,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: kGreenPale,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 13, color: kGreenMid),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kTextDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        color: kTextLight,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ==================== PROFILE TAB ====================
  Widget _buildProfileTab() {
    final user = supabase.auth.currentUser;
    final username =
        user?.userMetadata?['username'] as String? ??
        user?.email?.split('@').first ??
        'User';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: kGreenPale,
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: kGreenDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _capitalize(username),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(fontSize: 13, color: kTextLight),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async => await widget.onSignOut(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreenMid,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Sign out',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SETTINGS BOTTOM SHEET ====================
  void _showSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: kTextDark,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: kTextMid,
                              size: 24,
                            ),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSettingsSection(
                        title: 'Theme & Display',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.dark_mode_outlined,
                            title: 'Dark Mode',
                            trailing: Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: widget.isDarkMode,
                                onChanged: (value) {
                                  widget.onThemeChanged(value);
                                  Navigator.pop(context);
                                },
                                activeThumbColor: kGreenMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildSettingsSection(
                        title: 'Notifications',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.notifications_outlined,
                            title: 'Push Notifications',
                            subtitle: 'Receive scan alerts and reminders',
                            trailing: Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: true,
                                onChanged: (value) {},
                                activeThumbColor: kGreenMid,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(height: 1, color: kDivider),
                          ),
                          _buildSettingsTile(
                            icon: Icons.email_outlined,
                            title: 'Email Alerts',
                            subtitle: 'Weekly scan summaries',
                            trailing: Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: true,
                                onChanged: (value) {},
                                activeThumbColor: kGreenMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildSettingsSection(
                        title: 'Data & Privacy',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.info_outline,
                            title: 'Data Storage',
                            subtitle:
                                'Your scans are encrypted and stored securely',
                            onTap: () {},
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(height: 1, color: kDivider),
                          ),
                          _buildSettingsTile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy Policy',
                            onTap: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildSettingsSection(
                        title: 'About',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.info_outlined,
                            title: 'About FloraScan',
                            onTap: () => _showAboutDialog(context),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(height: 1, color: kDivider),
                          ),
                          _buildSettingsTile(
                            icon: Icons.bug_report_outlined,
                            title: 'App Version',
                            subtitle: 'v1.0.0',
                            onTap: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kGreenMid,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: kGreenMid, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextDark,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: kTextLight),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[trailing],
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'About FloraScan',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kGreenPale,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.asset(
                      'assets/images/FloraScan - Logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.eco, color: kGreenMid, size: 40),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FloraScan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(fontSize: 12, color: kTextLight),
                ),
                const SizedBox(height: 16),
                const Text(
                  'About',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'FloraScan is an advanced plant health monitoring application that uses Bluetooth connectivity to analyze leaf chlorophyll content and provide real-time health assessments for your plants.',
                  style: TextStyle(fontSize: 13, color: kTextMid, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Features',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                ...[
                  'Real-time chlorophyll analysis',
                  'Bluetooth device connectivity',
                  'Cloud data storage with Supabase',
                  'Secure user authentication',
                  'Detailed scan reports and history',
                  'Light and Dark mode support',
                ].map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      feature,
                      style: const TextStyle(fontSize: 13, color: kTextMid),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2026 FloraScan. All rights reserved.',
                  style: TextStyle(fontSize: 11, color: kTextLight),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: kGreenMid)),
            ),
          ],
        );
      },
    );
  }

  // ==================== HELPERS ====================
  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }

  String _chlorophyllLabel(LeafScanReport report) =>
      report.chlorophyllValue?.toString() ?? 'Pending';

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ==================== LEAF SCAN ANALYSIS RESULT ====================
class _LeafScanAnalysis {
  const _LeafScanAnalysis({
    required this.leafType,
    required this.lengthCm,
    required this.widthCm,
    required this.areaCm2,
    required this.perimeterCm,
    required this.aspectRatio,
    required this.hsvGreenHue,
  });

  final String leafType;
  final double lengthCm;
  final double widthCm;
  final double areaCm2;
  final double perimeterCm;
  final double aspectRatio;
  final double hsvGreenHue;
}

// ==================== LEAF IMAGE PROFILE ====================
class _LeafImageProfile {
  const _LeafImageProfile({
    required this.leafPixelCount,
    required this.greenCoverage,
    required this.bboxCoverage,
    required this.fillRatio,
    required this.longToShortRatio,
    required this.meanHue,
    required this.meanSaturation,
    required this.meanValue,
    required this.hueHistogram,
  });

  factory _LeafImageProfile.empty() => const _LeafImageProfile(
    leafPixelCount: 0,
    greenCoverage: 0,
    bboxCoverage: 0,
    fillRatio: 0,
    longToShortRatio: 0,
    meanHue: 0,
    meanSaturation: 0,
    meanValue: 0,
    hueHistogram: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  );

  final int leafPixelCount;
  final double greenCoverage;
  final double bboxCoverage;
  final double fillRatio;
  final double longToShortRatio;
  final double meanHue;
  final double meanSaturation;
  final double meanValue;
  final List<double> hueHistogram;

  bool get hasLeafCandidate =>
      leafPixelCount >= 180 &&
      greenCoverage >= 0.018 &&
      bboxCoverage >= 0.035 &&
      fillRatio >= 0.12 &&
      meanSaturation >= 0.18;
}

// ==================== CORNER BRACKET PAINTER ====================
class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const margin = 14.0;

    // Top-left
    canvas.drawLine(
      Offset(margin, margin + len),
      Offset(margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin + len, margin),
      paint,
    );
    // Top-right
    canvas.drawLine(
      Offset(size.width - margin - len, margin),
      Offset(size.width - margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin, margin + len),
      paint,
    );
    // Bottom-left
    canvas.drawLine(
      Offset(margin, size.height - margin - len),
      Offset(margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin + len, size.height - margin),
      paint,
    );
    // Bottom-right
    canvas.drawLine(
      Offset(size.width - margin - len, size.height - margin),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin - len),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerBracketPainter oldDelegate) => false;
}

// ==================== LEAF GUIDE PAINTER ====================
class _LeafGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.22;
    final ry = size.height * 0.38;

    const dashCount = 28;
    const gapFraction = 0.45;
    for (var i = 0; i < dashCount; i++) {
      final startAngle = (2 * pi * i) / dashCount;
      final sweepAngle = (2 * pi / dashCount) * (1 - gapFraction);
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2,
        height: ry * 2,
      );
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(_LeafGuidePainter oldDelegate) => false;
}
