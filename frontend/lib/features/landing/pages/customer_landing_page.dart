import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/pwa_install_banner.dart';
import '../../booking/models/booking_wizard_route_args.dart';
import '../../booking/models/booking_wizard_steps.dart';
import '../../booking/models/location_option.dart';
import '../../booking/models/service_type_option.dart';
import '../../booking/pages/guest_booking_lookup_page.dart';
import '../models/landing_booking_draft.dart';
import '../widgets/landing_booking_lookup_card.dart';
import '../widgets/landing_booking_widget.dart';
import '../widgets/landing_bottom_cta.dart';
import '../widgets/landing_footer.dart';
import '../widgets/landing_social_login_section.dart';
import '../widgets/landing_header.dart';
import '../widgets/landing_hero.dart';
import '../widgets/landing_reassurance_card.dart';
import '../widgets/landing_service_cards.dart';
import '../widgets/landing_steps_section.dart';
import '../widgets/landing_trust_section.dart';

class CustomerLandingPage extends StatefulWidget {
  const CustomerLandingPage({super.key, this.initialDraft});

  /// Seeds draft state for widget tests.
  @visibleForTesting
  final LandingBookingDraft? initialDraft;

  @override
  State<CustomerLandingPage> createState() => _CustomerLandingPageState();
}

class _CustomerLandingPageState extends State<CustomerLandingPage> {
  late LandingBookingDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft ?? const LandingBookingDraft();
  }

  void _updateService(BookingServiceType type) {
    setState(() {
      _draft = _draft.copyWith(
        serviceType: type,
        clearOrigin: true,
        clearDestination: true,
      );
    });
  }

  void _updateOrigin(LocationOption origin) {
    setState(() => _draft = _draft.copyWith(origin: origin));
  }

  void _updateDestination(LocationOption destination) {
    setState(() => _draft = _draft.copyWith(destination: destination));
  }

  void _openBookingWizard(BuildContext context) {
    if (_draft.isRouteComplete) {
      Navigator.pushNamed(
        context,
        '/booking',
        arguments: BookingWizardRouteArgs(
          serviceType: _draft.serviceType!,
          origin: _draft.origin!,
          destination: _draft.destination!,
          initialStep: BookingWizardSteps.schedule,
        ),
      );
      return;
    }

    Navigator.pushNamed(context, '/booking');
  }

  void _openBookingLookup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GuestBookingLookupPage(enableCustomerTools: true),
      ),
    );
  }

  void _openSupport(BuildContext context) {
    Navigator.pushNamed(context, '/support');
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width >= 900
        ? 1100.0
        : double.infinity;
    final languageCode = context.watch<LocaleState>().languageCode;

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
                LandingHero(
                  onBook: () => _openBookingWizard(context),
                  desktopBookingWidget: LandingBookingWidget(
                    draft: _draft,
                    languageCode: languageCode,
                    onServiceSelected: _updateService,
                    onOriginSelected: _updateOrigin,
                    onDestinationSelected: _updateDestination,
                    onSubmit: () => _openBookingWizard(context),
                  ),
                ),
                LandingServiceCards(
                  selectedService: _draft.serviceType,
                  onServiceSelected: _updateService,
                  onBook: () => _openBookingWizard(context),
                ),
                const LandingTrustSection(),
                const LandingStepsSection(),
                const LandingReassuranceCard(),
                LandingBookingLookupCard(
                  onLookup: () => _openBookingLookup(context),
                ),
                const PwaInstallBanner(),
                LandingBottomCta(onSupport: () => _openSupport(context)),
                const LandingSocialLoginSection(),
                LandingFooter(
                  onAdmin: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/admin',
                    (_) => false,
                  ),
                  onDriver: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/driver',
                    (_) => false,
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
