import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/pwa_install_banner.dart';
import '../../booking/pages/guest_booking_lookup_page.dart';
import '../../booking/pages/booking_wizard_page.dart';
import '../../driver/pages/driver_login_page.dart';
import '../../../screens/admin/admin_screen.dart';
import '../widgets/landing_booking_lookup_card.dart';
import '../widgets/landing_bottom_cta.dart';
import '../widgets/landing_footer.dart';
import '../widgets/landing_header.dart';
import '../widgets/landing_hero.dart';
import '../widgets/landing_reassurance_card.dart';
import '../widgets/landing_service_cards.dart';
import '../widgets/landing_steps_section.dart';
import '../widgets/landing_trust_section.dart';

class CustomerLandingPage extends StatelessWidget {
  const CustomerLandingPage({super.key});

  void _openBookingWizard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookingWizardPage()),
    );
  }

  void _openBookingLookup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GuestBookingLookupPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width >= 900 ? 1100.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppTokens.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LandingHeader(onLookup: () => _openBookingLookup(context)),
                LandingHero(onBook: () => _openBookingWizard(context)),
                LandingServiceCards(onBook: () => _openBookingWizard(context)),
                const LandingTrustSection(),
                const LandingStepsSection(),
                const LandingReassuranceCard(),
                LandingBookingLookupCard(onLookup: () => _openBookingLookup(context)),
                const PwaInstallBanner(),
                LandingBottomCta(onBook: () => _openBookingWizard(context)),
                LandingFooter(
                  onAdmin: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminScreen(initialTab: 1),
                    ),
                  ),
                  onDriver: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverLoginPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
