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
  String _connectionStatus = 'Disconnected';
  int? _chlorophyllValue;
  final List<LeafScanReport> _reports = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // Leaf identification and analysis variables
  bool _isAnalyzing = false;
  bool _fieldsLocked = false;
  String? _capturedImagePath;
  Map<String, _LeafImageProfile>? _leafReferenceProfiles;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _initializeCamera();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _leafNameController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _cameraController?.dispose();
    _saveReports(); // Save reports before disposing
    super.dispose();
  }

  // Get user-specific storage key
  /// Generates user-specific storage key for leaf scan reports
  String _getUserReportsKey() {
    final userId = supabase.auth.currentUser?.id ?? 'unknown';
    return 'leaf_scan_reports_$userId';
  }

  // Save reports to secure storage (user-specific)
  /// Saves all leaf scan reports to secure storage (user-specific)
  Future<void> _saveReports() async {
    final jsonList = _reports.map((r) => r.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await appSecureStorage.write(key: _getUserReportsKey(), value: jsonString);
  }

  // Load reports from secure storage (user-specific)
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

    // Start the camera preview
    setState(() {
      _isCameraActive = true;
      _isAnalyzing = false;
      _capturedImagePath = null;
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

  /// Captures an image from the camera for leaf analysis
  Future<void> _captureLeafImage() async {
    if (_isAnalyzing) return;

    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }

      // Freeze the camera frame
      final capturedImage = await _cameraController!.takePicture();

      // Start analysis with loading effect
      if (!mounted) return;
      setState(() {
        _isAnalyzing = true;
        _capturedImagePath = capturedImage.path;
        _leafNameController.clear();
        _lengthController.clear();
        _widthController.clear();
        _chlorophyllValue = null;
        _fieldsLocked = false;
        _connectionStatus = 'Analyzing leaf...';
      });

      // Identify the leaf type
      final analysis = await _analyzeLeafImage(capturedImage.path);

      if (analysis == null) {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _connectionStatus =
                'Not a Cucumber or Robusta Coffee leaf. Try again.';
            _fieldsLocked = false;
            _chlorophyllValue = null;
            _leafNameController.clear();
            _lengthController.clear();
            _widthController.clear();
            _isCameraActive = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️  Not a Cucumber or Robusta Coffee leaf. Please scan a valid leaf.',
              ),
              backgroundColor: ui.Color.fromARGB(1, 255, 95, 95),
            ),
          );
        }
        return;
      }

      final leafType = analysis.leafType;
      final measurements = {
        'length': analysis.lengthCm,
        'width': analysis.widthCm,
      };
      // Auto-populate fields with scan results
      if (mounted) {
        setState(() {
          _leafNameController.text = analysis.leafType;
          _lengthController.text = analysis.lengthCm.toStringAsFixed(1);
          _widthController.text = analysis.widthCm.toStringAsFixed(1);
          _chlorophyllValue = null;
          _fieldsLocked = true;
          _isAnalyzing = false;
          _connectionStatus = 'Leaf scanned successfully.';
          _isCameraActive = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$leafType scanned. L: ${measurements['length']}cm, W: ${measurements['width']}cm',
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

  /// Determines leaf health status (Healthy/Mild stress/Needs attention) based on chlorophyll
  String _leafHealthStatus(int value) {
    if (value >= 55) return 'Healthy';
    if (value >= 40) return 'Mild stress';
    return 'Needs attention';
  }

  /// Analyzes the captured frame and accepts only the two supported leaf types.
  Future<_LeafScanAnalysis?> _analyzeLeafImage(String imagePath) async {
    try {
      if (imagePath.isEmpty) return null;

      final capturedProfile = await _createLeafProfileFromFile(imagePath);
      await Future<void>.delayed(const Duration(milliseconds: 650));

      if (!capturedProfile.hasLeafCandidate) {
        return null;
      }

      final references = await _loadLeafReferenceProfiles();
      final scores =
          references.entries
              .map(
                (entry) => MapEntry(
                  entry.key,
                  _leafProfileDistance(capturedProfile, entry.value),
                ),
              )
              .toList()
            ..sort((a, b) => a.value.compareTo(b.value));

      final bestMatch = scores.first;
      if (bestMatch.value > 0.48) {
        return null;
      }

      final measurements = _estimateLeafMeasurements(
        bestMatch.key,
        capturedProfile,
      );

      return _LeafScanAnalysis(
        leafType: bestMatch.key,
        lengthCm: measurements['length']!,
        widthCm: measurements['width']!,
      );
    } catch (e) {
      debugPrint('Error analyzing leaf: $e');
      return null;
    }
  }

  Future<Map<String, _LeafImageProfile>> _loadLeafReferenceProfiles() async {
    final cached = _leafReferenceProfiles;
    if (cached != null) return cached;

    final references = <String, String>{
      'Cucumber Leaf': 'assets/images/Cucumber Leaf.png',
      'Robusta Coffee Leaf': 'assets/images/Robusta Coffee Leaf.png',
    };

    final profiles = <String, _LeafImageProfile>{};
    for (final entry in references.entries) {
      final bytes = await rootBundle.load(entry.value);
      profiles[entry.key] = await _createLeafProfile(
        bytes.buffer.asUint8List(),
      );
    }

    _leafReferenceProfiles = profiles;
    return profiles;
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

  double _leafProfileDistance(
    _LeafImageProfile captured,
    _LeafImageProfile reference,
  ) {
    var histogramDistance = 0.0;
    for (var i = 0; i < captured.hueHistogram.length; i++) {
      histogramDistance +=
          (captured.hueHistogram[i] - reference.hueHistogram[i]).abs();
    }
    histogramDistance = (histogramDistance / 2).clamp(0.0, 1.0).toDouble();

    final ratioDistance =
        (log(captured.longToShortRatio / reference.longToShortRatio).abs() /
                log(4))
            .clamp(0.0, 1.0)
            .toDouble();

    return (captured.meanHue - reference.meanHue).abs() / 125 * 0.20 +
        (captured.meanSaturation - reference.meanSaturation).abs() * 0.18 +
        (captured.meanValue - reference.meanValue).abs() * 0.14 +
        ratioDistance * 0.24 +
        (captured.fillRatio - reference.fillRatio).abs() * 0.12 +
        (captured.greenCoverage - reference.greenCoverage).abs() * 0.04 +
        histogramDistance * 0.08;
  }

  Map<String, double> _estimateLeafMeasurements(
    String leafType,
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

    late double length;
    late double width;

    switch (leafType) {
      case 'Cucumber Leaf':
        length = 4.5 + signal * 2.5;
        width = (length / profile.longToShortRatio).clamp(3.0, 5.6).toDouble();
        break;
      case 'Robusta Coffee Leaf':
        length = 8.0 + signal * 7.0;
        width = (length / profile.longToShortRatio).clamp(4.0, 8.0).toDouble();
        break;
      default:
        length = 0;
        width = 0;
    }

    return {
      'length': double.parse(length.toStringAsFixed(1)),
      'width': double.parse(width.toStringAsFixed(1)),
    };
  }

  /// Saves current scan report to local storage and cloud database
  Future<void> _saveScanReport() async {
    final name = _leafNameController.text.trim();
    final lengthCm = double.tryParse(_lengthController.text) ?? 0;
    final widthCm = double.tryParse(_widthController.text) ?? 0;
    final chlorophyll = _chlorophyllValue;

    if (name.isEmpty || lengthCm <= 0 || widthCm <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan a supported leaf first.')),
      );
      return;
    }

    final areaCm2 = double.parse((lengthCm * widthCm).toStringAsFixed(2));
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
    );

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

      await supabase.schema('florascan').from('leaf_scans').insert(scanData);

      setState(() {
        _reports.insert(0, report);
        _leafNameController.clear();
        _lengthController.clear();
        _widthController.clear();
        _chlorophyllValue = null;
        _fieldsLocked = false;
        _connectionStatus = 'Saved!.';
      });
      await _saveReports(); // Save to local storage
    } catch (e) {
      setState(() => _connectionStatus = 'Database Error: $e');
    }
  }

  /// Updates selected tab index to switch between different app screens
  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    if (index == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openCameraToScanLeaf());
      });
    } else {
      _stopCamera();
    }
  }

  // --- Bottom Nav ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildDashboardTab(),
      _buildHistoryTab(),
      _buildScanTab(),
      _buildReportsTab(),
      _buildProfileTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: tabs[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ==================== BOTTOM NAVIGATION ====================
  /// Builds the bottom navigation bar with 5 tabs including center scan button
  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_filled, 'label': 'Dashboard'},
      {'icon': Icons.history, 'label': 'History'},
      {'icon': Icons.qr_code_scanner, 'label': ''},
      {'icon': Icons.bar_chart_rounded, 'label': 'Reports'},
      {'icon': Icons.person_outline, 'label': 'Profile'},
    ];

    return Container(
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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isCenter = i == 2;
          final isSelected = _selectedIndex == i;
          final icon = items[i]['icon'] as IconData;
          final label = items[i]['label'] as String;

          if (isCenter) {
            return GestureDetector(
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
            );
          }

          return GestureDetector(
            onTap: () => _selectTab(i),
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isSelected ? kGreenMid : const Color(0xFFB0BEC5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? kGreenMid : const Color(0xFFB0BEC5),
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

  // --- Dashboard Tab --------------------------------------------------------

  // ==================== DASHBOARD TAB ====================
  /// Displays dashboard with current scan status, recent activity, and device info
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
            // -- Top Bar: notification + settings on right, logo CENTERED --
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Logo perfectly centered
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
                  // Icons pinned to the right
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
            // Welcome text
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
            // -- Cards ------------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // -- Current Scan card (prototype style) ------------------
                  GestureDetector(
                    onTap: () => _selectTab(2),
                    child: _dashCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left: label + big number + subtitle + timestamp
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
                          // Right: device icon box
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

                  // -- Recent Activity card (prototype: listed rows) ---------
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

                  // -- Device Status card (prototype style) ------------------
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
                            // Device icon with green tint when connected
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
                                    Text(
                                      'Connection: ',
                                      style: const TextStyle(
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

  /// Builds a reusable dashboard card container with shadow and rounding
  /// Builds a stylized dashboard card with shadow and custom styling
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

  // --- History Tab ----------------------------------------------------------

  /// Shows all previous leaf scan records in chronological order
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
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.leafName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: kTextDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Width: ${r.widthCm}cm  Length: ${r.lengthCm}cm',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: kTextMid,
                                    ),
                                  ),
                                  Text(
                                    'Chl: ${_chlorophyllLabel(r)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: kTextMid,
                                    ),
                                  ),
                                  Text(
                                    r.status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: r.status == 'Healthy'
                                          ? kGreenMid
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- Scan Tab -------------------------------------------------------------

  // ==================== SCAN TAB ====================
  /// Main scanning interface - shows camera frame, inputs, and device controls
  Widget _buildScanTab() {
    return SafeArea(
      child: Column(
        children: [
          // Top bar with back arrow and close
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
          // Scanner crosshair icon
          const Icon(Icons.gps_fixed, size: 38, color: kGreenMid),
          const SizedBox(height: 6),
          const Text(
            'Position leaf in frame',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: kTextMid,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(child: _buildScannerFrame()),
          const SizedBox(height: 20),
          // Scan fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _scanField(
                  'Leaf name / Sample ID',
                  _leafNameController,
                  readOnly: true,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _scanField(
                        'Length (cm)',
                        _lengthController,
                        keyboard: TextInputType.number,
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _scanField(
                        'Width (cm)',
                        _widthController,
                        keyboard: TextInputType.number,
                        readOnly: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Status
          if (_connectionStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                _connectionStatus,
                style: const TextStyle(fontSize: 12, color: kTextLight),
                textAlign: TextAlign.center,
              ),
            ),
          // Bluetooth devices
          if (_foundDevices.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: _foundDevices.values.map((device) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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
          const SizedBox(height: 12),
          // Bottom buttons row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(
                      Icons.bluetooth_searching,
                      size: 16,
                      color: kGreenMid,
                    ),
                    label: Text(
                      _isScanning
                          ? 'Searching...'
                          : 'Search Chlorophyll Device',
                      style: const TextStyle(fontSize: 12, color: kGreenMid),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kGreenMid),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isAnalyzing
                      ? null
                      : (_isCameraActive
                            ? _captureLeafImage
                            : _openCameraToScanLeaf),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _isAnalyzing ? kGreenPale : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: kGreenMid, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: kGreenMid.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner,
                      color: kGreenMid,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _fieldsLocked ? _saveScanReport : null,
                    icon: const Icon(
                      Icons.save_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Save',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreenMid,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildScannerFrame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = max(0.0, constraints.maxWidth - 40);
        final frameWidth = min(432.0, availableWidth);
        final frameHeight = min(
          315.0,
          min(frameWidth / 1.38, constraints.maxHeight),
        );
        final hasLiveCamera =
            _isCameraActive &&
            _isCameraInitialized &&
            _cameraController?.value.isInitialized == true;
        final frozenFramePath = _capturedImagePath;

        return Center(
          child: SizedBox(
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
                      color: const Color(0xFF3A6F43),
                      child: const Center(
                        child: Icon(
                          Icons.eco,
                          size: 78,
                          color: Color(0x55FFFFFF),
                        ),
                      ),
                    ),
                  CustomPaint(painter: _CornerBracketPainter()),
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

  // ==================== SCAN INPUT FIELD ====================
  /// Builds a text input field for scan data (name, length, width)
  Widget _scanField(
    String hint,
    TextEditingController controller, {
    TextInputType keyboard = TextInputType.text,
    bool readOnly = false,
  }) {
    final hasValue = controller.text.trim().isNotEmpty;

    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        readOnly: readOnly,
        style: TextStyle(
          fontSize: 13,
          color: hasValue ? kGreenMid : kTextDark,
          fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kTextLight, fontSize: 13),
          filled: true,
          fillColor: hasValue ? kGreenPale : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: hasValue ? kGreenAccent : Colors.transparent,
              width: hasValue ? 1.5 : 0,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: hasValue ? kGreenAccent : Colors.transparent,
              width: hasValue ? 1.5 : 0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: hasValue ? kGreenMid : kGreenAccent,
              width: 1.2,
            ),
          ),
          suffixIcon: hasValue
              ? const Icon(Icons.check_circle, color: kGreenAccent, size: 20)
              : null,
        ),
      ),
    );
  }

  // --- Reports Tab ----------------------------------------------------------

  /// Shows detailed analysis reports for all completed leaf measurements
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
                            const SizedBox(height: 8),
                            Text(
                              'Width: ${r.widthCm}cm   Length: ${r.lengthCm}cm',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kTextMid,
                              ),
                            ),
                            Text(
                              'Chlorophyll: ${_chlorophyllLabel(r)}   Status: ${r.status}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kTextMid,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.fertilizer,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kGreenMid,
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

  // --- Profile Tab ----------------------------------------------------------

  /// Displays user profile with account info and sign-out option
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

  // --- Settings Bottom Sheet -------------------------------------------------

  /// Shows the Settings bottom sheet with theme, notifications, and about app
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
                      // Header
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

                      // -- Theme Section ------------------------------------
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

                      // -- Notifications Section ----------------------------
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

                      // -- Data & Privacy Section ---------------------------
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

                      // -- About App Section --------------------------------
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

  /// Builds a settings section container with title and list of options
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

  /// Builds an individual settings menu tile with icon, title, and optional trailing widget
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

  /// Shows the About App dialog with app info, features, and version
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
                  '?? Real-time chlorophyll analysis',
                  '?? Bluetooth device connectivity',
                  '?? Cloud data storage with Supabase',
                  '?? Secure user authentication',
                  '?? Detailed scan reports and history',
                  '?? Light and Dark mode support',
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
                  '� 2026 FloraScan. All rights reserved.',
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

  // --- Helpers --------------------------------------------------------------

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';

  /// Formats DateTime as relative time (just now, 5m ago, 2h ago, 3/5)
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

  /// Capitalizes first letter of string for display
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _LeafScanAnalysis {
  const _LeafScanAnalysis({
    required this.leafType,
    required this.lengthCm,
    required this.widthCm,
  });

  final String leafType;
  final double lengthCm;
  final double widthCm;
}

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

// --- Corner Bracket Painter ---------------------------------------------------

class _CornerBracketPainter extends CustomPainter {
  @override
  /// Paints corner brackets at the four corners of the scan frame
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
  /// Returns false since brackets don't change between repaints
  bool shouldRepaint(_CornerBracketPainter oldDelegate) => false;
}
