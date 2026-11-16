import 'dart:convert';

import 'package:flutter/material.dart';

import '../driver_ux.dart';
import '../services/driver_api_service.dart';

enum DriverPasswordChangeResult { changed, sessionExpired }

class DriverPasswordChangeDialog extends StatefulWidget {
  const DriverPasswordChangeDialog({super.key, required this.changePassword});

  final Future<void> Function(String currentPassword, String newPassword)
  changePassword;

  @override
  State<DriverPasswordChangeDialog> createState() =>
      _DriverPasswordChangeDialogState();
}

class _DriverPasswordChangeDialogState
    extends State<DriverPasswordChangeDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String _text(String ko, String th) => '$ko / $th';

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.changePassword(_current.text, _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(DriverPasswordChangeResult.changed);
    } catch (error) {
      if (!mounted) return;
      if (driverIsAuthError(error)) {
        Navigator.of(context).pop(DriverPasswordChangeResult.sessionExpired);
        return;
      }
      final code = error is DriverApiException ? error.errorCode : null;
      setState(() {
        _submitting = false;
        _error = switch (code) {
          'CURRENT_PASSWORD_INCORRECT' => _text(
            '현재 비밀번호를 확인해 주세요.',
            'โปรดตรวจสอบรหัสผ่านปัจจุบัน',
          ),
          'PASSWORD_UNCHANGED' => _text(
            '현재와 다른 비밀번호를 입력해 주세요.',
            'โปรดใช้รหัสผ่านที่ต่างจากรหัสเดิม',
          ),
          'PASSWORD_CHANGE_CONFLICT' => _text(
            '비밀번호가 이미 변경되었습니다. 현재 비밀번호를 확인해 주세요.',
            'รหัสผ่านถูกเปลี่ยนแล้ว โปรดตรวจสอบรหัสผ่านปัจจุบัน',
          ),
          'RATE_LIMIT' => _text(
            '시도 횟수가 너무 많습니다. 잠시 후 다시 시도해 주세요.',
            'ลองหลายครั้งเกินไป โปรดลองใหม่ในภายหลัง',
          ),
          _ => _text(
            '비밀번호 변경에 실패했습니다. 다시 시도해 주세요.',
            'เปลี่ยนรหัสผ่านไม่สำเร็จ โปรดลองอีกครั้ง',
          ),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        scrollable: true,
        title: Text(_text('비밀번호 변경', 'เปลี่ยนรหัสผ่าน')),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '변경하면 새 비밀번호로 다시 로그인해야 합니다.',
                  'หลังเปลี่ยนรหัสผ่าน โปรดเข้าสู่ระบบใหม่ด้วยรหัสผ่านใหม่',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _current,
                enabled: !_submitting,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _text('현재 비밀번호', 'รหัสผ่านปัจจุบัน'),
                  errorMaxLines: 3,
                ),
                validator: (value) => value == null || value.isEmpty
                    ? _text('현재 비밀번호를 입력해 주세요.', 'โปรดกรอกรหัสผ่านปัจจุบัน')
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                enabled: !_submitting,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _text('새 비밀번호', 'รหัสผ่านใหม่'),
                  errorMaxLines: 3,
                ),
                validator: (value) =>
                    value == null ||
                        value.length < 8 ||
                        utf8.encode(value).length > 72
                    ? _text(
                        '8자 이상, 72바이트 이하로 입력해 주세요.',
                        'โปรดกรอกอย่างน้อย 8 ตัวอักษร และไม่เกิน 72 ไบต์',
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmation,
                enabled: !_submitting,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _text('새 비밀번호 확인', 'ยืนยันรหัสผ่านใหม่'),
                  errorMaxLines: 3,
                ),
                validator: (value) => value != _password.text
                    ? _text('새 비밀번호가 일치하지 않습니다.', 'รหัสผ่านใหม่ไม่ตรงกัน')
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(_text('취소', 'ยกเลิก')),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(
              _submitting
                  ? _text('변경 중…', 'กำลังเปลี่ยน…')
                  : _text('변경', 'เปลี่ยน'),
            ),
          ),
        ],
      ),
    );
  }
}
