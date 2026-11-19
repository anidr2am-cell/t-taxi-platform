import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../../core/pwa/pwa_install_service.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../services/driver_api_service.dart';
import '../pages/driver_notifications_page.dart';

class DriverArrivalReadinessCard extends StatefulWidget {
  const DriverArrivalReadinessCard({
    super.key,
    required this.api,
    this.registration,
  });
  final DriverApiService api;
  final NotificationDeviceRegistrationService? registration;
  @override
  State<DriverArrivalReadinessCard> createState() =>
      _DriverArrivalReadinessCardState();
}

class _DriverArrivalReadinessCardState
    extends State<DriverArrivalReadinessCard> {
  late final _pwa = createPwaInstallService();
  late final _registration =
      widget.registration ?? NotificationDeviceRegistrationService();
  String? _result;
  int _unreadArrivals = 0;
  Timer? _timer;
  bool _checking = false;
  @override
  void initState() {
    super.initState();
    _checkInbox();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _checkInbox());
  }

  Future<void> _checkInbox() async {
    if (_checking) return;
    _checking = true;
    try {
      final data = await widget.api.listNotifications(unreadOnly: true);
      final items = (data['items'] as List? ?? []).whereType<Map>();
      final count = items
          .where((n) => n['notificationType'] == 'CUSTOMER_GATE_ARRIVED')
          .length;
      if (mounted) setState(() => _unreadArrivals = count);
    } catch (_) {
      /* Keep the last known unread count; never claim push is enabled. */
    } finally {
      _checking = false;
    }
  }

  bool _busy = false;
  @override
  void dispose() {
    _timer?.cancel();
    if (widget.registration == null) _registration.dispose();
    _pwa.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    if (_busy) return;
    if (!_pwa.isStandalone && !_pwa.isInstalled) {
      setState(
        () => _result =
            'กรุณาเพิ่ม T-Ride Driver ลงหน้าจอหลัก แล้วเปิดจากไอคอนก่อน\n바탕화면에 설치한 뒤 아이콘으로 열어 주세요.',
      );
      return;
    }
    setState(() => _busy = true);
    final result = await _registration.enableAuthenticated(
      accessTokenLoader: widget.api.getSavedToken,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result.registered
          ? 'ลงทะเบียนรับแจ้งเตือนแล้ว โปรดตรวจสอบเสียงและการตั้งค่าโทรศัพท์ด้วย\n알림 등록 완료. 휴대전화 소리·알림 설정도 확인해 주세요.'
          : 'ยังรับแจ้งเตือนไม่ได้ โปรดเปิดอนุญาตการแจ้งเตือน หากยังไม่ได้ให้ติดต่อผู้ดูแล\n알림 등록이 안 됐습니다. 알림 권한을 확인하거나 관리자에게 문의하세요.';
    });
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.notifications_active, color: AppTokens.primary),
    title: Text(
      _unreadArrivals > 0
          ? 'ลูกค้าถึงประตู 7 แล้ว ($_unreadArrivals)\n고객 도착 알림 · 눌러서 확인'
          : 'รับแจ้งเมื่อลูกค้าถึงประตู 7\n고객 7번 게이트 도착 알림',
    ),
    children: [
      Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ต้องติดตั้ง PWA และเปิดจากไอคอนบนหน้าจอหลัก\nPWA를 설치하고 바탕화면 아이콘으로 실행하세요.\n\n1. Android: เปิดด้วย Chrome → เมนู ⋮ → ติดตั้ง / เพิ่มลงหน้าจอหลัก\niPhone (iOS 16.4 ขึ้นไป): เปิดด้วย Safari → แชร์ → เพิ่มไปยังหน้าจอโฮม\n2. เปิดจากไอคอนและเข้าสู่ระบบ แล้วกดปุ่มด้านล่าง → อนุญาต\n3. เปิดเสียงและการแจ้งเตือน ปิดโหมดห้ามรบกวน ตรวจสอบอินเทอร์เน็ตและโหมดประหยัดพลังงาน\n\nเมื่อเห็น “ลูกค้าถึงประตู 7 แล้ว” ให้ตรวจเลขที่การจอง เปิดรายละเอียดงาน และประสานกับผู้ดูแล\n\nการติดตั้งอย่างเดียวไม่รับประกันว่าจะมีเสียงทุกครั้ง ก่อนเวลารับให้เปิดรายการแจ้งเตือนตรวจสอบด้วย หากไม่มีแจ้งเตือนให้ติดต่อผู้ดูแล ห้ามกดเริ่มงานเพียงเพราะได้รับแจ้งเตือน\n설치만으로 알림이 보장되지 않습니다. 픽업 전 알림 목록을 확인하고, 문제가 있으면 관리자에게 문의하세요. 도착 알림은 운행 시작 지시가 아닙니다.',
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTokens.spaceSm,
                ),
                child: Text(_result!),
              ),
            FilledButton(
              onPressed: _busy ? null : _enable,
              child: const Text('เปิดรับแจ้งเตือน / 알림 켜기'),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverNotificationsPage(api: widget.api),
                ),
              ),
              child: const Text('ดูรายการแจ้งเตือน / 알림 목록 확인'),
            ),
          ],
        ),
      ),
    ],
  );
}
