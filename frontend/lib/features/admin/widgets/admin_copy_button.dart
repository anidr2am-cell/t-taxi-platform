import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/clipboard_writer.dart';
import '../../../widgets/app_ui.dart';

class AdminCopyButton extends StatelessWidget {
  const AdminCopyButton({
    super.key,
    required this.text,
    required this.label,
    this.copyText,
  });
  final String text;
  final String label;
  final Future<void> Function(String)? copyText;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty || text == '-') return const SizedBox.shrink();
    return SelectionContainer.disabled(
      child: IconButton(
        tooltip: context.l10n
            .t('admin_copy_action')
            .replaceAll('{field}', label),
        icon: const Icon(Icons.copy_outlined),
        onPressed: () async {
          var succeeded = false;
          try {
            await (copyText ?? writeClipboardText)(text);
            succeeded = true;
          } catch (_) {
            // Permissions and insecure origins can reject both clipboard methods.
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.t(
                    succeeded ? 'admin_copy_success' : 'admin_copy_failed',
                  ),
                ),
              ),
            );
        },
      ),
    );
  }
}

class AdminCopyRow extends StatelessWidget {
  const AdminCopyRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: AppUi.summaryRow(
          label: label,
          value: value.isEmpty ? '-' : value,
        ),
      ),
      AdminCopyButton(text: value, label: label),
    ],
  );
}
