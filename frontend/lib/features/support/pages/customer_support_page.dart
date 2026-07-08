import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/support_inquiry_api_service.dart';

class CustomerSupportPage extends StatelessWidget {
  const CustomerSupportPage({super.key, this.api});

  final SupportInquiryApiService? api;

  Future<void> _openInquiry(BuildContext context) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.88,
          child: _SupportChatPanel(
            api: api ?? SupportInquiryApiService(),
            onClose: () => Navigator.pop(context),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppTokens.spaceLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: _SupportChatPanel(
            api: api ?? SupportInquiryApiService(),
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    );
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppUi.sectionHeader(
                        context,
                        title: l10n.t('support_title'),
                        subtitle: l10n.t('support_page_intro'),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('support_open_inquiry_button'),
                          onPressed: () => _openInquiry(context),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text(l10n.t('support_inquiry_button')),
                        ),
                      ),
                    ],
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

class _SupportChatPanel extends StatefulWidget {
  const _SupportChatPanel({required this.api, required this.onClose});

  final SupportInquiryApiService api;
  final VoidCallback onClose;

  @override
  State<_SupportChatPanel> createState() => _SupportChatPanelState();
}

class _SupportChatPanelState extends State<_SupportChatPanel> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_SupportMessage> _messages = [];
  final List<_SupportAttachment> _attachments = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

  Future<void> _sendMessage() async {
    if (_submitting) return;
    final text = _messageController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    final sentAttachments = List<_SupportAttachment>.from(_attachments);
    final displayText = text.isNotEmpty
        ? text
        : sentAttachments.map((file) => file.name).join(', ');

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final receipt = await widget.api.submit(
        message: displayText,
        locale: Localizations.localeOf(context).languageCode,
        attachments: sentAttachments
            .map(
              (file) => SupportInquiryAttachmentDraft(
                name: file.name,
                bytes: file.bytes,
              ),
            )
            .toList(growable: false),
      );
      if (!mounted) return;
      final receiptMessage = receipt.publicId.isEmpty
          ? context.l10n.t('support_auto_receipt')
          : '${context.l10n.t('support_auto_receipt')}\n${context.l10n.t('support_receipt_number')}: ${receipt.publicId}';
      setState(() {
        _messages
          ..add(
            _SupportMessage(
              displayText,
              isUser: true,
              attachments: sentAttachments,
            ),
          )
          ..add(_SupportMessage(receiptMessage));
        _attachments.clear();
        _messageController.clear();
        _submitting = false;
      });
      _scrollToLatest();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('support_submit_failed'),
        );
        _submitting = false;
      });
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceSm,
                AppTokens.spaceSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.t('support_dialog_title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('support_close_button'),
                    tooltip: l10n.t('support_close_button'),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const Key('support_message_area'),
                controller: _scrollController,
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                children: [
                  _MessageBubble(
                    message: _SupportMessage(l10n.t('support_default_guide')),
                  ),
                  for (final message in _messages)
                    _MessageBubble(message: message),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('support_message_input'),
                    controller: _messageController,
                    enabled: !_submitting,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: l10n.t('support_input_label'),
                      hintText: l10n.t('support_input_hint'),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  _AttachmentPreview(attachments: _attachments),
                  if (_error != null) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    Text(
                      _error!,
                      key: const Key('support_error_message'),
                      style: const TextStyle(color: AppTokens.error),
                    ),
                  ],
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    l10n.t('support_attachment_help'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 520;
                      final attachButton = OutlinedButton.icon(
                        key: const Key('support_attach_button'),
                        onPressed: _submitting ? null : _pickImages,
                        icon: const Icon(Icons.attach_file),
                        label: Text(l10n.t('support_attach_button')),
                      );
                      final sendButton = FilledButton.icon(
                        key: const Key('support_send_button'),
                        onPressed: _submitting ? null : _sendMessage,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(
                          _submitting
                              ? l10n.t('support_sending')
                              : l10n.t('support_send_button'),
                        ),
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

                      return Row(
                        children: [attachButton, const Spacer(), sendButton],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
          color: isUser ? AppTokens.primary : AppTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: isUser ? AppTokens.primary : AppTokens.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : AppTokens.textPrimary,
                height: 1.4,
              ),
            ),
            if (message.attachments.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSm),
              _AttachmentPreview(
                attachments: message.attachments,
                muted: isUser,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachments, this.muted = false});

  final List<_SupportAttachment> attachments;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (attachments.isEmpty) {
      return Text(
        l10n.t('support_no_attachments'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: muted ? Colors.white70 : AppTokens.textMuted,
        ),
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
              color: muted
                  ? Colors.white.withValues(alpha: 0.12)
                  : AppTokens.primaryLight,
              borderRadius: AppTokens.borderRadiusMd,
              border: Border.all(
                color: muted ? Colors.white30 : AppTokens.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AttachmentThumb(attachment: attachment, muted: muted),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: muted ? Colors.white : AppTokens.textPrimary,
                    ),
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
  const _AttachmentThumb({required this.attachment, required this.muted});

  final _SupportAttachment attachment;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.image_outlined,
      color: muted ? Colors.white : AppTokens.primary,
    );
    final bytes = attachment.bytes;
    if (bytes == null || bytes.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: AppTokens.borderRadiusSm,
      child: Image.memory(
        bytes,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

class _SupportMessage {
  const _SupportMessage(
    this.text, {
    this.isUser = false,
    this.attachments = const [],
  });

  final String text;
  final bool isUser;
  final List<_SupportAttachment> attachments;
}

class _SupportAttachment {
  const _SupportAttachment({required this.name, this.bytes});

  final String name;
  final Uint8List? bytes;
}
