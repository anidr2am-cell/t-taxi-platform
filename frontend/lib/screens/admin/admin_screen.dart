import 'package:flutter/material.dart';

import '../../features/admin/widgets/admin_auth_gate.dart';
import '../../features/admin_dashboard/pages/admin_dashboard_page.dart';
import '../../features/admin_dispatch/pages/admin_dispatch_queue_page.dart';
import '../../features/admin_dispatch/services/admin_dispatch_api_service.dart';
import '../../features/admin_settlement/pages/admin_settlement_queue_page.dart';
import '../../features/admin_review/pages/admin_review_queue_page.dart';
import '../../features/admin_notification/pages/admin_notification_queue_page.dart';
import '../../features/admin_chat/pages/admin_chat_queue_page.dart';
import '../../features/admin_support/pages/admin_support_inquiry_page.dart';
import '../../features/admin_flight/pages/admin_flight_monitor_page.dart';
import '../../features/admin_driver_application/pages/admin_driver_application_list_page.dart';
import '../../features/driver_location/pages/admin_driver_monitor_page.dart';
import '../../features/admin_pricing/pages/admin_pricing_manager_page.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/language_selector.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.initialTab = 0});

  /// MVP demo: open Reservations/Dispatch tab directly (`1`).
  final int initialTab;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late int _selectedIndex;
  int _sessionEpoch = 0;
  final _drawerKey = GlobalKey<ScaffoldState>();

  static const _authGatedIndices = {0, 2, 3, 4, 5, 8, 9, 10, 11, 12};

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, 12);
  }

  Future<void> _logout() async {
    await const AdminDispatchApiService().logout();
    if (!mounted) return;
    setState(() => _sessionEpoch++);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.t('admin_logout'))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final compactNav = width < 960;

    final menuItems = [
      l10n.t('admin_dashboard'),
      l10n.t('admin_reservations'),
      l10n.t('admin_chats'),
      l10n.t('admin_drivers'),
      l10n.t('admin_driver_application_menu'),
      l10n.t('admin_pricing'),
      l10n.t('admin_golf'),
      l10n.t('admin_airports'),
      l10n.t('admin_settlements'),
      l10n.t('admin_reviews'),
      l10n.t('admin_notifications'),
      l10n.t('admin_flights'),
      l10n.t('admin_support_menu'),
    ];

    final icons = [
      Icons.dashboard_outlined,
      Icons.list_alt_outlined,
      Icons.chat_bubble_outline,
      Icons.local_taxi_outlined,
      Icons.person_add_alt_1_outlined,
      Icons.price_change_outlined,
      Icons.golf_course_outlined,
      Icons.flight_outlined,
      Icons.receipt_long_outlined,
      Icons.rate_review_outlined,
      Icons.notifications_outlined,
      Icons.flight_land_outlined,
      Icons.support_agent_outlined,
    ];

    final selectedIcons = [
      Icons.dashboard,
      Icons.list_alt,
      Icons.chat_bubble,
      Icons.local_taxi,
      Icons.person_add_alt_1,
      Icons.price_change,
      Icons.golf_course,
      Icons.flight,
      Icons.receipt_long,
      Icons.rate_review,
      Icons.notifications,
      Icons.flight_land,
      Icons.support_agent,
    ];

    void selectIndex(int index) {
      setState(() => _selectedIndex = index);
      if (compactNav) _drawerKey.currentState?.closeDrawer();
    }

    Widget buildRail({required bool extended}) {
      return NavigationRail(
        selectedIndex: _selectedIndex,
        extended: extended,
        minExtendedWidth: 200,
        onDestinationSelected: selectIndex,
        labelType: extended
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.all,
        backgroundColor: AppTokens.surface,
        selectedIconTheme: const IconThemeData(color: AppTokens.primary),
        selectedLabelTextStyle: const TextStyle(
          color: AppTokens.primaryDark,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: AppTokens.textSecondary,
          fontSize: 11,
        ),
        destinations: List.generate(menuItems.length, (index) {
          return NavigationRailDestination(
            icon: Icon(icons[index]),
            selectedIcon: Icon(selectedIcons[index], color: AppTokens.primary),
            label: Text(menuItems[index]),
          );
        }),
      );
    }

    Widget buildDrawerList() {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        children: List.generate(menuItems.length, (index) {
          final selected = index == _selectedIndex;
          return ListTile(
            leading: Icon(
              selected ? selectedIcons[index] : icons[index],
              color: selected ? AppTokens.primary : AppTokens.textSecondary,
            ),
            title: Text(
              menuItems[index],
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTokens.primaryDark : AppTokens.textPrimary,
              ),
            ),
            selected: selected,
            onTap: () => selectIndex(index),
          );
        }),
      );
    }

    return Scaffold(
      key: _drawerKey,
      appBar: AppBar(
        title: Text(menuItems[_selectedIndex.clamp(0, menuItems.length - 1)]),
        leading: compactNav
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _drawerKey.currentState?.openDrawer(),
              )
            : null,
        actions: [
          if (_authGatedIndices.contains(_selectedIndex))
            IconButton(
              tooltip: l10n.t('admin_logout'),
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          const LanguageSelector(),
        ],
      ),
      drawer: compactNav
          ? Drawer(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      child: Text(
                        l10n.t('admin_dashboard'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTokens.primaryDark,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: buildDrawerList()),
                  ],
                ),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!compactNav) ...[
            buildRail(extended: width >= 1200),
            const VerticalDivider(width: 1, color: AppTokens.border),
          ],
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_sessionEpoch),
              child: _buildContent(l10n),
            ),
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
            onOpenSettlements: () => setState(() => _selectedIndex = 8),
          ),
        );
      case 1:
        return const AdminDispatchQueuePage();
      case 2:
        return const AdminAuthGate(child: AdminChatQueuePage());
      case 3:
        return const AdminAuthGate(child: AdminDriverMonitorPage());
      case 4:
        return const AdminAuthGate(child: AdminDriverApplicationListPage());
      case 5:
        return const AdminAuthGate(child: AdminPricingManagerPage());
      case 6:
        return _buildLegacyNotice(l10n.t('admin_golf'));
      case 7:
        return _buildLegacyNotice(l10n.t('admin_airports'));
      case 8:
        return const AdminAuthGate(child: AdminSettlementQueuePage());
      case 9:
        return const AdminAuthGate(child: AdminReviewQueuePage());
      case 10:
        return const AdminAuthGate(child: AdminNotificationQueuePage());
      case 11:
        return const AdminAuthGate(child: AdminFlightMonitorPage());
      case 12:
        return const AdminAuthGate(child: AdminSupportInquiryPage());
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLegacyNotice(String title) {
    return Center(
      child: AppUi.centeredContent(
        child: Padding(
          padding: AppUi.pagePadding(context),
          child: AppUi.emptyState(
            title: title,
            message: context.l10n.t('admin_placeholder_deferred'),
            icon: Icons.construction_outlined,
          ),
        ),
      ),
    );
  }
}
