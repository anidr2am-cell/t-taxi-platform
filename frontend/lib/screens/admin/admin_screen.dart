import 'package:flutter/material.dart';
import '../../features/admin/widgets/admin_auth_gate.dart';
import '../../features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import '../../features/admin_settlement/pages/admin_settlement_queue_page.dart';
import '../../features/admin_review/pages/admin_review_queue_page.dart';
import '../../features/admin_notification/pages/admin_notification_queue_page.dart';
import '../../features/admin_chat/pages/admin_chat_queue_page.dart';
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
    // Legacy /api/* dashboard endpoints are deprecated; operational data uses v1 module tabs.
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
      l10n.t('admin_settlements'),
      'Reviews',
      'Notifications',
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
        return const AdminAuthGate(child: AdminChatQueuePage());
      case 3:
        return _buildLegacyNotice('Drivers', 'Driver management uses operational dispatch and driver APIs.');
      case 4:
        return _buildLegacyNotice('Pricing', 'Use admin pricing APIs (/api/v1/admin/pricing) for production configuration.');
      case 5:
        return _buildLegacyNotice('Golf courses', 'Catalog management is deferred in MVP release.');
      case 6:
        return _buildLegacyNotice('Airports', 'Catalog management is deferred in MVP release.');
      case 7:
        return const AdminAuthGate(child: AdminSettlementQueuePage());
      case 8:
        return const AdminAuthGate(child: AdminReviewQueuePage());
      case 9:
        return const AdminAuthGate(child: AdminNotificationQueuePage());
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDashboard(AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operational MVP dashboard',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Use Reservations (dispatch), Settlements, Reviews, Notifications, and Chats tabs for live /api/v1 data. '
            'Legacy dashboard metrics are not wired in this release build.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statCard('Dispatch', 'Live', Icons.local_taxi),
              _statCard('Settlements', 'Live', Icons.receipt_long),
              _statCard('Reviews', 'Live', Icons.star),
              _statCard('Chat', 'Live', Icons.chat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyNotice(String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
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
