import 'package:flutter/material.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../../auth/presentation/language_selector.dart';
import '../../dispatch/data/dispatch_models.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../data/account_api.dart';
import '../data/account_models.dart';
import 'profile_edit_page.dart';
import 'vehicle_list_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.accountApi,
    required this.dispatchRepository,
    required this.localeController,
    required this.onUnauthorized,
    required this.onLogout,
  });

  final AccountDataSource accountApi;
  final DispatchReader dispatchRepository;
  final LocaleController localeController;
  final Future<void> Function() onUnauthorized;
  final Future<void> Function() onLogout;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  DriverProfile? _profile;
  RatingSummary? _rating;
  DriverDispatchStatus? _status;
  Object? _error;
  bool _loading = true;
  bool _changingOnline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        widget.accountApi.getProfile(),
        widget.accountApi.getRatingSummary(),
        widget.dispatchRepository.getStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = values[0] as DriverProfile;
        _rating = values[1] as RatingSummary;
        _status = values[2] as DriverDispatchStatus;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _setOnline(bool value) async {
    if (_changingOnline) return;
    setState(() => _changingOnline = true);
    try {
      final status = value
          ? await widget.dispatchRepository.goOnline()
          : await widget.dispatchRepository.goOffline();
      if (!mounted) return;
      setState(() {
        _status = status;
        _changingOnline = false;
      });
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() => _changingOnline = false);
      _message(error.localizedMessage(AppLocalizations.of(context)));
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: FilledButton(
                key: const Key('accountRetry'),
                onPressed: _load,
                child: Text(l10n.retry),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _profile!.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber),
                              const SizedBox(width: 6),
                              Text(
                                _rating!.averageRating == null
                                    ? l10n.noReviewsYet
                                    : l10n.ratingSummary(
                                        '${_rating!.averageRating}',
                                        _rating!.reviewCount,
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: SwitchListTile(
                      key: const Key('accountOnlineToggle'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      title: Text(
                        _status!.online ? l10n.online : l10n.offline,
                      ),
                      subtitle: Text(l10n.newCallReceivingStatus),
                      value: _status!.online,
                      onChanged: _changingOnline ? null : _setOnline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryVehicleCard(vehicle: _profile!.vehicle),
                  const SizedBox(height: 16),
                  ListTile(
                    key: const Key('openProfileEdit'),
                    leading: const Icon(Icons.person_outline),
                    title: Text(l10n.editProfile),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ProfileEditPage(
                            api: widget.accountApi,
                            initialProfile: _profile!,
                          ),
                        ),
                      );
                      if (changed == true) await _load();
                    },
                  ),
                  ListTile(
                    key: const Key('openVehicleList'),
                    leading: const Icon(Icons.directions_car_outlined),
                    title: Text(l10n.manageVehicles),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VehicleListPage(
                          api: widget.accountApi,
                          onUnauthorized: widget.onUnauthorized,
                        ),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.localeController,
                    builder: (context, _) {
                      final currentLanguage =
                          widget.localeController.locale.languageCode == 'ko'
                          ? l10n.languageKorean
                          : l10n.languageThai;
                      return ListTile(
                        key: const Key('openLanguageSettings'),
                        leading: const Icon(Icons.language),
                        title: Text(l10n.languageSettings),
                        subtitle: Text(currentLanguage),
                        trailing: LanguageSelector(
                          controller: widget.localeController,
                          compact: false,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const Key('logoutButton'),
                    leading: const Icon(Icons.logout),
                    title: Text(l10n.logout),
                    onTap: widget.onLogout,
                  ),
                ],
              ),
            ),
    );
  }
}

class _PrimaryVehicleCard extends StatelessWidget {
  const _PrimaryVehicleCard({required this.vehicle});

  final DriverProfileVehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = vehicle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.primaryVehicle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              value == null
                  ? l10n.noPrimaryVehicleRegistered
                  : [
                          value.typeName ?? value.typeCode,
                          value.plateNumber,
                          value.modelName,
                          value.color,
                        ]
                        .whereType<String>()
                        .where((item) => item.isNotEmpty)
                        .join(' · '),
            ),
          ],
        ),
      ),
    );
  }
}
