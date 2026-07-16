import 'dart:async';

import 'package:flutter/material.dart';

import '../../booking/utils/booking_status_display.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/api_date_format.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';
import '../utils/admin_operations_ux.dart';
import 'admin_booking_detail_page.dart';

String? _serviceTypeCodeFromItem(Map<String, dynamic> item) {
  final serviceType = item['serviceType'];
  if (serviceType is Map) {
    final code = serviceType['code'];
    if (code is String && code.isNotEmpty) return code;
  }
  final code = item['serviceTypeCode'];
  return code is String && code.isNotEmpty ? code : null;
}

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
  Timer? _searchDebounce;

  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingSummary = false;
  String? _error;
  List<dynamic> _items = [];
  Map<String, dynamic> _summary = {};
  int _page = 1;
  int _total = 0;
  final int _limit = 20;
  String _view = AdminBookingView.needsAction;
  String? _statusFilter;
  String? _assignmentFilter;
  String? _dateFrom;
  String? _dateTo;
  String? _serviceType;
  String? _origin;
  String? _destination;
  String? _settlementStatus;
  bool _lowRating = false;
  bool _unassignedOnly = false;
  bool _hasInquiry = false;
  bool _showArchived = false;
  bool _archiveSubmitting = false;
  final Set<String> _selectedForArchive = {};
  String? _loadMoreError;
  bool _needsLogin = false;
  String? _selectedBookingNumber;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _load(page: 1);
    });
  }

  int get _activeFilterCount {
    var count = 0;
    if (_statusFilter != null) count++;
    if (_assignmentFilter != null) count++;
    if (_dateFrom != null || _dateTo != null) count++;
    if (_serviceType != null && _serviceType!.isNotEmpty) count++;
    if (_origin != null && _origin!.isNotEmpty) count++;
    if (_destination != null && _destination!.isNotEmpty) count++;
    if (_settlementStatus != null) count++;
    if (_lowRating) count++;
    if (_unassignedOnly) count++;
    if (_hasInquiry) count++;
    return count;
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
    await Future.wait([_loadSummary(), _load(page: 1)]);
  }

  Future<void> _loadSummary() async {
    setState(() => _loadingSummary = true);
    try {
      final data = await _api.getBookingsSummary();
      if (!mounted) return;
      setState(() {
        _summary = data;
        _loadingSummary = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSummary = false);
    }
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
      await Future.wait([_loadSummary(), _load(page: 1)]);
    } catch (err) {
      setState(() {
        _loading = false;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_action_failed'),
          languageCode: context.l10n.languageCode,
        );
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
      final search = _searchController.text.trim();
      final data = await _api.listBookings(
        view: _view,
        search: search.isEmpty ? null : search,
        status: _statusFilter,
        assignmentState: _unassignedOnly ? 'UNASSIGNED' : _assignmentFilter,
        serviceDateFrom: _dateFrom,
        serviceDateTo: _dateTo,
        serviceType: _serviceType,
        origin: _origin,
        destination: _destination,
        settlementStatus: _settlementStatus,
        lowRating: _lowRating ? true : null,
        hasInquiry: _hasInquiry ? true : null,
        archived: _showArchived ? true : null,
        page: page,
        limit: _limit,
      );
      final items = data['items'] as List<dynamic>? ?? [];
      setState(() {
        _page = page;
        _total = data['total'] as int? ?? items.length;
        _items = append ? [..._items, ...items] : items;
        if (!append) _selectedForArchive.clear();
        _loading = false;
        _loadingMore = false;
        _loadMoreError = null;
        if (!append && items.isNotEmpty) {
          final first = items.first as Map;
          _selectedBookingNumber ??= first['bookingNumber'] as String?;
        }
        if (!append && items.isEmpty) {
          _selectedBookingNumber = null;
        }
      });
    } catch (err) {
      final token = await _api.getSavedToken();
      if (append) {
        if (!mounted) return;
        setState(() {
          _loadingMore = false;
          _loadMoreError = userFacingError(
            err,
            fallback: context.l10n.t('admin_dispatch_load_more_failed'),
            languageCode: context.l10n.languageCode,
          );
        });
        return;
      }
      setState(() {
        if (token == null || token.isEmpty) {
          _needsLogin = true;
          _error = null;
        } else {
          _error = userFacingError(
            err,
            fallback: context.l10n.t('ui_action_failed'),
            languageCode: context.l10n.languageCode,
          );
        }
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _switchView(String view, {bool? unassignedOnly}) {
    setState(() {
      _view = view;
      _showArchived = false;
      _selectedForArchive.clear();
      if (unassignedOnly != null) {
        _unassignedOnly = unassignedOnly;
      } else if (view != AdminBookingView.all) {
        _unassignedOnly = false;
      }
    });
    _load(page: 1);
  }

  void _toggleArchivedView(bool value) {
    setState(() {
      _showArchived = value;
      _selectedForArchive.clear();
      if (value) {
        _view = AdminBookingView.all;
        _unassignedOnly = false;
      }
    });
    _load(page: 1);
  }

  void _toggleArchiveSelection(String bookingNumber, bool selected) {
    setState(() {
      if (selected) {
        _selectedForArchive.add(bookingNumber);
      } else {
        _selectedForArchive.remove(bookingNumber);
      }
    });
  }

  bool _hasArchiveWarning(Map<String, dynamic> item) {
    final status = item['status'] as String? ?? '';
    final assignment = item['activeAssignment'];
    return assignment is Map ||
        {
          'DRIVER_ASSIGNED',
          'ON_ROUTE',
          'DRIVER_ARRIVED',
          'PICKED_UP',
          'SETTLEMENT_PENDING',
          'COMPLETED',
        }.contains(status);
  }

  Future<void> _archiveSelected() async {
    if (_selectedForArchive.isEmpty || _archiveSubmitting) return;
    final l10n = context.l10n;
    final selectedItems = _items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _selectedForArchive.contains(item['bookingNumber']))
        .toList();
    final hasWarning = selectedItems.any(_hasArchiveWarning);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('admin_ops_archive_confirm_title')),
        content: Text(
          hasWarning
              ? l10n.t('admin_ops_archive_warning')
              : l10n.t('admin_ops_archive_info'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('driver_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.t('admin_ops_archive_bulk').replaceAll(' ({count})', ''),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _archiveSubmitting = true);
    try {
      await _api.archiveBookings(_selectedForArchive.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('admin_ops_archive_success'))),
      );
      await Future.wait([_loadSummary(), _load(page: 1)]);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                err,
                fallback: l10n.t('admin_ops_archive_failed'),
                languageCode: l10n.languageCode,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _archiveSubmitting = false);
    }
  }

  Future<void> _restoreBooking(String bookingNumber) async {
    if (_archiveSubmitting) return;
    final l10n = context.l10n;
    setState(() => _archiveSubmitting = true);
    try {
      await _api.restoreBookings([bookingNumber]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('admin_ops_archive_restore_success'))),
      );
      await Future.wait([_loadSummary(), _load(page: 1)]);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                err,
                fallback: l10n.t('admin_ops_archive_restore_failed'),
                languageCode: l10n.languageCode,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _archiveSubmitting = false);
    }
  }

  Future<void> _openDetail(String bookingNumber) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _api,
          onChanged: () {
            _loadSummary();
            _load(page: 1);
          },
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    final l10n = context.l10n;
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(
        l10n: l10n,
        statusFilter: _statusFilter,
        assignmentFilter: _assignmentFilter,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        serviceType: _serviceType,
        origin: _origin,
        destination: _destination,
        settlementStatus: _settlementStatus,
        lowRating: _lowRating,
        unassignedOnly: _unassignedOnly,
        hasInquiry: _hasInquiry,
      ),
    );
    if (result == null) return;
    if (result.reset) {
      setState(() {
        _statusFilter = null;
        _assignmentFilter = null;
        _dateFrom = null;
        _dateTo = null;
        _serviceType = null;
        _origin = null;
        _destination = null;
        _settlementStatus = null;
        _lowRating = false;
        _unassignedOnly = false;
        _hasInquiry = false;
      });
    } else {
      setState(() {
        _statusFilter = result.statusFilter;
        _assignmentFilter = result.assignmentFilter;
        _dateFrom = result.dateFrom;
        _dateTo = result.dateTo;
        _serviceType = result.serviceType;
        _origin = result.origin;
        _destination = result.destination;
        _settlementStatus = result.settlementStatus;
        _lowRating = result.lowRating;
        _unassignedOnly = result.unassignedOnly;
        _hasInquiry = result.hasInquiry;
      });
    }
    await _load(page: 1);
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
          _buildToolbar(l10n),
          _buildArchiveActions(l10n),
          _buildSummaryCards(l10n),
          _buildTabs(l10n),
          Expanded(child: _buildWorkbench(l10n)),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Padding(
      padding: AppUi.pagePadding(context).copyWith(bottom: AppTokens.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_search'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _load(page: 1);
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _load(page: 1),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _activeFilterCount > 0,
            label: Text('$_activeFilterCount'),
            child: IconButton(
              tooltip: l10n.t('admin_ops_filters'),
              onPressed: _openFilters,
              icon: const Icon(Icons.tune),
            ),
          ),
          IconButton(
            tooltip: l10n.t('admin_dispatch_refresh'),
            onPressed: () {
              _loadSummary();
              _load(page: 1);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveActions(AppLocalizations l10n) {
    return Padding(
      padding: AppUi.pagePadding(
        context,
      ).copyWith(top: 0, bottom: AppTokens.spaceSm),
      child: Wrap(
        spacing: AppTokens.spaceSm,
        runSpacing: AppTokens.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            selected: _showArchived,
            avatar: const Icon(Icons.archive_outlined, size: 18),
            label: Text(
              l10n.t(
                _showArchived
                    ? 'admin_ops_archive_hide'
                    : 'admin_ops_archive_show',
              ),
            ),
            onSelected: _toggleArchivedView,
          ),
          if (!_showArchived)
            FilledButton.icon(
              onPressed: _selectedForArchive.isEmpty || _archiveSubmitting
                  ? null
                  : _archiveSelected,
              icon: _archiveSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.visibility_off_outlined),
              label: Text(
                l10n
                    .t('admin_ops_archive_bulk')
                    .replaceAll('{count}', '${_selectedForArchive.length}'),
              ),
            ),
          if (_showArchived)
            Text(
              l10n.t('admin_ops_archive_hidden_notice'),
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(AppLocalizations l10n) {
    const keys = [
      'needsAction',
      'unassigned',
      'today',
      'inProgress',
      'settlementPending',
      'issues',
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppUi.pagePadding(context).copyWith(top: 0, bottom: 8),
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = keys[index];
          final count = _summary[key] as int? ?? 0;
          final view = AdminOperationsUx.viewForSummaryCard(key);
          return _SummaryCard(
            label: AdminOperationsUx.summaryCardLabel(l10n, key),
            count: count,
            loading: _loadingSummary,
            selected:
                view == _view &&
                (key != 'unassigned' || _unassignedOnly) &&
                (key != 'issues' || _view == AdminBookingView.issues),
            onTap: () {
              if (view == null) return;
              if (key == 'unassigned') {
                _switchView(view, unassignedOnly: true);
              } else {
                _switchView(view);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildTabs(AppLocalizations l10n) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppUi.pagePadding(context).copyWith(top: 0, bottom: 8),
        itemCount: AdminBookingView.ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final view = AdminBookingView.ordered[index];
          final selected = _view == view && !_unassignedOnly;
          return ChoiceChip(
            label: Text(AdminOperationsUx.viewLabel(l10n, view)),
            selected: selected,
            onSelected: (_) => _switchView(view),
          );
        },
      ),
    );
  }

  Widget _buildWorkbench(AppLocalizations l10n) {
    if (_loading) return AppUi.loadingState();
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final masterDetail = constraints.maxWidth >= 1000;
        if (!masterDetail) {
          return _buildList(l10n, masterDetail: false);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: _buildList(l10n, masterDetail: true)),
            const VerticalDivider(width: 1),
            Expanded(flex: 4, child: _buildPreviewPanel(l10n)),
          ],
        );
      },
    );
  }

  Widget _buildList(AppLocalizations l10n, {required bool masterDetail}) {
    final showLoadMore = _items.length < _total;
    return RefreshIndicator(
      onRefresh: () async {
        await _loadSummary();
        await _load(page: 1);
      },
      child: ListView.builder(
        itemCount: _items.length + 1 + (showLoadMore ? 1 : 0),
        padding: AppUi.pagePadding(context).copyWith(top: 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildResultHeader(l10n);
          }

          final itemIndex = index - 1;
          if (itemIndex >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : _loadMoreError != null
                    ? AppUi.errorState(
                        message: _loadMoreError!,
                        onRetry: () => _load(page: _page + 1, append: true),
                        retryLabel: l10n.t('admin_dispatch_retry'),
                      )
                    : OutlinedButton(
                        onPressed: () => _load(page: _page + 1, append: true),
                        child: Text(l10n.t('admin_dispatch_load_more')),
                      ),
              ),
            );
          }

          final item = Map<String, dynamic>.from(_items[itemIndex] as Map);
          final bookingNumber = item['bookingNumber'] as String? ?? '';
          final selected = _selectedBookingNumber == bookingNumber;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BookingListCard(
              item: item,
              l10n: l10n,
              selected: selected,
              archiveSelected: _selectedForArchive.contains(bookingNumber),
              showArchived: _showArchived,
              onArchiveSelected: (value) =>
                  _toggleArchiveSelection(bookingNumber, value),
              onRestore: () => _restoreBooking(bookingNumber),
              onTap: () {
                if (masterDetail) {
                  setState(() => _selectedBookingNumber = bookingNumber);
                } else {
                  _openDetail(bookingNumber);
                }
              },
              onPrimaryAction: () => _openDetail(bookingNumber),
            ),
          );
        },
      ),
    );
  }

  bool get _hasAdditionalFilters {
    return _searchController.text.trim().isNotEmpty ||
        _statusFilter != null ||
        _dateFrom != null ||
        _dateTo != null ||
        _serviceType != null ||
        _origin != null ||
        _destination != null ||
        _settlementStatus != null ||
        _lowRating ||
        _hasInquiry ||
        _showArchived;
  }

  Widget _buildResultHeader(AppLocalizations l10n) {
    final totalText = l10n
        .t(
          _unassignedOnly
              ? 'admin_ops_unassigned_result_total'
              : 'admin_ops_result_total',
        )
        .replaceAll('{total}', '$_total');
    final showingText = l10n
        .t('admin_ops_result_showing')
        .replaceAll('{count}', '${_items.length}');
    final filteredText = _hasAdditionalFilters
        ? ' · ${l10n.t('admin_ops_result_filtered')}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Text(
        '$totalText · $showingText$filteredText',
        style: const TextStyle(
          color: AppTokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPreviewPanel(AppLocalizations l10n) {
    final selected = _items
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['bookingNumber'] == _selectedBookingNumber)
        .toList();
    if (selected.isEmpty) {
      return Center(child: Text(l10n.t('admin_ops_select_booking')));
    }
    final item = selected.first;
    final operations = item['operations'] is Map
        ? Map<String, dynamic>.from(item['operations'] as Map)
        : null;
    final status = item['status'] as String? ?? '';
    final cta =
        item['primaryCta'] as String? ?? operations?['primaryCta'] as String?;

    return Padding(
      padding: AppUi.pagePadding(context),
      child: AppUi.surfaceCard(
        child: SizedBox(
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item['bookingNumber'] as String? ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              AppUi.statusBadge(
                BookingStatusDisplay.label(
                  l10n,
                  status,
                  audience: BookingStatusAudience.admin,
                ),
                tone: AppUi.toneForBookingStatus(status),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                AdminOperationsUx.nextActionLabel(l10n, operations, item),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                AdminOperationsUx.routeContextLabel(
                  l10n,
                  _serviceTypeCodeFromItem(item),
                ),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item['origin']} → ${item['destination']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(item['scheduledPickupAt'] as String? ?? '-'),
              const Spacer(),
              AppUi.primaryButton(
                label: AdminOperationsUx.primaryCtaLabel(l10n, cta),
                icon: Icons.open_in_new,
                onPressed: () => _openDetail(item['bookingNumber'] as String),
              ),
            ],
          ),
        ),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.loading,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool loading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTokens.borderRadiusMd,
      child: Container(
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTokens.primaryLight : AppTokens.surface,
          borderRadius: AppTokens.borderRadiusMd,
          border: Border.all(
            color: selected ? AppTokens.primary : AppTokens.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTokens.textSecondary,
              ),
            ),
            loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.primaryDark,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _BookingListCard extends StatelessWidget {
  const _BookingListCard({
    required this.item,
    required this.l10n,
    required this.onTap,
    required this.onPrimaryAction,
    required this.archiveSelected,
    required this.showArchived,
    required this.onArchiveSelected,
    required this.onRestore,
    this.selected = false,
  });

  final Map<String, dynamic> item;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onPrimaryAction;
  final bool archiveSelected;
  final bool showArchived;
  final ValueChanged<bool> onArchiveSelected;
  final VoidCallback onRestore;
  final bool selected;

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
    final operations = item['operations'] is Map
        ? Map<String, dynamic>.from(item['operations'] as Map)
        : null;
    final severity = operations?['severity'] as String?;
    final reason = AdminOperationsUx.formatActionReason(l10n, operations);
    final cta =
        item['primaryCta'] as String? ?? operations?['primaryCta'] as String?;
    final archive = item['archive'] is Map
        ? Map<String, dynamic>.from(item['archive'] as Map)
        : const <String, dynamic>{};
    final isArchived = archive['isArchived'] == true;

    return AppUi.surfaceCard(
      onTap: onTap,
      backgroundColor: selected
          ? AppTokens.primaryLight
          : (isArchived
                ? AppTokens.surfaceMuted
                : (unassigned ? AppTokens.warningLight : AppTokens.surface)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!showArchived)
                Checkbox(
                  value: archiveSelected,
                  onChanged: (value) => onArchiveSelected(value ?? false),
                  visualDensity: VisualDensity.compact,
                ),
              Expanded(
                child: Text(
                  item['bookingNumber'] as String? ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppUi.statusBadge(
                BookingStatusDisplay.label(
                  l10n,
                  status,
                  audience: BookingStatusAudience.admin,
                ),
                tone: AppUi.toneForBookingStatus(status),
              ),
              if (isArchived) ...[
                const SizedBox(width: 6),
                AppUi.statusBadge(
                  l10n.t('admin_ops_archive_badge'),
                  tone: AppStatusTone.neutral,
                ),
              ],
            ],
          ),
          if (severity != null && severity.isNotEmpty) ...[
            const SizedBox(height: 6),
            AppUi.statusBadge(
              AdminOperationsUx.severityLabel(l10n, severity),
              tone: severity == 'URGENT'
                  ? AppStatusTone.error
                  : AppStatusTone.warning,
            ),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTokens.warning,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            AdminOperationsUx.routeContextLabel(
              l10n,
              _serviceTypeCodeFromItem(item),
            ),
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${item['origin']} → ${item['destination']}',
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${item['scheduledPickupAt'] ?? '-'} · ${item['customerDisplayName'] ?? '-'} · ${item['passengerCount'] ?? '-'} pax',
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.t('admin_dispatch_assigned_driver')}: $assignmentLabel',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: unassigned ? AppTokens.warning : AppTokens.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            amountLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: AppTokens.spaceXs,
              children: [
                if (isArchived)
                  OutlinedButton.icon(
                    onPressed: onRestore,
                    icon: const Icon(Icons.restore),
                    label: Text(l10n.t('admin_ops_archive_restore')),
                  ),
                TextButton(
                  onPressed: onPrimaryAction,
                  child: Text(AdminOperationsUx.primaryCtaLabel(l10n, cta)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterResult {
  const _FilterResult({
    this.statusFilter,
    this.assignmentFilter,
    this.dateFrom,
    this.dateTo,
    this.serviceType,
    this.origin,
    this.destination,
    this.settlementStatus,
    this.lowRating = false,
    this.unassignedOnly = false,
    this.hasInquiry = false,
    this.reset = false,
  });

  final String? statusFilter;
  final String? assignmentFilter;
  final String? dateFrom;
  final String? dateTo;
  final String? serviceType;
  final String? origin;
  final String? destination;
  final String? settlementStatus;
  final bool lowRating;
  final bool unassignedOnly;
  final bool hasInquiry;
  final bool reset;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.l10n,
    this.statusFilter,
    this.assignmentFilter,
    this.dateFrom,
    this.dateTo,
    this.serviceType,
    this.origin,
    this.destination,
    this.settlementStatus,
    this.lowRating = false,
    this.unassignedOnly = false,
    this.hasInquiry = false,
  });

  final AppLocalizations l10n;
  final String? statusFilter;
  final String? assignmentFilter;
  final String? dateFrom;
  final String? dateTo;
  final String? serviceType;
  final String? origin;
  final String? destination;
  final String? settlementStatus;
  final bool lowRating;
  final bool unassignedOnly;
  final bool hasInquiry;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _status = widget.statusFilter;
  late String? _assignment = widget.assignmentFilter;
  late final _dateFrom = TextEditingController(text: widget.dateFrom);
  late final _dateTo = TextEditingController(text: widget.dateTo);
  late final _serviceType = TextEditingController(text: widget.serviceType);
  late final _origin = TextEditingController(text: widget.origin);
  late final _destination = TextEditingController(text: widget.destination);
  late String? _settlement = widget.settlementStatus;
  late bool _lowRating = widget.lowRating;
  late bool _unassigned = widget.unassignedOnly;
  late bool _hasInquiry = widget.hasInquiry;
  String? _dateError;

  @override
  void dispose() {
    _dateFrom.dispose();
    _dateTo.dispose();
    _serviceType.dispose();
    _origin.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = parseApiDate(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      controller.text = formatApiDate(picked);
      _dateError = null;
    });
  }

  void _applyFilters() {
    final from = _dateFrom.text.trim().isEmpty ? null : _dateFrom.text.trim();
    final to = _dateTo.text.trim().isEmpty ? null : _dateTo.text.trim();
    if (from != null && parseApiDate(from) == null) {
      setState(() {
        _dateError = widget.l10n.t('admin_ops_filter_date_from_invalid');
      });
      return;
    }
    if (to != null && parseApiDate(to) == null) {
      setState(() {
        _dateError = widget.l10n.t('admin_ops_filter_date_to_invalid');
      });
      return;
    }
    if (from != null && to != null && from.compareTo(to) > 0) {
      setState(() {
        _dateError = widget.l10n.t('admin_ops_filter_date_range_invalid');
      });
      return;
    }
    Navigator.pop(
      context,
      _FilterResult(
        statusFilter: _status,
        assignmentFilter: _assignment,
        dateFrom: from,
        dateTo: to,
        serviceType: _serviceType.text.trim().isEmpty
            ? null
            : _serviceType.text.trim(),
        origin: _origin.text.trim().isEmpty ? null : _origin.text.trim(),
        destination: _destination.text.trim().isEmpty
            ? null
            : _destination.text.trim(),
        settlementStatus: _settlement,
        lowRating: _lowRating,
        unassignedOnly: _unassigned,
        hasInquiry: _hasInquiry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.t('admin_ops_filters'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dateFrom,
              readOnly: true,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_filter_date_from'),
                helperText: 'YYYY-MM-DD',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () => _pickDate(_dateFrom),
                ),
              ),
              onTap: () => _pickDate(_dateFrom),
            ),
            TextField(
              controller: _dateTo,
              readOnly: true,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_filter_date_to'),
                helperText: 'YYYY-MM-DD',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () => _pickDate(_dateTo),
                ),
              ),
              onTap: () => _pickDate(_dateTo),
            ),
            if (_dateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  _dateError!,
                  style: const TextStyle(color: AppTokens.error),
                ),
              ),
            DropdownButtonFormField<String?>(
              initialValue: _status,
              decoration: InputDecoration(labelText: l10n.t('status')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.t('admin_dispatch_all_statuses')),
                ),
                DropdownMenuItem(
                  value: 'PENDING',
                  child: Text(l10n.t('status_pending')),
                ),
                const DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                DropdownMenuItem(
                  value: 'CONFIRMED',
                  child: Text(l10n.t('status_confirmed')),
                ),
                DropdownMenuItem(
                  value: 'DRIVER_ASSIGNED',
                  child: Text(l10n.t('status_driver_assigned')),
                ),
                DropdownMenuItem(
                  value: 'ON_ROUTE',
                  child: Text(l10n.t('status_on_route')),
                ),
                DropdownMenuItem(
                  value: 'DRIVER_ARRIVED',
                  child: Text(l10n.t('status_driver_arrived')),
                ),
                DropdownMenuItem(
                  value: 'PICKED_UP',
                  child: Text(l10n.t('status_picked_up')),
                ),
                DropdownMenuItem(
                  value: 'SETTLEMENT_PENDING',
                  child: Text(l10n.t('status_settlement_pending')),
                ),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _assignment,
              decoration: InputDecoration(
                labelText: l10n.t('admin_dispatch_assignment'),
              ),
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
              onChanged: (v) => setState(() => _assignment = v),
            ),
            TextField(
              controller: _serviceType,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_filter_service_type'),
              ),
            ),
            TextField(
              controller: _origin,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_filter_origin'),
              ),
            ),
            TextField(
              controller: _destination,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_filter_destination'),
              ),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _settlement,
              decoration: InputDecoration(
                labelText: l10n.t('admin_ops_filter_settlement'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.t('admin_dispatch_all_statuses')),
                ),
                DropdownMenuItem(
                  value: 'RECEIPT_REJECTED',
                  child: Text(l10n.t('admin_ops_settlement_rejected')),
                ),
                DropdownMenuItem(
                  value: 'RECEIPT_SUBMITTED',
                  child: Text(l10n.t('admin_ops_settlement_submitted')),
                ),
                DropdownMenuItem(
                  value: 'RECEIPT_MISSING',
                  child: Text(l10n.t('admin_ops_settlement_missing')),
                ),
              ],
              onChanged: (v) => setState(() => _settlement = v),
            ),
            SwitchListTile(
              title: Text(l10n.t('admin_ops_filter_low_rating')),
              value: _lowRating,
              onChanged: (v) => setState(() => _lowRating = v),
            ),
            SwitchListTile(
              title: Text(l10n.t('admin_dispatch_unassigned')),
              value: _unassigned,
              onChanged: (v) => setState(() => _unassigned = v),
            ),
            SwitchListTile(
              title: Text(l10n.t('admin_ops_filter_has_inquiry')),
              value: _hasInquiry,
              onChanged: (v) => setState(() => _hasInquiry = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _FilterResult(reset: true),
                    ),
                    child: Text(l10n.t('admin_ops_filter_reset')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _applyFilters,
                    child: Text(l10n.t('admin_ops_filter_apply')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
