import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/support_inquiry_api_service.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';

class CustomerSupportPage extends StatelessWidget {
  const CustomerSupportPage({super.key, this.api, this.settingsApi});

  final SupportInquiryApiService? api;
  final PlatformSettingsApiService? settingsApi;

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
                const SizedBox(height: AppTokens.spaceMd),
                _LineInquirySection(
                  api: settingsApi ?? const PlatformSettingsApiService(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineInquirySection extends StatelessWidget {
  const _LineInquirySection({required this.api});

  final PlatformSettingsApiService api;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: FutureBuilder<Map<String, dynamic>>(
        future: api.getPublic(),
        builder: (context, snapshot) {
          final path = snapshot.data?['lineQrImageUrl'] as String?;
          final description = (snapshot.data?['lineQrDescription'] as String?)
              ?.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('support_line_inquiry'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              if (description != null && description.isNotEmpty) ...[
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTokens.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              if (path == null || path.isEmpty)
                Text(l10n.t('support_line_qr_missing'))
              else
                Image.network(
                  api.assetUri(path).toString(),
                  height: 240,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      Text(l10n.t('support_line_qr_missing')),
                ),
            ],
          );
        },
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
  static const _pollInterval = Duration(seconds: 12);

  final _messageController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _kakaoController = TextEditingController();
  final _lineController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_SupportMessage> _messages = [];
  final List<_SupportMessage> _systemMessages = [];
  final List<_SupportAttachment> _attachments = [];
  bool _submitting = false;
  bool _loadingThread = false;
  String? _error;
  SupportInquiryLookup? _lookup;

  @override
  void initState() {
    super.initState();
    _loadStoredThread();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _kakaoController.dispose();
    _lineController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Timer? _pollTimer;

  Future<void> _loadStoredThread() async {
    setState(() => _loadingThread = true);
    final lookup = await widget.api.loadLatestLookup();
    if (!mounted) return;
    if (lookup == null) {
      setState(() => _loadingThread = false);
      return;
    }
    _lookup = lookup;
    await _refreshThread(showError: false);
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) _refreshThread(showError: false);
    });
  }

  Future<void> _refreshThread({required bool showError}) async {
    final lookup = _lookup;
    if (lookup == null) return;
    try {
      final thread = await widget.api.getThread(
        publicId: lookup.publicId,
        lookupToken: lookup.token,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            thread.messages
                .where((message) => message.message.trim().isNotEmpty)
                .map(
                  (message) => _SupportMessage(
                    message.message,
                    isUser: message.senderType == 'CUSTOMER',
                    senderType: message.senderType,
                  ),
                ),
          );
        _loadingThread = false;
      });
      _scrollToLatest();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingThread = false;
        if (showError) {
          _error = userFacingError(
            err,
            fallback: context.l10n.t('support_thread_load_failed'),
          );
        }
      });
    }
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
        customerName: _nameController.text,
        customerPhone: _phoneController.text,
        kakaoId: _kakaoController.text,
        lineId: _lineController.text,
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
      await widget.api.saveLatestLookup(receipt);
      if (!mounted) return;
      final receiptMessage = receipt.publicId.isEmpty
          ? context.l10n.t('support_auto_receipt')
          : '${context.l10n.t('support_auto_receipt')}\n${context.l10n.t('support_receipt_number')}: ${receipt.publicId}';
      setState(() {
        if (receipt.lookupToken != null && receipt.lookupToken!.isNotEmpty) {
          _lookup = SupportInquiryLookup(
            publicId: receipt.publicId,
            token: receipt.lookupToken!,
          );
        }
        _messages.add(
          _SupportMessage(
            displayText,
            isUser: true,
            senderType: 'CUSTOMER',
            attachments: sentAttachments,
          ),
        );
        _systemMessages
          ..clear()
          ..add(_SupportMessage(receiptMessage, senderType: 'SYSTEM'));
        _attachments.clear();
        _messageController.clear();
        _submitting = false;
      });
      if (_lookup != null) _startPolling();
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
                  _SupportContactCard(
                    enabled: !_submitting,
                    nameController: _nameController,
                    phoneController: _phoneController,
                    kakaoController: _kakaoController,
                    lineController: _lineController,
                  ),
                  if (_loadingThread)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                      child: Text(
                        l10n.t('support_thread_loading'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.textMuted,
                        ),
                      ),
                    ),
                  for (final message in _messages)
                    _MessageBubble(message: message),
                  for (final message in _systemMessages)
                    _MessageBubble(message: message),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.56,
              ),
              child: SingleChildScrollView(
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
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportContactCard extends StatelessWidget {
  const _SupportContactCard({
    required this.enabled,
    required this.nameController,
    required this.phoneController,
    required this.kakaoController,
    required this.lineController,
  });

  final bool enabled;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController kakaoController;
  final TextEditingController lineController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const Key('support_contact_section'),
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: AppTokens.primaryLight,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('support_contact_help'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTokens.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.t('support_contact_messenger_help'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTokens.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _ContactFields(
            enabled: enabled,
            nameController: nameController,
            phoneController: phoneController,
            kakaoController: kakaoController,
            lineController: lineController,
          ),
        ],
      ),
    );
  }
}

class _ContactFields extends StatelessWidget {
  const _ContactFields({
    required this.enabled,
    required this.nameController,
    required this.phoneController,
    required this.kakaoController,
    required this.lineController,
  });

  final bool enabled;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController kakaoController;
  final TextEditingController lineController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 560;
        final fields = [
          _ContactField(
            key: const Key('support_customer_name_input'),
            controller: nameController,
            enabled: enabled,
            label: l10n.t('support_contact_name'),
          ),
          _ContactField(
            key: const Key('support_customer_phone_input'),
            controller: phoneController,
            enabled: enabled,
            label: l10n.t('support_contact_phone'),
            keyboardType: TextInputType.phone,
          ),
          _ContactField(
            key: const Key('support_kakao_input'),
            controller: kakaoController,
            enabled: enabled,
            label: l10n.t('support_contact_kakao'),
          ),
          _ContactField(
            key: const Key('support_line_input'),
            controller: lineController,
            enabled: enabled,
            label: l10n.t('support_contact_line'),
          ),
        ];

        if (!twoColumns) {
          return Column(
            children: [
              for (final field in fields) ...[
                field,
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ],
          );
        }

        return Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: [
            for (final field in fields)
              SizedBox(
                width: (constraints.maxWidth - AppTokens.spaceSm) / 2,
                child: field,
              ),
          ],
        );
      },
    );
  }
}

class _ContactField extends StatelessWidget {
  const _ContactField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    this.keyboardType,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
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
    this.senderType = 'SYSTEM',
    this.attachments = const [],
  });

  final String text;
  final bool isUser;
  final String senderType;
  final List<_SupportAttachment> attachments;
}

class _SupportAttachment {
  const _SupportAttachment({required this.name, this.bytes});

  final String name;
  final Uint8List? bytes;
}
