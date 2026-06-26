import 'package:flutter/material.dart';
import '../features/landing/pages/customer_landing_page.dart';

/// Customer entry screen — landing page before booking wizard.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomerLandingPage();
  }
}
