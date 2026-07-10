import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';

String? chatRoleLabel(Map<String, dynamic> message, AppLocalizations l10n) {
  final rawRole =
      message['senderType'] ??
      message['senderRole'] ??
      message['sender_role'] ??
      message['role'];
  final role = rawRole is String ? rawRole.toUpperCase() : '';
  final displayName = (message['senderDisplayName'] as String? ?? '')
      .toLowerCase();

  if (role.contains('SYSTEM') || displayName.contains('system')) {
    return l10n.t('chat_role_system');
  }
  if (role.contains('ADMIN') || displayName.contains('admin')) {
    return l10n.t('chat_role_admin');
  }
  if (role.contains('DRIVER') || displayName.contains('driver')) {
    return l10n.t('chat_role_driver');
  }
  if (role.contains('CUSTOMER') ||
      role.contains('GUEST') ||
      displayName.contains('customer') ||
      displayName.contains('guest')) {
    return l10n.t('chat_role_customer');
  }
  return null;
}

AppStatusTone chatRoleTone(Map<String, dynamic> message) {
  final rawRole =
      message['senderType'] ??
      message['senderRole'] ??
      message['sender_role'] ??
      message['role'];
  final role = rawRole is String ? rawRole.toUpperCase() : '';
  final displayName = (message['senderDisplayName'] as String? ?? '')
      .toLowerCase();

  if (role.contains('SYSTEM') || displayName.contains('system')) {
    return AppStatusTone.neutral;
  }
  if (role.contains('ADMIN') || displayName.contains('admin')) {
    return AppStatusTone.warning;
  }
  if (role.contains('DRIVER') || displayName.contains('driver')) {
    return AppStatusTone.info;
  }
  return AppStatusTone.success;
}

class ChatRoleBadge extends StatelessWidget {
  const ChatRoleBadge({super.key, required this.message, required this.l10n});

  final Map<String, dynamic> message;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final label = chatRoleLabel(message, l10n);
    if (label == null) return const SizedBox.shrink();
    return AppUi.statusBadge(label, tone: chatRoleTone(message));
  }
}
