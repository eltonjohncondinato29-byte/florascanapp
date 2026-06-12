part of '../main.dart';

// ==================== ADMIN ACTIVITY LOG PAGE ====================
class AdminActivityLogPage extends StatefulWidget {
  const AdminActivityLogPage({super.key});

  @override
  State<AdminActivityLogPage> createState() => _AdminActivityLogPageState();
}

class _AdminActivityLogPageState extends State<AdminActivityLogPage> {
  late Future<List<AdminActivityLog>> _logsFuture;
  String? _filterCropName;
  AdminActionType? _filterActionType;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  void _refreshLogs() {
    setState(() {
      _logsFuture = CropService.fetchActivityLogs(cropName: _filterCropName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('Admin Activity Log'),
        backgroundColor: kGreenMid,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshLogs),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: FutureBuilder<List<AdminActivityLog>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading logs: ${snapshot.error}'),
                  );
                }

                var logs = snapshot.data ?? [];

                // Apply action type filter if selected
                if (_filterActionType != null) {
                  logs = logs
                      .where((log) => log.actionType == _filterActionType)
                      .toList();
                }

                if (logs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text('No activity logs found'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return _buildActivityCard(log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: _buildActionTypeFilter()),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _filterCropName = null;
                  _filterActionType = null;
                });
                _refreshLogs();
              },
              tooltip: 'Clear filters',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTypeFilter() {
    return DropdownButton<AdminActionType?>(
      value: _filterActionType,
      isExpanded: true,
      underline: Container(height: 1, color: Colors.grey[300]),
      items: [
        const DropdownMenuItem(value: null, child: Text('All Actions')),
        ...AdminActionType.values.map(
          (actionType) => DropdownMenuItem(
            value: actionType,
            child: Text(_formatActionType(actionType)),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _filterActionType = value);
        _refreshLogs();
      },
    );
  }

  Widget _buildActivityCard(AdminActivityLog log) {
    final icon = log.actionType == AdminActionType.createdCrop
        ? Icons.add_circle
        : log.actionType == AdminActionType.updatedCrop
        ? Icons.edit
        : Icons.delete;

    final color = log.actionType == AdminActionType.createdCrop
        ? Colors.green
        : log.actionType == AdminActionType.updatedCrop
        ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 24),
        title: Text(
          _formatActionType(log.actionType),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Crop: ${log.cropName}'),
            Text('Admin: ${log.adminName}'),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                _buildLogDetail('Admin ID', log.adminId),
                _buildLogDetail('Admin Name', log.adminName),
                _buildLogDetail('Crop Name', log.cropName),
                _buildLogDetail(
                  'Action Type',
                  _formatActionType(log.actionType),
                ),
                _buildLogDetail('Date & Time', _formatDateTime(log.timestamp)),
                if (log.changeDescription != null)
                  _buildLogDetail('Changes', log.changeDescription!),
                if (log.previousValues != null &&
                    log.actionType == AdminActionType.updatedCrop) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Previous Values:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._buildValuesList(log.previousValues!),
                ],
                if (log.newValues != null &&
                    log.actionType == AdminActionType.updatedCrop) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'New Values:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._buildValuesList(log.newValues!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  List<Widget> _buildValuesList(Map<String, dynamic> values) {
    return values.entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '• ${entry.key}: ${entry.value}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        )
        .toList();
  }

  String _formatActionType(AdminActionType actionType) {
    switch (actionType) {
      case AdminActionType.createdCrop:
        return 'Created Crop';
      case AdminActionType.updatedCrop:
        return 'Updated Crop';
      case AdminActionType.deletedCrop:
        return 'Deleted Crop';
    }
  }

  String _formatDateTime(DateTime date) {
    return '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
