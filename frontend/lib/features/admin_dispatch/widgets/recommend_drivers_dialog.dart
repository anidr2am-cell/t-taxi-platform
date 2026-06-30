import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
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

  List<dynamic> get _candidates => _data?['candidates'] as List<dynamic>? ?? [];

  List<dynamic> get _excluded => _data?['excluded'] as List<dynamic>? ?? [];

  @override
  Widget build(BuildContext context) {
    final recommendedId = _data?['recommendedDriverId'] as int?;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
      title: const Text('Recommend drivers'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? AppUi.loadingState(message: 'Loading candidates...')
            : _error != null
                ? AppUi.errorState(message: _error!, onRetry: _load)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_candidates.isEmpty)
                          AppUi.emptyState(title: 'No eligible drivers found for this booking.'),
                        ..._candidates.asMap().entries.map((entry) {
                          final index = entry.key;
                          final map = Map<String, dynamic>.from(entry.value as Map);
                          return _CandidateCard(
                            map: map,
                            rank: index + 1,
                            recommendedId: recommendedId,
                            selectedDriverId: _selectedDriverId,
                            onSelect: (id) => setState(() => _selectedDriverId = id),
                          );
                        }),
                        if (_excluded.isNotEmpty) ...[
                          const SizedBox(height: AppTokens.spaceMd),
                          AppUi.sectionHeader(context, title: 'Excluded'),
                          ..._excluded.map((row) {
                            final map = Map<String, dynamic>.from(row as Map);
                            return AppUi.surfaceCard(
                              backgroundColor: AppTokens.surfaceMuted,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${map['displayName']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (map['reasons'] as List<dynamic>? ?? []).join(', '),
                                    style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13),
                                  ),
                                ],
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
          AppUi.secondaryButton(
            label: 'Assign recommended',
            icon: Icons.star_outline,
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
          ),
          const SizedBox(width: 8),
          AppUi.primaryButton(
            label: 'Assign selected',
            icon: Icons.check,
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
          ),
        ],
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.map,
    required this.rank,
    required this.recommendedId,
    required this.selectedDriverId,
    required this.onSelect,
  });

  final Map<String, dynamic> map;
  final int rank;
  final int? recommendedId;
  final int? selectedDriverId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final driverId = map['driverId'] as int;
    final isRecommended = driverId == recommendedId;
    final selected = selectedDriverId == driverId;
    final online = map['online'] == true;
    final reasons = (map['reasons'] as List<dynamic>? ?? []).join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppUi.surfaceCard(
        onTap: () => onSelect(driverId),
        backgroundColor: isRecommended ? AppTokens.accentLight : (selected ? AppTokens.primaryLight : AppTokens.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isRecommended ? AppTokens.accent.withValues(alpha: 0.15) : AppTokens.surfaceMuted,
                    borderRadius: AppTokens.borderRadiusSm,
                  ),
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isRecommended ? AppTokens.accent : AppTokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${map['displayName']} (${map['vehicleTypeCode'] ?? '-'})',
                    style: TextStyle(
                      fontWeight: isRecommended ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isRecommended) AppUi.statusBadge('Recommended', tone: AppStatusTone.warning),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppUi.statusBadge('Score ${map['score']}', tone: AppStatusTone.info),
                AppUi.statusBadge(
                  online ? 'Online' : 'Offline',
                  tone: online ? AppStatusTone.success : AppStatusTone.neutral,
                ),
                AppUi.statusBadge('Jobs ${map['activeJobCount']}', tone: AppStatusTone.neutral),
                if (map['distanceKm'] != null)
                  AppUi.statusBadge('${map['distanceKm']} km', tone: AppStatusTone.info),
              ],
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reasons, style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppTokens.primary : AppTokens.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  selected ? 'Selected' : 'Tap to select',
                  style: TextStyle(
                    color: selected ? AppTokens.primaryDark : AppTokens.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
