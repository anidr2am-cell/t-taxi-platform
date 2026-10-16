import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../services/admin_pricing_api_service.dart';

class AdminGolfPricesPanel extends StatefulWidget {
  const AdminGolfPricesPanel({
    super.key,
    this.api = const AdminPricingApiService(),
  });
  final AdminPricingApiService api;
  @override
  State<AdminGolfPricesPanel> createState() => _AdminGolfPricesPanelState();
}

class _AdminGolfPricesPanelState extends State<AdminGolfPricesPanel> {
  AdminGolfPricingApiService get _api =>
      widget.api is AdminGolfPricingApiService
      ? widget.api as AdminGolfPricingApiService
      : const AdminGolfPricingApiService();
  List<dynamic> _prices = [], _courses = [];
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Future.wait([
        _api.listGolfPrices(),
        _api.listGolfCourses(),
      ]);
      if (mounted)
        setState(() {
          _prices = data[0];
          _courses = data[1];
          _loading = false;
          _error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = userFacingError(
            e,
            fallback: context.l10n.t('ui_load_failed'),
          );
        });
    }
  }

  Future<void> _edit(Map row) async {
    final c = TextEditingController(text: '${row['roundTripPrice']}');
    final value = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('golf_round_trip_price')),
        content: TextField(controller: c, keyboardType: TextInputType.number),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(context.l10n.t('ui_cancel')),
          ),
          FilledButton(
            onPressed: () {
              final p = num.tryParse(c.text);
              if (p != null && p > 0 && p == p.round())
                Navigator.pop(dialog, p.toInt());
            },
            child: Text(context.l10n.t('ui_save')),
          ),
        ],
      ),
    );
    c.dispose();
    if (value == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _api.updateGolfPrice(row['id'] as int, value);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('golf_price_saved'))),
        );
    } catch (e) {
      if (mounted)
        setState(
          () => _error = userFacingError(
            e,
            fallback: context.l10n.t('ui_action_failed'),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n.t;
    final language = Localizations.localeOf(context).languageCode;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('admin_golf_prices'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(t('golf_package_included')),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppTokens.error)),
          if (_saving) const LinearProgressIndicator(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(t('golf_region'))),
                DataColumn(label: Text(t('vehicle'))),
                DataColumn(label: Text(t('golf_holes'))),
                DataColumn(label: Text(t('golf_round_trip_price'))),
                DataColumn(label: Text(t('golf_one_way_price'))),
              ],
              rows: [
                for (final row in _prices)
                  DataRow(
                    cells: [
                      DataCell(Text(row['fareGroup'].toString())),
                      DataCell(Text(row['vehicleTypeCode'].toString())),
                      DataCell(Text(row['holes'].toString())),
                      DataCell(
                        TextButton(
                          onPressed: _saving ? null : () => _edit(row as Map),
                          child: Text(row['roundTripPrice'].toString()),
                        ),
                      ),
                      DataCell(
                        Text(
                          row['holes'] == 18
                              ? '${(row['roundTripPrice'] as num) / 2}'
                              : '—',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          for (final c in _courses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${(c['names'] as Map)[language] ?? (c['names'] as Map)['en']} · ${c['fareGroup']}',
              ),
              subtitle: SelectableText(
                '${c['lat']}, ${c['lng']}\n${c['coordinateSource']}',
              ),
            ),
        ],
      ),
    );
  }
}
