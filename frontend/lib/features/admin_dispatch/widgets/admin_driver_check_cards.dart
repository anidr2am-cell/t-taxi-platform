import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../admin/widgets/admin_copy_button.dart';
import '../utils/admin_driver_check_messages.dart';

class AdminDriverCheckCards extends StatelessWidget {
  const AdminDriverCheckCards({super.key, required this.detail, this.copyText});
  final Map<String, dynamic> detail;
  final Future<void> Function(String)? copyText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_driver_check_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('admin_driver_check_notice')),
          const SizedBox(height: AppTokens.spaceSm),
          for (final message in buildAdminDriverCheckMessages(detail))
            ExpansionTile(
              initiallyExpanded: true,
              key: ValueKey('adminDriverCheck-${message.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
              title: Row(
                children: [
                  Expanded(child: Text(l10n.t(message.titleKey))),
                  AdminCopyButton(
                    text: message.thai,
                    label:
                        '${l10n.t(message.titleKey)} · ${l10n.t('admin_driver_check_thai')}',
                    copyText: copyText,
                  ),
                ],
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.t('admin_driver_check_thai'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                SelectableText(message.thai),
                const SizedBox(height: AppTokens.spaceMd),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.t('admin_driver_check_korean'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                SelectableText(message.korean),
              ],
            ),
        ],
      ),
    );
  }
}
