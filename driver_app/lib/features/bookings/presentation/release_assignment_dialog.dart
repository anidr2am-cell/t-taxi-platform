import 'package:flutter/material.dart';

const emergencyReleaseReasonCodes = <String>{
  'VEHICLE_BREAKDOWN',
  'ACCIDENT',
  'DRIVER_ILLNESS',
  'FAMILY_EMERGENCY',
};

const releaseReasonLabels = <String, String>{
  'VEHICLE_BREAKDOWN': '차량 고장',
  'ACCIDENT': '사고',
  'DRIVER_ILLNESS': '기사 질병',
  'FAMILY_EMERGENCY': '가족 긴급 상황',
  'SCHEDULE_CONFLICT': '일정 충돌',
  'LOCATION_TOO_FAR': '거리가 너무 멂',
  'OTHER': '기타',
};

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
    final reasons = releaseReasonLabels.entries
        .where(
          (entry) =>
              !widget.emergencyOnly ||
              emergencyReleaseReasonCodes.contains(entry.key),
        )
        .toList(growable: false);
    final detailRequired = _reasonCode == 'OTHER';
    final detailValid =
        !detailRequired || _detailController.text.trim().length >= 3;

    return AlertDialog(
      key: const Key('releaseAssignmentDialog'),
      title: const Text('배정 반납'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.emergencyOnly) ...[
              const Text(
                '일반 반납 가능 시간이 지나 긴급 사유만 선택할 수 있습니다.',
                key: Key('emergencyOnlyNotice'),
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
                      (reason) => RadioListTile<String>(
                        key: Key('releaseReason-${reason.key}'),
                        value: reason.key,
                        contentPadding: EdgeInsets.zero,
                        title: Text(reason.value),
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
                decoration: const InputDecoration(
                  labelText: '상세 사유',
                  hintText: '3자 이상 입력해 주세요.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
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
          child: const Text('반납하기'),
        ),
      ],
    );
  }
}
