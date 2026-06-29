import 'package:flutter/material.dart';
import '../../features/admin/widgets/admin_auth_gate.dart';
import '../../features/admin_dashboard/pages/admin_dashboard_page.dart';
import '../../features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import '../../features/admin_settlement/pages/admin_settlement_queue_page.dart';
import '../../features/admin_review/pages/admin_review_queue_page.dart';
import '../../features/admin_notification/pages/admin_notification_queue_page.dart';
import '../../features/admin_chat/pages/admin_chat_queue_page.dart';
import '../../features/admin_flight/pages/admin_flight_monitor_page.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/language_selector.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;

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
      'Flights',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('admin_dashboard')),
        actions: [
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
            child: _buildContent(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    switch (_selectedIndex) {
      case 0:
        return AdminAuthGate(
          child: AdminDashboardPage(
            onOpenDispatch: () => setState(() => _selectedIndex = 1),
            onOpenSettlements: () => setState(() => _selectedIndex = 7),
          ),
        );
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
      case 10:
        return const AdminAuthGate(child: AdminFlightMonitorPage());
      default:
        return const SizedBox.shrink();
    }
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
}
