import 'package:flutter/material.dart';

import '../services/admin_dispatch_api_service.dart';

class RecommendDriversDialogResult {
  const RecommendDriversDialogResult({
    required this.driverId,
    required this.useTopCandidate,
    required this.assignmentVersion,
  });

  final int driverId;
  final bool useTopCandidate;
  final int assignmentVersion;
}

Future<RecommendDriversDialogResult?> showRecommendDriversDialog({
  required BuildContext context,
  required AdminDispatchApiService api,
  required String bookingNumber,
}) {
  return showDialog<RecommendDriversDialogResult>(
    context: context,
    builder: (ctx) => _RecommendDriversDialog(api: api, bookingNumber: bookingNumber),
  );
}

class _RecommendDriversDialog extends StatefulWidget {
  const _RecommendDriversDialog({
    required this.api,
    required this.bookingNumber,
  });

  final AdminDispatchApiService api;
  final String bookingNumber;

  @override
  State<_RecommendDriversDialog> createState() => _RecommendDriversDialogState();
}

class _RecommendDriversDialogState extends State<_RecommendDriversDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  int? _selectedDriverId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getDriverCandidates(widget.bookingNumber);
      if (!mounted) return;
      setState(() {
        _data = data;
        _selectedDriverId = data['recommendedDriverId'] as int?;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  List<dynamic> get _candidates =>
      _data?['candidates'] as List<dynamic>? ?? [];

  List<dynamic> get _excluded =>
      _data?['excluded'] as List<dynamic>? ?? [];

  @override
  Widget build(BuildContext context) {
    final recommendedId = _data?['recommendedDriverId'] as int?;

    return AlertDialog(
      title: const Text('Recommend drivers'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_candidates.isEmpty)
                          const Text('No eligible drivers found for this booking.'),
                        ..._candidates.map((row) {
                          final map = Map<String, dynamic>.from(row as Map);
                          final driverId = map['driverId'] as int;
                          final isRecommended = driverId == recommendedId;
                          final selected = _selectedDriverId == driverId;
                          return Card(
                            color: isRecommended ? Colors.green.shade50 : null,
                            child: ListTile(
                              selected: selected,
                              onTap: () => setState(() => _selectedDriverId = driverId),
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                              ),
                              title: Text(
                                '${map['displayName']} (${map['vehicleTypeCode'] ?? '-'})',
                                style: TextStyle(
                                  fontWeight: isRecommended ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                'Score ${map['score']} · '
                                '${map['online'] == true ? 'Online' : 'Offline'} · '
                                'Jobs ${map['activeJobCount']} · '
                                '${map['distanceKm'] != null ? '${map['distanceKm']} km' : 'No distance'} · '
                                '${(map['reasons'] as List<dynamic>? ?? []).join(', ')}',
                              ),
                              trailing: isRecommended
                                  ? const Chip(label: Text('Recommended'))
                                  : null,
                            ),
                          );
                        }),
                        if (_excluded.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Excluded', style: TextStyle(fontWeight: FontWeight.bold)),
                          ..._excluded.map((row) {
                            final map = Map<String, dynamic>.from(row as Map);
                            return ListTile(
                              dense: true,
                              title: Text('${map['displayName']}'),
                              subtitle: Text(
                                (map['reasons'] as List<dynamic>? ?? []).join(', '),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (!_loading && _error == null && _candidates.isNotEmpty) ...[
          OutlinedButton(
            onPressed: recommendedId == null
                ? null
                : () => Navigator.pop(
                      context,
                      RecommendDriversDialogResult(
                        driverId: recommendedId,
                        useTopCandidate: true,
                        assignmentVersion: _data?['assignmentVersion'] as int? ?? 0,
                      ),
                    ),
            child: const Text('Assign recommended'),
          ),
          FilledButton(
            onPressed: _selectedDriverId == null
                ? null
                : () => Navigator.pop(
                      context,
                      RecommendDriversDialogResult(
                        driverId: _selectedDriverId!,
                        useTopCandidate: false,
                        assignmentVersion: _data?['assignmentVersion'] as int? ?? 0,
                      ),
                    ),
            child: const Text('Assign selected'),
          ),
        ],
      ],
    );
  }
}
