import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';
import 'admin_booking_detail_page.dart';

class AdminDispatchQueuePage extends StatefulWidget {
  const AdminDispatchQueuePage({super.key, this.api});

  final AdminDispatchApiService? api;

  @override
  State<AdminDispatchQueuePage> createState() => _AdminDispatchQueuePageState();
}

class _AdminDispatchQueuePageState extends State<AdminDispatchQueuePage> {
  late final AdminDispatchApiService _api =
      widget.api ?? const AdminDispatchApiService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<dynamic> _items = [];
  int _page = 1;
  int _total = 0;
  final int _limit = 20;
  String? _statusFilter;
  String? _assignmentFilter;
  String? _dateFrom;
  String? _dateTo;
  bool _needsLogin = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final token = await _api.getSavedToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _needsLogin = true;
        _loading = false;
      });
      return;
    }
    await _load(page: 1);
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      setState(() => _needsLogin = false);
      await _load(page: 1);
    } catch (err) {
      setState(() {
        _loading = false;
        _error = userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
      });
    }
  }

  Future<void> _load({required int page, bool append = false}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.listBookings(
        search: _searchController.text.trim(),
        status: _statusFilter,
        assignmentState: _assignmentFilter,
        serviceDateFrom: _dateFrom,
        serviceDateTo: _dateTo,
        page: page,
        limit: _limit,
      );
      final items = data['items'] as List<dynamic>? ?? [];
      setState(() {
        _page = page;
        _total = data['total'] as int? ?? items.length;
        _items = append ? [..._items, ...items] : items;
        _loading = false;
        _loadingMore = false;
      });
    } catch (err) {
      final token = await _api.getSavedToken();
      setState(() {
        if (token == null || token.isEmpty) {
          _needsLogin = true;
          _error = null;
        } else {
          _error = userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
        }
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openDetail(String bookingNumber) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _api,
          onChanged: () => _load(page: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_needsLogin) {
      return _buildLogin(l10n);
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: AppUi.pagePadding(context).copyWith(bottom: AppTokens.spaceSm),
            child: AppUi.surfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: l10n.t('admin_dispatch_search'),
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
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _filterChip(
                        label: l10n.t('status'),
                        child: DropdownButton<String?>(
                          value: _statusFilter,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          hint: Text(l10n.t('admin_dispatch_all_statuses')),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(l10n.t('admin_dispatch_all_statuses')),
                            ),
                            DropdownMenuItem(
                              value: 'PENDING',
                              child: Text(l10n.t('status_pending')),
                            ),
                            DropdownMenuItem(
                              value: 'DRIVER_ASSIGNED',
                              child: Text(l10n.t('status_driver_assigned')),
                            ),
                            DropdownMenuItem(
                              value: 'COMPLETED',
                              child: Text(l10n.t('status_completed')),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _statusFilter = v);
                            _load(page: 1);
                          },
                        ),
                      ),
                      _filterChip(
                        label: l10n.t('admin_dispatch_assignment'),
                        child: DropdownButton<String?>(
                          value: _assignmentFilter,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          hint: Text(l10n.t('admin_dispatch_all_assignments')),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(l10n.t('admin_dispatch_all_assignments')),
                            ),
                            DropdownMenuItem(
                              value: 'UNASSIGNED',
                              child: Text(l10n.t('admin_dispatch_unassigned')),
                            ),
                            DropdownMenuItem(
                              value: 'ASSIGNED',
                              child: Text(l10n.t('admin_dispatch_assigned')),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _assignmentFilter = v);
                            _load(page: 1);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.t('admin_dispatch_refresh'),
                        onPressed: () => _load(page: 1),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return AppUi.loadingState();
    }
    if (_error != null) {
      return AppUi.errorState(
        message: _error!,
        onRetry: () => _load(page: 1),
        retryLabel: l10n.t('admin_dispatch_retry'),
      );
    }
    if (_items.isEmpty) {
      return AppUi.emptyState(
        title: l10n.t('admin_dispatch_empty'),
        icon: Icons.inbox_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return ListView.builder(
            itemCount: _items.length + (_items.length < _total ? 1 : 0),
            padding: AppUi.pagePadding(context).copyWith(top: 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Center(
                    child: _loadingMore
                        ? const CircularProgressIndicator()
                        : OutlinedButton(
                            onPressed: () => _load(page: _page + 1, append: true),
                            child: Text(l10n.t('admin_dispatch_load_more')),
                          ),
                  ),
                );
              }

              final item = Map<String, dynamic>.from(_items[index] as Map);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BookingListCard(
                  item: item,
                  l10n: l10n,
                  wide: wide,
                  onTap: () => _openDetail(item['bookingNumber'] as String),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLogin(AppLocalizations l10n) {
    return Scaffold(
      body: AppUi.centeredContent(
        maxWidth: 400,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: AppUi.surfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppUi.sectionHeader(
                  context,
                  title: l10n.t('admin_dispatch_login_title'),
                ),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: l10n.t('email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                if (_error != null) AppUi.errorState(message: _error!),
                AppUi.primaryButton(
                  label: l10n.t('admin_dispatch_login'),
                  icon: Icons.login,
                  onPressed: _login,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingListCard extends StatelessWidget {
  const _BookingListCard({
    required this.item,
    required this.l10n,
    required this.wide,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final AppLocalizations l10n;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final assignment = item['activeAssignment'] is Map
        ? Map<String, dynamic>.from(item['activeAssignment'] as Map)
        : null;
    final unassigned = assignment == null;
    final driverName = assignment?['driverDisplayName'] as String?;
    final assignmentLabel = driverName == null || driverName.isEmpty
        ? l10n.t('admin_dispatch_unassigned')
        : driverName;
    final status = item['status'] as String? ?? '';
    final amount = item['totalAmount'];
    final currency = item['currency'] as String? ?? '';
    final amountLabel = amount != null ? '$amount $currency' : '-';

    return AppUi.surfaceCard(
      onTap: onTap,
      backgroundColor: unassigned ? AppTokens.warningLight : AppTokens.surface,
      padding: const EdgeInsets.all(14),
      child: wide ? _wideLayout(status, assignmentLabel, amountLabel, unassigned) : _narrowLayout(status, assignmentLabel, amountLabel, unassigned),
    );
  }

  Widget _headerRow(String status, bool unassigned) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            item['bookingNumber'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppUi.statusBadge(status, tone: AppUi.toneForBookingStatus(status)),
            const SizedBox(height: 6),
            AppUi.statusBadge(
              unassigned ? 'UNASSIGNED' : 'ASSIGNED',
              tone: unassigned ? AppStatusTone.warning : AppStatusTone.success,
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaColumn(String assignmentLabel, String amountLabel, bool unassigned) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          '${item['origin']} → ${item['destination']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${item['scheduledPickupAt'] ?? '-'} · ${item['customerDisplayName'] ?? '-'}',
          style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              unassigned ? Icons.person_off_outlined : Icons.person_outline,
              size: 16,
              color: unassigned ? AppTokens.warning : AppTokens.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${l10n.t('admin_dispatch_assigned_driver')}: $assignmentLabel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: unassigned ? AppTokens.warning : AppTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          amountLabel,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTokens.primaryDark,
          ),
        ),
        if (item['flightNumber'] != null) ...[
          const SizedBox(height: 4),
          Text(
            'Flight ${item['flightNumber']}',
            style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _wideLayout(String status, String assignmentLabel, String amountLabel, bool unassigned) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_headerRow(status, unassigned), _metaColumn(assignmentLabel, amountLabel, unassigned)])),
        const Icon(Icons.chevron_right, color: AppTokens.textMuted),
      ],
    );
  }

  Widget _narrowLayout(String status, String assignmentLabel, String amountLabel, bool unassigned) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerRow(status, unassigned),
        _metaColumn(assignmentLabel, amountLabel, unassigned),
      ],
    );
  }
}
