import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../models/driver_application_models.dart';

class DriverRegistrationPhotoUploadCard extends StatelessWidget {
  const DriverRegistrationPhotoUploadCard({
    super.key,
    required this.fieldKey,
    required this.title,
    required this.description,
    required this.files,
    required this.isRequired,
    required this.showMissing,
    required this.processing,
    required this.selectLabel,
    required this.showSelectButton,
    this.disabledSelectLabel,
    this.onSelect,
    this.onRemoveAll,
    this.onRemoveFile,
    this.errorText,
    this.missingText,
    this.countText,
    this.maxPreviewFiles = 3,
  });

  final String fieldKey;
  final String title;
  final String description;
  final List<DriverApplicationUploadFile> files;
  final bool isRequired;
  final bool showMissing;
  final bool processing;
  final String selectLabel;
  final bool showSelectButton;
  final String? disabledSelectLabel;
  final VoidCallback? onSelect;
  final VoidCallback? onRemoveAll;
  final void Function(int index)? onRemoveFile;
  final String? errorText;
  final String? missingText;
  final String? countText;
  final int maxPreviewFiles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasFiles = files.isNotEmpty;
    final visibleError = errorText ?? (showMissing ? missingText : null);
    final borderColor = visibleError != null
        ? AppTokens.error
        : hasFiles
        ? AppTokens.success
        : AppTokens.border;
    final statusColor = visibleError != null
        ? AppTokens.error
        : hasFiles
        ? AppTokens.success
        : AppTokens.textSecondary;

    return Semantics(
      label: '$title ${_statusText(l10n, hasFiles, visibleError)}',
      child: Container(
        key: ValueKey('driver_application_file_card_$fieldKey'),
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stateIcon(statusColor),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppTokens.spaceXs,
                        runSpacing: AppTokens.spaceXs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (isRequired)
                            _Badge(
                              text: l10n.t('driver_apply_upload_required'),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _statusText(l10n, hasFiles, visibleError),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: statusColor),
                ),
                if (countText != null)
                  _CountBadge(text: countText!, color: statusColor),
              ],
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSm),
              _FilePreviewList(
                files: files,
                maxPreviewFiles: maxPreviewFiles,
                onRemoveFile: onRemoveFile,
                processing: processing,
              ),
            ],
            if (visibleError != null) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                visibleError,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTokens.error),
              ),
            ],
            const SizedBox(height: AppTokens.spaceMd),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                if (showSelectButton)
                  OutlinedButton.icon(
                    key: ValueKey('driver_application_file_select_$fieldKey'),
                    onPressed: processing ? null : onSelect,
                    icon: processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      processing
                          ? l10n.t('driver_apply_upload_processing')
                          : selectLabel,
                    ),
                  ),
                if (!showSelectButton && disabledSelectLabel != null)
                  OutlinedButton.icon(
                    key: ValueKey(
                      'driver_application_file_select_disabled_$fieldKey',
                    ),
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(disabledSelectLabel!),
                  ),
                if (hasFiles && onRemoveAll != null)
                  TextButton.icon(
                    key: ValueKey('driver_application_file_remove_$fieldKey'),
                    onPressed: processing ? null : onRemoveAll,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.t('driver_apply_upload_remove')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateIcon(Color color) {
    if (processing) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return Icon(
      errorText != null || showMissing
          ? Icons.error_outline
          : files.isNotEmpty
          ? Icons.check_circle_outline
          : Icons.image_outlined,
      color: color,
    );
  }

  String _statusText(
    AppLocalizations l10n,
    bool hasFiles,
    String? visibleError,
  ) {
    if (processing) return l10n.t('driver_apply_upload_processing');
    if (visibleError != null) return l10n.t('driver_apply_upload_error');
    if (hasFiles) return l10n.t('driver_apply_upload_selected');
    return l10n.t('driver_apply_upload_empty');
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTokens.errorLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppTokens.error),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _FilePreviewList extends StatelessWidget {
  const _FilePreviewList({
    required this.files,
    required this.maxPreviewFiles,
    required this.processing,
    this.onRemoveFile,
  });

  final List<DriverApplicationUploadFile> files;
  final int maxPreviewFiles;
  final bool processing;
  final void Function(int index)? onRemoveFile;

  @override
  Widget build(BuildContext context) {
    final visibleFiles = files.take(maxPreviewFiles).toList(growable: false);
    final hiddenCount = files.length - visibleFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: [
            for (final file in visibleFiles)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: _FilePreview(
                  file: file,
                  onRemove: onRemoveFile == null || processing
                      ? null
                      : () => onRemoveFile!(files.indexOf(file)),
                ),
              ),
          ],
        ),
        if (hiddenCount > 0) ...[
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            '+$hiddenCount',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.file, this.onRemove});

  final DriverApplicationUploadFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isPdf = file.name.toLowerCase().endsWith('.pdf');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              child: Container(
                width: 48,
                height: 48,
                color: AppTokens.surfaceMuted,
                child: isPdf
                    ? const Icon(Icons.picture_as_pdf_outlined)
                    : Image.memory(
                        Uint8List.fromList(file.bytes),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.image_outlined);
                        },
                      ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceXs),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fileSizeText(context, file),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: file.wasCompressed
                          ? AppTokens.success
                          : AppTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: -10,
            start: 36,
            child: IconButton.filledTonal(
              key: ValueKey('driver_application_file_remove_${file.name}'),
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              iconSize: 18,
              tooltip: context.l10n.t('driver_apply_upload_remove'),
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
  }

  String _fileSizeText(BuildContext context, DriverApplicationUploadFile file) {
    final l10n = context.l10n;
    final original = _formatBytes(file.displayOriginalByteLength);
    final upload = _formatBytes(file.uploadByteLength);
    if (file.wasCompressed) {
      return l10n
          .t('driver_apply_upload_optimized_size')
          .replaceAll('{original}', original)
          .replaceAll('{upload}', upload);
    }
    return l10n
        .t('driver_apply_upload_ready_size')
        .replaceAll('{size}', upload);
  }

  String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes < 1024) return '${bytes}B';
    if (bytes >= mb ~/ 10) {
      return '${(bytes / mb).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)}KB';
  }
}
