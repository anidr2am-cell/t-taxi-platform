import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../driver_auth.dart';
import '../services/driver_api_service.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  Future<Map<String, dynamic>>? _ratingFuture;

  @override
  void initState() {
    super.initState();
    _ratingFuture = _api.getRatingSummary();
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    driverRedirectToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_nav_profile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _ratingFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Card(
                  child: ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('…'),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    title: Text(l10n.t('driver_rating_error')),
                    subtitle: Text(snapshot.error.toString()),
                  ),
                );
              }
              final rating = snapshot.data ?? {};
              final avg = rating['averageRating'];
              final count = rating['reviewCount'] ?? 0;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber, size: 32),
                  title: Text(
                    avg == null
                        ? l10n.t('driver_no_ratings')
                        : '${avg} ${l10n.t('driver_rating_average')}',
                  ),
                  subtitle: Text('$count ${l10n.t('driver_rating_count')}'),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(l10n.t('driver_logout')),
            ),
          ),
        ],
      ),
    );
  }
}
