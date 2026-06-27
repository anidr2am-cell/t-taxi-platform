import 'package:flutter/material.dart';
import '../../features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/language_selector.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;
  bool _loading = true;

  Map<String, dynamic>? _dashboard;
  List<dynamic> _reservations = [];
  List<dynamic> _chats = [];
  List<dynamic> _drivers = [];
  List<dynamic> _vehiclePrices = [];
  List<dynamic> _golfCourses = [];
  List<dynamic> _airports = [];

  String? _selectedChatRoom;
  String? _selectedChatCustomer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _dashboard = await ApiService().getDashboard();
      _reservations = await ApiService().getAdminReservations();
      _chats = await ApiService().getAdminChats();
      _drivers = await ApiService().getDrivers();
      _vehiclePrices = await ApiService().getAdminVehiclePrices();
      _golfCourses = await ApiService().getAdminGolfCourses();
      _airports = await ApiService().getAdminAirports();
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final menuItems = [
      l10n.t('admin_dashboard'),
      l10n.t('admin_reservations'),
      l10n.t('admin_chats'),
      l10n.t('admin_drivers'),
      l10n.t('admin_pricing'),
      l10n.t('admin_golf'),
      l10n.t('admin_airports'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('admin_dashboard')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          const LanguageSelector(),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: menuItems
                .map((label) => NavigationRailDestination(
                      icon: const Icon(Icons.circle_outlined),
                      selectedIcon: const Icon(Icons.circle),
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboard(l10n);
      case 1:
        return const AdminDispatchQueuePage();
      case 2:
        return _buildChats(l10n);
      case 3:
        return _buildDrivers(l10n);
      case 4:
        return _buildPricing(l10n);
      case 5:
        return _buildGolfCourses(l10n);
      case 6:
        return _buildAirports(l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDashboard(AppLocalizations l10n) {
    final d = _dashboard ?? {};
    final statusStats = d['statusStats'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statCard(l10n.t('today_bookings'), '${d['todayReservations'] ?? 0}', Icons.calendar_today),
              _statCard(l10n.t('today_revenue'), '${d['todayRevenue'] ?? 0} THB', Icons.attach_money),
              _statCard(l10n.t('pending_count'), '${d['pendingReservations'] ?? 0}', Icons.pending),
              _statCard(l10n.t('awaiting_driver'), '${d['awaitingDriver'] ?? 0}', Icons.person_search),
              _statCard(l10n.t('active_chats'), '${d['activeChats'] ?? 0}', Icons.chat),
            ],
          ),
          const SizedBox(height: 24),
          Text('Status Statistics', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...statusStats.map((s) => ListTile(
                title: Text(s['status'] as String? ?? ''),
                trailing: Text('${s['count']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Card(
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 32),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildReservations(AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _reservations.length,
      itemBuilder: (context, index) {
        final r = _reservations[index];
        return Card(
          child: ListTile(
            title: Text(r['reservation_number'] as String? ?? ''),
            subtitle: Text('${r['service_type']} | ${r['status']} | ${r['customer_name'] ?? ''}'),
            trailing: Text('${r['total_price']} THB'),
            onTap: () => _showReservationActions(r),
          ),
        );
      },
    );
  }

  void _showReservationActions(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(r['reservation_number'] as String? ?? '')),
          ListTile(
            leading: const Icon(Icons.check),
            title: const Text('Confirm'),
            onTap: () async {
              await ApiService().updateReservationStatus(r['id'] as int, 'confirmed');
              Navigator.pop(ctx);
              _loadData();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Assign Driver'),
            onTap: () async {
              if (_drivers.isNotEmpty) {
                await ApiService().updateReservationStatus(
                  r['id'] as int,
                  'driver_assigned',
                  driverId: _drivers.first['id'] as int,
                );
              }
              Navigator.pop(ctx);
              _loadData();
            },
          ),
          ListTile(
            leading: const Icon(Icons.done_all),
            title: const Text('Complete'),
            onTap: () async {
              await ApiService().updateReservationStatus(r['id'] as int, 'completed');
              Navigator.pop(ctx);
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChats(AppLocalizations l10n) {
    if (_selectedChatRoom != null) {
      return Column(
        children: [
          ListTile(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedChatRoom = null),
            ),
            title: Text(_selectedChatCustomer ?? ''),
          ),
          Expanded(
            child: ChatPanel(
              roomId: _selectedChatRoom!,
              senderRole: 'admin',
              senderName: 'Admin',
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _chats.length,
      itemBuilder: (context, index) {
        final c = _chats[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.chat)),
            title: Text(c['reservation_number'] as String? ?? ''),
            subtitle: Text(c['last_message'] as String? ?? ''),
            trailing: Text('${c['message_count'] ?? 0}'),
            onTap: () => setState(() {
              _selectedChatRoom = c['room_id'] as String?;
              _selectedChatCustomer = c['customer_name'] as String?;
            }),
          ),
        );
      },
    );
  }

  Widget _buildDrivers(AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _drivers.length,
      itemBuilder: (context, index) {
        final d = _drivers[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(d['name'] as String? ?? ''),
            subtitle: Text('${d['phone']} | ${d['vehicle_type']}'),
            trailing: Icon(
              d['is_available'] == true ? Icons.check_circle : Icons.cancel,
              color: d['is_available'] == true ? Colors.green : Colors.grey,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPricing(AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _vehiclePrices.length,
      itemBuilder: (context, index) {
        final p = _vehiclePrices[index];
        return Card(
          child: ListTile(
            title: Text('${p['vehicle_type']} - ${p['service_type']}'),
            trailing: Text('${p['base_price']} THB'),
          ),
        );
      },
    );
  }

  Widget _buildGolfCourses(AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _golfCourses.length,
      itemBuilder: (context, index) {
        final g = _golfCourses[index];
        return Card(
          child: ListTile(
            title: Text(g['name'] as String? ?? ''),
            subtitle: Text(g['region'] as String? ?? ''),
          ),
        );
      },
    );
  }

  Widget _buildAirports(AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _airports.length,
      itemBuilder: (context, index) {
        final a = _airports[index];
        return Card(
          child: ListTile(
            title: Text('${a['code']} - ${a['name']}'),
            subtitle: Text(a['city'] as String? ?? ''),
          ),
        );
      },
    );
  }
}
