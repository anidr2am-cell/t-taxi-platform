import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/booking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import '../widgets/pwa_install_banner.dart';
import 'booking/booking_flow_screen.dart';
import 'admin/admin_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final services = [
      _ServiceCardData(
        type: ServiceType.airportPickup,
        icon: Icons.flight_land,
        color: Colors.blue,
      ),
      _ServiceCardData(
        type: ServiceType.airportDropoff,
        icon: Icons.flight_takeoff,
        color: Colors.orange,
      ),
      _ServiceCardData(
        type: ServiceType.cityTransfer,
        icon: Icons.location_city,
        color: Colors.green,
      ),
      _ServiceCardData(
        type: ServiceType.golfTransfer,
        icon: Icons.golf_course,
        color: Colors.teal,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('app_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            ),
          ),
          const LanguageSelector(),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.local_taxi, size: 48, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('app_subtitle'),
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const PwaInstallBanner(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.t('select_service'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...services.map((s) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _ServiceCard(
                data: s,
                label: l10n.t(s.type.labelKey),
                onTap: () {
                  context.read<BookingState>().reset();
                  context.read<BookingState>().setServiceType(s.type);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BookingFlowScreen()),
                  );
                },
              ),
            )),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ServiceCardData {
  final ServiceType type;
  final IconData icon;
  final Color color;

  _ServiceCardData({required this.type, required this.icon, required this.color});
}

class _ServiceCard extends StatelessWidget {
  final _ServiceCardData data;
  final String label;
  final VoidCallback onTap;

  const _ServiceCard({required this.data, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, color: data.color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
