import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/language_selector.dart';
import '../../../widgets/pwa_install_banner.dart';
import '../../booking/pages/booking_wizard_page.dart';
import '../../driver/pages/driver_login_page.dart';
import '../widgets/landing_hero.dart';
import '../widgets/landing_service_cards.dart';
import '../widgets/landing_trust_section.dart';
import '../../../screens/admin/admin_screen.dart';

class CustomerLandingPage extends StatelessWidget {
  const CustomerLandingPage({super.key});

  void _openBookingWizard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookingWizardPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxWidth = MediaQuery.sizeOf(context).width >= 900 ? 1100.0 : double.infinity;

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
          IconButton(
            icon: const Icon(Icons.local_taxi),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverLoginPage()),
            ),
          ),
          const LanguageSelector(),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LandingHero(onBook: () => _openBookingWizard(context)),
                const PwaInstallBanner(),
                LandingServiceCards(
                  onBook: () => _openBookingWizard(context),
                ),
                const LandingTrustSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
