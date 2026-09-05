import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_home_banner_api_service.dart';

class AdminHomeBannerPage extends StatefulWidget {
  const AdminHomeBannerPage({
    super.key,
    this.apiService,
    this.pickImageFile,
  });

  final AdminHomeBannerApiService? apiService;
  final Future<PlatformFile?> Function()? pickImageFile;

  @override
  State<AdminHomeBannerPage> createState() => _AdminHomeBannerPageState();
}

class _AdminHomeBannerPageState extends State<AdminHomeBannerPage> {
  final _orderController = TextEditingController();

  AdminHomeBannerApiService get _api =>
      widget.apiService ?? const AdminHomeBannerApiService();

  bool _loading = true;
  bool _uploading = false;
  String? _error;
  List<AdminHomeBannerItem> _banners = const [];
  final Map<int, Uint8List> _imageCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final banners = await _api.listBanners();
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _loading = false;
      });
      await _prefetchImages(banners);
    } on AdminHomeBannerApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.t('ui_load_failed');
      });
    }
  }

  Future<void> _prefetchImages(List<AdminHomeBannerItem> banners) async {
    for (final banner in banners) {
      if (_imageCache.containsKey(banner.id)) continue;
      try {
        final bytes = await _api.fetchImageBytes(banner.imageUrl);
        if (!mounted) return;
        setState(() => _imageCache[banner.id] = bytes);
      } catch (_) {}
    }
  }

  Future<PlatformFile?> _pickImageFile() async {
    if (widget.pickImageFile != null) return widget.pickImageFile!();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    return picked?.files.single;
  }

  Future<void> _uploadBanner() async {
    final file = await _pickImageFile();
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    final orderText = _orderController.text.trim();
    final displayOrder = orderText.isEmpty ? null : int.tryParse(orderText);

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      await _api.createBanner(
        bytes: bytes,
        filename: file.name,
        displayOrder: displayOrder,
      );
      if (!mounted) return;
      _orderController.clear();
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_home_banner_create_success'))),
      );
      await _load();
    } on AdminHomeBannerApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = context.l10n.t('admin_home_banner_create_failed');
      });
    }
  }

  Future<void> _toggleActive(AdminHomeBannerItem banner) async {
    try {
      await _api.updateBanner(
        bannerId: banner.id,
        isActive: !banner.isActive,
      );
      if (!mounted) return;
      await _load();
    } on AdminHomeBannerApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _updateOrder(AdminHomeBannerItem banner, int displayOrder) async {
    try {
      await _api.updateBanner(
        bannerId: banner.id,
        displayOrder: displayOrder,
      );
      if (!mounted) return;
      await _load();
    } on AdminHomeBannerApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _deleteBanner(AdminHomeBannerItem banner) async {
    try {
      await _api.deleteBanner(banner.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_home_banner_delete_success'))),
      );
      await _load();
    } on AdminHomeBannerApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppUi.centeredContent(
      child: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          AppUi.sectionHeader(context, title: l10n.t('admin_home_banner_title')),
          AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _orderController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_home_banner_order_label'),
                    helperText: l10n.t('admin_home_banner_order_hint'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _uploadBanner,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l10n.t('admin_home_banner_upload_button')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(_error!, style: const TextStyle(color: AppTokens.error)),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppTokens.spaceLg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_banners.isEmpty)
            AppUi.surfaceCard(child: Text(l10n.t('admin_home_banner_empty')))
          else
            ..._banners.map((banner) {
              final bytes = _imageCache[banner.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                child: AppUi.surfaceCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                          child: Image.memory(
                            bytes,
                            width: 96,
                            height: 54,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 96,
                          height: 54,
                          child: Icon(Icons.image_outlined),
                        ),
                      const SizedBox(width: AppTokens.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('#${banner.id}'),
                            Text(
                              '${l10n.t('admin_home_banner_order_label')}: ${banner.displayOrder}',
                            ),
                            Text(
                              banner.isActive
                                  ? l10n.t('admin_home_banner_active')
                                  : l10n.t('admin_home_banner_inactive'),
                            ),
                            const SizedBox(height: AppTokens.spaceSm),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: l10n.t('admin_home_banner_move_up'),
                                  onPressed: banner.displayOrder <= 0
                                      ? null
                                      : () => _updateOrder(
                                            banner,
                                            banner.displayOrder - 1,
                                          ),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: l10n.t('admin_home_banner_move_down'),
                                  onPressed: () => _updateOrder(
                                    banner,
                                    banner.displayOrder + 1,
                                  ),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Switch(
                            value: banner.isActive,
                            onChanged: (_) => _toggleActive(banner),
                          ),
                          IconButton(
                            tooltip: l10n.t('admin_home_banner_delete'),
                            onPressed: () => _deleteBanner(banner),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
