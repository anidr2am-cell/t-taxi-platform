import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';

void main() {
  const keys = <String>[
    'driver_release_assignment',
    'driver_release_assignment_title',
    'driver_release_assignment_message',
    'driver_release_assignment_cancel',
    'driver_release_assignment_confirm',
    'driver_release_assignment_success',
    'driver_release_assignment_failed',
    'driver_release_assignment_blocked',
    'driver_release_assignment_emergency_hint',
    'driver_release_assignment_irreversible',
    'driver_release_reason_label',
    'driver_release_reason_detail_label',
    'driver_release_reason_detail_required',
    'driver_release_reason_VEHICLE_BREAKDOWN',
    'driver_release_reason_ACCIDENT',
    'driver_release_reason_DRIVER_ILLNESS',
    'driver_release_reason_FAMILY_EMERGENCY',
    'driver_release_reason_SCHEDULE_CONFLICT',
    'driver_release_reason_LOCATION_TOO_FAR',
    'driver_release_reason_OTHER',
    'guest_status_guidance_reassignment',
    'status_reassignment_in_progress',
    'admin_ops_severity_critical',
    'admin_ops_reason_critical_reassignment',
    'admin_ops_reason_urgent_reassignment',
    'admin_ops_reason_driver_released_reassignment',
    'admin_ops_reason_critical_unassigned',
    'admin_ops_reason_urgent_unassigned',
  ];

  for (final language in AppLocalizations.supportedLanguages) {
    test('$language has all release/reassignment keys without fallback', () {
      final l10n = AppLocalizations(language);
      for (final key in keys) {
        final value = l10n.t(key);
        expect(value, isNot(equals(key)), reason: '$language missing $key');
        expect(value.trim(), isNotEmpty, reason: '$language empty $key');
      }
    });
  }

  test('ko uses 배정 반납 wording', () {
    final l10n = AppLocalizations('ko');
    expect(l10n.t('driver_release_assignment'), '배정 반납');
    expect(l10n.t('status_reassignment_in_progress'), '기사 재배정 중');
  });

  test('th uses คืนงาน wording for driver release', () {
    final l10n = AppLocalizations('th');
    expect(l10n.t('driver_release_assignment'), 'คืนงาน');
    expect(l10n.t('status_reassignment_in_progress'), 'กำลังจัดหาคนขับใหม่');
  });

  test('zh and ja return localized reassignment guidance', () {
    expect(
      AppLocalizations('zh').t('guest_status_guidance_reassignment'),
      contains('司机'),
    );
    expect(
      AppLocalizations('ja').t('guest_status_guidance_reassignment'),
      contains('ドライバー'),
    );
  });
}
