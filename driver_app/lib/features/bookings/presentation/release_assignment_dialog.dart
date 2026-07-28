import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';

const emergencyReleaseReasonCodes = <String>{
  'VEHICLE_BREAKDOWN',
  'ACCIDENT',
  'DRIVER_ILLNESS',
  'FAMILY_EMERGENCY',
};

const releaseReasonCodes = <String>[
  'VEHICLE_BREAKDOWN',
  'ACCIDENT',
  'DRIVER_ILLNESS',
  'FAMILY_EMERGENCY',
  'SCHEDULE_CONFLICT',
  'LOCATION_TOO_FAR',
  'OTHER',
];

class ReleaseAssignmentInput {
  const ReleaseAssignmentInput({required this.reasonCode, this.reasonDetail});

  final String reasonCode;
  final String? reasonDetail;
}

class ReleaseAssignmentDialog extends StatefulWidget {
  const ReleaseAssignmentDialog({super.key, required this.emergencyOnly});

  final bool emergencyOnly;

  @override
  State<ReleaseAssignmentDialog> createState() =>
      _ReleaseAssignmentDialogState();
}

class _ReleaseAssignmentDialogState extends State<ReleaseAssignmentDialog> {
  String? _reasonCode;
  final _detailController = TextEditingController();

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reasons = releaseReasonCodes
        .where(
          (code) =>
              !widget.emergencyOnly ||
              emergencyReleaseReasonCodes.contains(code),
        )
        .toList(growable: false);
    final detailRequired = _reasonCode == 'OTHER';
    final detailValid =
        !detailRequired || _detailController.text.trim().length >= 3;

    return AlertDialog(
      key: const Key('releaseAssignmentDialog'),
      title: Text(l10n.releaseAssignmentTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.emergencyOnly) ...[
              Text(
                l10n.emergencyReleaseOnlyNotice,
                key: const Key('emergencyOnlyNotice'),
              ),
              const SizedBox(height: 8),
            ],
            RadioGroup<String>(
              groupValue: _reasonCode,
              onChanged: (value) => setState(() => _reasonCode = value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: reasons
                    .map(
                      (code) => RadioListTile<String>(
                        key: Key('releaseReason-$code'),
                        value: code,
                        contentPadding: EdgeInsets.zero,
                        title: Text(releaseReasonLabel(l10n, code)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            if (detailRequired)
              TextField(
                key: const Key('releaseReasonDetail'),
                controller: _detailController,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.releaseReasonDetailLabel,
                  hintText: l10n.releaseReasonDetailHint,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('releaseConfirmButton'),
          onPressed: _reasonCode != null && detailValid
              ? () => Navigator.of(context).pop(
                  ReleaseAssignmentInput(
                    reasonCode: _reasonCode!,
                    reasonDetail: detailRequired
                        ? _detailController.text.trim()
                        : null,
                  ),
                )
              : null,
          child: Text(l10n.releaseConfirm),
        ),
      ],
    );
  }
}
