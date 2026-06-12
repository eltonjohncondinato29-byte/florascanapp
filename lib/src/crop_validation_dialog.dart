part of '../main.dart';

// ==================== CROP VALIDATION DIALOG ====================
/// Dialog shown when scanned leaf doesn't closely match the selected crop
Future<bool> showCropValidationDialog(
  BuildContext context,
  CropValidationResult validationResult,
) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _CropValidationDialog(validationResult: validationResult),
      ) ??
      false;
}

class _CropValidationDialog extends StatelessWidget {
  const _CropValidationDialog({required this.validationResult});

  final CropValidationResult validationResult;

  @override
  Widget build(BuildContext context) {
    final isCriticalMismatch =
        validationResult.confidenceLevel == ConfidenceLevel.low;

    return AlertDialog(
      title: const Text('Crop Verification'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCriticalMismatch
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isCriticalMismatch ? Icons.warning : Icons.info,
                    color: isCriticalMismatch ? Colors.red : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCriticalMismatch
                              ? 'Critical Crop Mismatch'
                              : 'Crop Match Warning',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCriticalMismatch
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isCriticalMismatch
                              ? 'This leaf is NOT a match for the selected crop.'
                              : 'I am not fully confident that this leaf matches the selected crop.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Selected Crop: ${validationResult.selectedCropName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Match Confidence: ${validationResult.matchPercentage.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                color: _getConfidenceColor(validationResult.confidenceLevel),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Based on the scanned measurements, it may be:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ..._buildMatchList(),
            if (isCriticalMismatch) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'This scan cannot be saved under the selected crop. Please select the correct crop.',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!isCriticalMismatch)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, isCriticalMismatch),
          style: ElevatedButton.styleFrom(
            backgroundColor: isCriticalMismatch
                ? Colors.red
                : (validationResult.matchPercentage >= 75.0
                      ? Colors.green
                      : Colors.orange),
          ),
          child: Text(
            isCriticalMismatch ? 'I Understand' : 'Yes, Continue',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMatchList() {
    return validationResult.allMatches.asMap().entries.take(3).map((entry) {
      final index = entry.key;
      final match = entry.value;
      final isSelected = match.cropId == validationResult.selectedCropId;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? kGreenPale
                : Colors.grey.withValues(alpha: 0.05),
            border: isSelected ? Border.all(color: kGreenMid, width: 2) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${index + 1}. ${match.cropName}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getMatchColor(match.matchPercentage),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${match.matchPercentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (match.matchDetails.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: match.matchDetails.entries
                      .map(
                        (entry) => Text(
                          '${_formatDetailName(entry.key)}: ${entry.value}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _getMatchColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 50) return Colors.orange;
    return Colors.red;
  }

  String _formatDetailName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Color _getConfidenceColor(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return Colors.green;
      case ConfidenceLevel.medium:
        return Colors.orange;
      case ConfidenceLevel.low:
        return Colors.red;
    }
  }
}
