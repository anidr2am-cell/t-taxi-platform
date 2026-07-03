import 'package:flutter/material.dart';

import '../../../features/driver_application/models/driver_application_models.dart';
import '../../../features/driver_application/services/driver_application_api_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import 'admin_driver_application_detail_page.dart';

class AdminDriverApplicationListPage extends StatefulWidget {
  const AdminDriverApplicationListPage({super.key, this.api});

  final DriverApplicationApiService? api;

  @override
  State<AdminDriverApplicationListPage> createState() =>
      _AdminDriverApplicationListPageState();
}

class _AdminDriverApplicationListPageState
    extends State<AdminDriverApplicationListPage> {
  late final DriverApplicationApiService _api =
      widget.api ?? DriverApplicationApiService();
  final _search = TextEditingController();

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _status;
  String? _countryCode;
  String? _vehicleTypeCode;
  int _page = 1;
  int _total = 0;
  final int _limit = 20;
  List<DriverApplicationAdminListItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load(page: 1);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required int page, bool append = false}) async {
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final data = await _api.listAdminApplications(
        page: page,
        limit: _limit,
        status: _status,
        countryCode: _countryCode,
        vehicleTypeCode: _vehicleTypeCode,
        search: _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _total = data.total;
        _items = append ? [..._items, ...data.items] : data.items;
        _loading = false;
        _loadingMore = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openDetail(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDriverApplicationDetailPage(
          id: id,
          api: _api,
          onChanged: () => _load(page: 1),
        ),
      ),
    );
    if (mounted) _load(page: 1);
  }

  String _label(String status) {
    switch (status) {
      case 'APPROVED':
        return context.l10n.t('driver_application_status_approved');
      case 'REJECTED':
        return context.l10n.t('driver_application_status_rejected');
      default:
        return context.l10n.t('driver_application_status_pending');
    }
  }

  AppStatusTone _tone(String status) {
    switch (status) {
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
        return AppStatusTone.error;
      default:
        return AppStatusTone.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: AppUi.pagePadding(
            context,
          ).copyWith(bottom: AppTokens.spaceSm),
          child: AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppUi.sectionHeader(
                  context,
                  title: l10n.t('admin_driver_application_title'),
                  subtitle: l10n.t('admin_driver_application_subtitle'),
                  trailing: IconButton(
                    tooltip: l10n.t('admin_dispatch_refresh'),
                    onPressed: () => _load(page: 1),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_driver_application_search'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _load(page: 1),
                    ),
                  ),
                  onSubmitted: (_) => _load(page: 1),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DropdownButton<String?>(
                      value: _status,
                      hint: Text(
                        l10n.t('admin_driver_application_all_statuses'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            l10n.t('admin_driver_application_all_statuses'),
                          ),
                        ),
                        ...['PENDING', 'APPROVED', 'REJECTED'].map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(_label(status)),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _status = value);
                        _load(page: 1);
                      },
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: l10n.t('country'),
                          isDense: true,
                        ),
                        onChanged: (value) =>
                            _countryCode = value.trim().toUpperCase(),
                        onSubmitted: (_) => _load(page: 1),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: l10n.t('driver_application_vehicle_type'),
                          isDense: true,
                        ),
                        onChanged: (value) =>
                            _vehicleTypeCode = value.trim().toUpperCase(),
                        onSubmitted: (_) => _load(page: 1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _body(l10n)),
      ],
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return AppUi.loadingState();
    if (_error != null) {
      return AppUi.errorState(
        message: _error!,
        retryLabel: l10n.t('ui_retry'),
        onRetry: () => _load(page: 1),
      );
    }
    if (_items.isEmpty) {
      return AppUi.emptyState(
        title: l10n.t('admin_driver_application_empty'),
        icon: Icons.person_add_disabled_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return ListView.builder(
            padding: AppUi.pagePadding(context).copyWith(top: 0),
            itemCount: _items.length + (_items.length < _total ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return Center(
                  child: _loadingMore
                      ? const CircularProgressIndicator()
                      : OutlinedButton(
                          onPressed: () => _load(page: _page + 1, append: true),
                          child: Text(l10n.t('admin_dispatch_load_more')),
                        ),
                );
              }
              final item = _items[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppUi.adminQueueCard(
                  onTap: () => _openDetail(item.id),
                  backgroundColor: item.status == 'PENDING'
                      ? AppTokens.warningLight
                      : null,
                  child: wide ? _wideRow(item) : _card(item),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _wideRow(DriverApplicationAdminListItem item) {
    return Row(
      children: [
        Expanded(flex: 2, child: _titleBlock(item)),
        Expanded(child: Text(item.email)),
        Expanded(child: Text(item.phone)),
        Expanded(child: Text(item.countryCode ?? '-')),
        Expanded(child: Text(item.vehicleTypeCode)),
        Expanded(child: Text(item.vehiclePlateNumber)),
        Expanded(child: Text(item.submittedAt)),
        AppUi.statusBadge(_label(item.status), tone: _tone(item.status)),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: AppTokens.textMuted),
      ],
    );
  }

  Widget _card(DriverApplicationAdminListItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _titleBlock(item)),
            AppUi.statusBadge(_label(item.status), tone: _tone(item.status)),
          ],
        ),
        const SizedBox(height: 8),
        Text('${item.email} · ${item.phone}'),
        const SizedBox(height: 4),
        Text(
          '${item.vehicleTypeCode} · ${item.vehiclePlateNumber}',
          style: const TextStyle(color: AppTokens.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          item.submittedAt,
          style: const TextStyle(color: AppTokens.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _titleBlock(DriverApplicationAdminListItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.applicationNumber,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Text(
          item.fullName,
          style: const TextStyle(color: AppTokens.textSecondary),
        ),
      ],
    );
  }
}
