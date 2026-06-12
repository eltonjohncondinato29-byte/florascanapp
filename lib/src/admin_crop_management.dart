part of '../main.dart';

// ==================== ADMIN CROP MANAGEMENT PAGE ====================
class AdminCropManagementPage extends StatefulWidget {
  const AdminCropManagementPage({super.key, required this.onCropChanged});

  final VoidCallback onCropChanged;

  @override
  State<AdminCropManagementPage> createState() =>
      _AdminCropManagementPageState();
}

class _AdminCropManagementPageState extends State<AdminCropManagementPage> {
  late Future<List<CropProfile>> _cropsFuture;

  @override
  void initState() {
    super.initState();
    _cropsFuture = CropService.fetchAllCrops();
  }

  void _refreshCrops() {
    setState(() {
      _cropsFuture = CropService.fetchAllCrops();
    });
    widget.onCropChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('Crop Management'),
        backgroundColor: kGreenMid,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => const _AddCropDialog(),
              fullscreenDialog: true,
            ),
          );
          if (result == true) {
            _refreshCrops();
          }
        },
        backgroundColor: kGreenMid,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<CropProfile>>(
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
                  Text(
                    'No crops added yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap the + button to add your first crop'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: crops.length,
            itemBuilder: (context, index) {
              final crop = crops[index];
              return _buildCropCard(crop, _refreshCrops);
            },
          );
        },
      ),
    );
  }

  Widget _buildCropCard(CropProfile crop, VoidCallback onRefresh) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        crop.cropName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Created by ${crop.createdBy} on ${_formatDate(crop.createdDate)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) => _EditCropDialog(crop: crop),
                          fullscreenDialog: true,
                        ),
                      );
                      if (result == true) onRefresh();
                    } else if (value == 'delete') {
                      _showDeleteConfirmation(context, crop, onRefresh);
                    } else if (value == 'history') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => _CropHistoryPage(crop: crop),
                        ),
                      );
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Row(
                        children: [
                          Icon(Icons.history, size: 20),
                          SizedBox(width: 8),
                          Text('View History'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            _buildCropDetailsGrid(crop),
          ],
        ),
      ),
    );
  }

  Widget _buildCropDetailsGrid(CropProfile crop) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      children: [
        _buildDetailItem('SPAD Index', '${crop.referenceSpadIndex}'),
        _buildDetailItem('Leaf Length', '${crop.standardLeafLengthCm} cm'),
        _buildDetailItem('Leaf Width', '${crop.standardLeafWidthCm} cm'),
        _buildDetailItem('Perimeter', '${crop.standardLeafPerimeterCm} cm'),
        _buildDetailItem('Aspect Ratio', '${crop.standardAspectRatio}'),
        _buildDetailItem('Color', crop.standardLeafColor),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: kGreenPale,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF666666)),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: kGreenDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    CropProfile crop,
    VoidCallback onRefresh,
  ) {
    // Capture before the dialog so it is not used across an async gap
    // inside the builder's shadowed context.
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Crop'),
        content: Text(
          'Are you sure you want to delete "${crop.cropName}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final user = supabase.auth.currentUser;
              final adminName =
                  user?.userMetadata?['username'] as String? ??
                  user?.email?.split('@').first ??
                  'Unknown';

              final success = await CropService.deleteCrop(
                cropId: crop.id,
                cropName: crop.cropName,
                adminId: user?.id ?? '',
                adminName: adminName,
              );

              if (success && mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Crop "${crop.cropName}" deleted'),
                    backgroundColor: Colors.green,
                  ),
                );
                onRefresh();
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

// ==================== ADD CROP DIALOG ====================
class _AddCropDialog extends StatefulWidget {
  const _AddCropDialog();

  @override
  State<_AddCropDialog> createState() => _AddCropDialogState();
}

class _AddCropDialogState extends State<_AddCropDialog> {
  final _cropNameController = TextEditingController();
  final _spadController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _perimeterController = TextEditingController();
  final _aspectRatioController = TextEditingController();

  String _selectedColor = 'Dark Green';
  bool _isLoading = false;

  final _colorOptions = [
    'Dark Green',
    'Deep Glossy Green',
    'Green',
    'Light Green',
    'Yellow-Green',
  ];

  @override
  void dispose() {
    _cropNameController.dispose();
    _spadController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _perimeterController.dispose();
    _aspectRatioController.dispose();
    super.dispose();
  }

  Future<void> _saveCrop() async {
    if (_cropNameController.text.isEmpty ||
        _spadController.text.isEmpty ||
        _lengthController.text.isEmpty ||
        _widthController.text.isEmpty ||
        _perimeterController.text.isEmpty ||
        _aspectRatioController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Capture before the first await to avoid async-gap lint.
    final messenger = ScaffoldMessenger.of(context);

    try {
      final user = supabase.auth.currentUser;
      final adminName =
          user?.userMetadata?['username'] as String? ??
          user?.email?.split('@').first ??
          'Unknown';

      await CropService.createCrop(
        cropName: _cropNameController.text.trim(),
        referenceSpadIndex: double.parse(_spadController.text),
        standardLeafLengthCm: double.parse(_lengthController.text),
        standardLeafWidthCm: double.parse(_widthController.text),
        standardLeafColor: _selectedColor,
        standardLeafPerimeterCm: double.parse(_perimeterController.text),
        standardAspectRatio: double.parse(_aspectRatioController.text),
        adminId: user?.id ?? '',
        adminName: adminName,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error saving crop: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Crop'),
        backgroundColor: kGreenMid,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField('Crop Name', _cropNameController, 'e.g., Cucumber'),
            _buildTextField(
              'Reference Chlorophyll Index (SPAD)',
              _spadController,
              'e.g., 42.1',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Leaf Length (cm)',
              _lengthController,
              'e.g., 15.2',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Leaf Width (cm)',
              _widthController,
              'e.g., 15.2',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Leaf Perimeter (cm)',
              _perimeterController,
              'e.g., 48.3',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Aspect Ratio (L÷W)',
              _aspectRatioController,
              'e.g., 0.98',
              isNumeric: true,
            ),
            const SizedBox(height: 16),
            const Text(
              'Standard Leaf Color/Hue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _selectedColor,
              isExpanded: true,
              items: _colorOptions
                  .map(
                    (color) =>
                        DropdownMenuItem(value: color, child: Text(color)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedColor = value);
                }
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveCrop,
                style: ElevatedButton.styleFrom(backgroundColor: kGreenMid),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Crop',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    bool isNumeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            keyboardType: isNumeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
        ],
      ),
    );
  }
}

// ==================== EDIT CROP DIALOG ====================
class _EditCropDialog extends StatefulWidget {
  const _EditCropDialog({required this.crop});

  final CropProfile crop;

  @override
  State<_EditCropDialog> createState() => _EditCropDialogState();
}

class _EditCropDialogState extends State<_EditCropDialog> {
  late TextEditingController _cropNameController;
  late TextEditingController _spadController;
  late TextEditingController _lengthController;
  late TextEditingController _widthController;
  late TextEditingController _perimeterController;
  late TextEditingController _aspectRatioController;

  late String _selectedColor;
  bool _isLoading = false;

  final _colorOptions = [
    'Dark Green',
    'Deep Glossy Green',
    'Green',
    'Light Green',
    'Yellow-Green',
  ];

  @override
  void initState() {
    super.initState();
    _cropNameController = TextEditingController(text: widget.crop.cropName);
    _spadController = TextEditingController(
      text: widget.crop.referenceSpadIndex.toString(),
    );
    _lengthController = TextEditingController(
      text: widget.crop.standardLeafLengthCm.toString(),
    );
    _widthController = TextEditingController(
      text: widget.crop.standardLeafWidthCm.toString(),
    );
    _perimeterController = TextEditingController(
      text: widget.crop.standardLeafPerimeterCm.toString(),
    );
    _aspectRatioController = TextEditingController(
      text: widget.crop.standardAspectRatio.toString(),
    );
    _selectedColor = widget.crop.standardLeafColor;
  }

  @override
  void dispose() {
    _cropNameController.dispose();
    _spadController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _perimeterController.dispose();
    _aspectRatioController.dispose();
    super.dispose();
  }

  Future<void> _updateCrop() async {
    if (_cropNameController.text.isEmpty ||
        _spadController.text.isEmpty ||
        _lengthController.text.isEmpty ||
        _widthController.text.isEmpty ||
        _perimeterController.text.isEmpty ||
        _aspectRatioController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Capture before the first await to avoid async-gap lint.
    final messenger = ScaffoldMessenger.of(context);

    try {
      final user = supabase.auth.currentUser;
      final adminName =
          user?.userMetadata?['username'] as String? ??
          user?.email?.split('@').first ??
          'Unknown';

      await CropService.updateCrop(
        cropId: widget.crop.id,
        cropName: _cropNameController.text.trim(),
        referenceSpadIndex: double.parse(_spadController.text),
        standardLeafLengthCm: double.parse(_lengthController.text),
        standardLeafWidthCm: double.parse(_widthController.text),
        standardLeafColor: _selectedColor,
        standardLeafPerimeterCm: double.parse(_perimeterController.text),
        standardAspectRatio: double.parse(_aspectRatioController.text),
        adminId: user?.id ?? '',
        adminName: adminName,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error updating crop: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Crop'),
        backgroundColor: kGreenMid,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField('Crop Name', _cropNameController, 'e.g., Cucumber'),
            _buildTextField(
              'Reference Chlorophyll Index (SPAD)',
              _spadController,
              'e.g., 42.1',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Leaf Length (cm)',
              _lengthController,
              'e.g., 15.2',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Leaf Width (cm)',
              _widthController,
              'e.g., 15.2',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Leaf Perimeter (cm)',
              _perimeterController,
              'e.g., 48.3',
              isNumeric: true,
            ),
            _buildTextField(
              'Standard Aspect Ratio (L÷W)',
              _aspectRatioController,
              'e.g., 0.98',
              isNumeric: true,
            ),
            const SizedBox(height: 16),
            const Text(
              'Standard Leaf Color/Hue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _selectedColor,
              isExpanded: true,
              items: _colorOptions
                  .map(
                    (color) =>
                        DropdownMenuItem(value: color, child: Text(color)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedColor = value);
                }
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateCrop,
                style: ElevatedButton.styleFrom(backgroundColor: kGreenMid),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Update Crop',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    bool isNumeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            keyboardType: isNumeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
        ],
      ),
    );
  }
}

// ==================== CROP HISTORY PAGE ====================
class _CropHistoryPage extends StatefulWidget {
  const _CropHistoryPage({required this.crop});

  final CropProfile crop;

  @override
  State<_CropHistoryPage> createState() => _CropHistoryPageState();
}

class _CropHistoryPageState extends State<_CropHistoryPage> {
  late Future<List<CropHistory>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = CropService.fetchCropHistory(cropId: widget.crop.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.crop.cropName} - History'),
        backgroundColor: kGreenMid,
      ),
      body: FutureBuilder<List<CropHistory>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading history: ${snapshot.error}'),
            );
          }

          final history = snapshot.data ?? [];

          if (history.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('No history available'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final event = history[index];
              return _buildHistoryCard(event);
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryCard(CropHistory event) {
    final icon = event.eventType == CropHistoryEventType.created
        ? Icons.add_circle
        : event.eventType == CropHistoryEventType.updated
        ? Icons.edit
        : Icons.delete;

    final color = event.eventType == CropHistoryEventType.created
        ? Colors.green
        : event.eventType == CropHistoryEventType.updated
        ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.eventType.name.toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'By ${event.adminName}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(event.timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                    ),
                  ),
                  if (event.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                  if (event.newValues != null &&
                      event.eventType == CropHistoryEventType.updated) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kGreenPale,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Changes:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._buildChangeList(
                            event.previousValues,
                            event.newValues,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChangeList(
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  ) {
    if (oldValues == null || newValues == null) return [];

    final changes = <Widget>[];
    for (final key in newValues.keys) {
      final oldValue = oldValues[key];
      final newValue = newValues[key];

      if (oldValue != newValue) {
        changes.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• $key: $oldValue → $newValue',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        );
      }
    }

    return changes;
  }

  String _formatDateTime(DateTime date) {
    return '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
