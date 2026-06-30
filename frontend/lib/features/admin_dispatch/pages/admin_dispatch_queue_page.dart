import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
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
        _error = err.toString();
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
          _error = err.toString();
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
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_dispatch_search'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _load(page: 1),
                    ),
                  ),
                  onSubmitted: (_) => _load(page: 1),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DropdownButton<String?>(
                      value: _statusFilter,
                      hint: Text(l10n.t('status')),
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
                    DropdownButton<String?>(
                      value: _assignmentFilter,
                      hint: Text(l10n.t('admin_dispatch_assignment')),
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
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _load(page: 1),
              child: Text(l10n.t('admin_dispatch_retry')),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(l10n.t('admin_dispatch_empty')));
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: ListView.builder(
        itemCount: _items.length + (_items.length < _total ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
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
          final assignment = item['activeAssignment'] is Map
              ? Map<String, dynamic>.from(item['activeAssignment'] as Map)
              : null;
          final driverName = assignment?['driverDisplayName'] as String?;
          final assignmentLabel = driverName == null || driverName.isEmpty
              ? l10n.t('admin_dispatch_unassigned')
              : driverName;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              onTap: () => _openDetail(item['bookingNumber'] as String),
              title: Text(item['bookingNumber'] as String? ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['origin']} → ${item['destination']}'),
                  Text(
                    '${item['customerDisplayName']} · ${item['scheduledPickupAt'] ?? '-'}',
                  ),
                  Text(
                    '${l10n.t('admin_dispatch_assigned_driver')}: $assignmentLabel',
                  ),
                  if (item['flightNumber'] != null)
                    Text(item['flightNumber'] as String),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _badge(item['status'] as String? ?? '', AppTheme.primary),
                  const SizedBox(height: 4),
                  _badge(
                    assignment == null ? 'UNASSIGNED' : 'ASSIGNED',
                    assignment == null ? Colors.orange : AppTheme.success,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLogin(AppLocalizations l10n) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.t('admin_dispatch_login_title'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: l10n.t('email'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('password'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: _login,
                  child: Text(l10n.t('admin_dispatch_login')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
