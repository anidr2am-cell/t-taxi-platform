import 'package:flutter/material.dart';
import '../../features/admin/widgets/admin_auth_gate.dart';
import '../../features/admin_dashboard/pages/admin_dashboard_page.dart';
import '../../features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import '../../features/admin_settlement/pages/admin_settlement_queue_page.dart';
import '../../features/admin_review/pages/admin_review_queue_page.dart';
import '../../features/admin_notification/pages/admin_notification_queue_page.dart';
import '../../features/admin_chat/pages/admin_chat_queue_page.dart';
import '../../features/admin_flight/pages/admin_flight_monitor_page.dart';
import '../../features/driver_location/pages/admin_driver_monitor_page.dart';
import '../../features/admin_pricing/pages/admin_pricing_manager_page.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_ui.dart';
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

    final icons = [
      Icons.dashboard_outlined,
      Icons.list_alt_outlined,
      Icons.chat_bubble_outline,
      Icons.local_taxi_outlined,
      Icons.price_change_outlined,
      Icons.golf_course_outlined,
      Icons.flight_outlined,
      Icons.receipt_long_outlined,
      Icons.rate_review_outlined,
      Icons.notifications_outlined,
      Icons.flight_land_outlined,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(menuItems[_selectedIndex.clamp(0, menuItems.length - 1)]),
        actions: const [LanguageSelector()],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: AppTokens.surface,
            destinations: List.generate(menuItems.length, (index) {
              return NavigationRailDestination(
                icon: Icon(icons[index]),
                selectedIcon: Icon(icons[index], color: AppTokens.primary),
                label: Text(menuItems[index], style: const TextStyle(fontSize: 11)),
              );
            }),
          ),
          const VerticalDivider(width: 1, color: AppTokens.border),
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
        return const AdminAuthGate(child: AdminDriverMonitorPage());
      case 4:
        return const AdminAuthGate(child: AdminPricingManagerPage());
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
        child: AppUi.emptyState(
          title: title,
          message: message,
          icon: Icons.construction_outlined,
        ),
      ),
    );
  }
}
