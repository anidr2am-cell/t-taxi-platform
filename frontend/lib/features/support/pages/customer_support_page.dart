import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';

class CustomerSupportPage extends StatefulWidget {
  const CustomerSupportPage({super.key});

  @override
  State<CustomerSupportPage> createState() => _CustomerSupportPageState();
}

class _CustomerSupportPageState extends State<CustomerSupportPage> {
  final _messageController = TextEditingController();
  final List<_SupportMessage> _messages = [];
  final List<_SupportAttachment> _attachments = [];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    setState(() {
      _attachments
        ..clear()
        ..addAll(
          result.files
              .where((file) => file.name.trim().isNotEmpty)
              .map(
                (file) =>
                    _SupportAttachment(name: file.name, bytes: file.bytes),
              ),
        );
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    final attachmentNames = _attachments.map((file) => file.name).join(', ');
    final displayText = [
      if (text.isNotEmpty) text,
      if (attachmentNames.isNotEmpty) attachmentNames,
    ].join('\n');

    setState(() {
      _messages
        ..add(_SupportMessage(displayText, isUser: true))
        ..add(_SupportMessage(context.l10n.t('support_auto_receipt')));
      _attachments.clear();
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width >= 900 ? 920.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(title: Text(l10n.t('support_title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: AppUi.pagePadding(context),
              children: [
                AppUi.surfaceCard(
                  padding: const EdgeInsets.all(AppTokens.spaceLg),
                  child: _InquirySection(
                    messages: _messages,
                    attachments: _attachments,
                    messageController: _messageController,
                    onAttach: _pickImages,
                    onSend: _sendMessage,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  padding: const EdgeInsets.all(AppTokens.spaceLg),
                  child: const _FaqSection(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InquirySection extends StatelessWidget {
  const _InquirySection({
    required this.messages,
    required this.attachments,
    required this.messageController,
    required this.onAttach,
    required this.onSend,
  });

  final List<_SupportMessage> messages;
  final List<_SupportAttachment> attachments;
  final TextEditingController messageController;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('support_inquiry_title'),
          subtitle: l10n.t('support_inquiry_subtitle'),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Container(
          key: const Key('support_message_area'),
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          decoration: BoxDecoration(
            color: AppTokens.surfaceMuted,
            borderRadius: AppTokens.borderRadiusMd,
            border: Border.all(color: AppTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MessageBubble(
                message: _SupportMessage(l10n.t('support_default_guide')),
              ),
              for (final message in messages) _MessageBubble(message: message),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        TextField(
          key: const Key('support_message_input'),
          controller: messageController,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: l10n.t('support_input_label'),
            hintText: l10n.t('support_input_hint'),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _AttachmentPreview(attachments: attachments),
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          l10n.t('support_attachment_help'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final attachButton = OutlinedButton.icon(
              key: const Key('support_attach_button'),
              onPressed: onAttach,
              icon: const Icon(Icons.attach_file),
              label: Text(l10n.t('support_attach_button')),
            );
            final sendButton = FilledButton.icon(
              key: const Key('support_send_button'),
              onPressed: onSend,
              icon: const Icon(Icons.send_outlined),
              label: Text(l10n.t('support_send_button')),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  attachButton,
                  const SizedBox(height: AppTokens.spaceSm),
                  sendButton,
                ],
              );
            }

            return Row(children: [attachButton, const Spacer(), sendButton]);
          },
        ),
      ],
    );
  }
}

class _FaqSection extends StatelessWidget {
  const _FaqSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppUi.sectionHeader(context, title: l10n.t('support_faq_title')),
        Text(
          l10n.t('support_faq_placeholder'),
          key: const Key('support_faq_placeholder'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTokens.textSecondary),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: isUser ? const Key('support_user_message') : null,
        margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTokens.primary : AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: isUser ? AppTokens.primary : AppTokens.border,
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : AppTokens.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachments});

  final List<_SupportAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (attachments.isEmpty) {
      return Text(
        l10n.t('support_no_attachments'),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTokens.textMuted),
      );
    }

    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: [
        for (final attachment in attachments)
          Container(
            key: const Key('support_attachment_preview'),
            width: 160,
            padding: const EdgeInsets.all(AppTokens.spaceSm),
            decoration: BoxDecoration(
              color: AppTokens.primaryLight,
              borderRadius: AppTokens.borderRadiusMd,
              border: Border.all(color: AppTokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AttachmentThumb(attachment: attachment),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.attachment});

  final _SupportAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final bytes = attachment.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const Icon(Icons.image_outlined, color: AppTokens.primary);
    }

    return ClipRRect(
      borderRadius: AppTokens.borderRadiusSm,
      child: Image.memory(
        bytes,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.image_outlined, color: AppTokens.primary),
      ),
    );
  }
}

class _SupportMessage {
  const _SupportMessage(this.text, {this.isUser = false});

  final String text;
  final bool isUser;
}

class _SupportAttachment {
  const _SupportAttachment({required this.name, this.bytes});

  final String name;
  final Uint8List? bytes;
}
