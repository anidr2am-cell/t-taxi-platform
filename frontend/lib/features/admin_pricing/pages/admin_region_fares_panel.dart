import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../services/admin_pricing_api_service.dart';

class AdminRegionFaresPanel extends StatefulWidget {
  const AdminRegionFaresPanel({super.key, required this.api});
  final AdminPricingApiService api;
  @override
  State<AdminRegionFaresPanel> createState() => _AdminRegionFaresPanelState();
}

class _AdminRegionFaresPanelState extends State<AdminRegionFaresPanel> {
  AdminRegionPricingApiService get _regionApi =>
      widget.api is AdminRegionPricingApiService
      ? widget.api as AdminRegionPricingApiService
      : const AdminRegionPricingApiService();
  List<dynamic> _regions = [], _routes = [], _prices = [], _candidates = [];
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
        _regionApi.listPricingRegions(),
        _regionApi.listRegionFareCandidates(),
        widget.api.listRoutes(includeInactive: false),
        widget.api.listVehiclePrices(includeInactive: false),
      ]);
      if (mounted)
        setState(() {
          _regions = data[0];
          _candidates = data[1];
          _routes = data[2];
          _prices = data[3];
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

  String _geometrySummary(Map geometry) {
    final t = context.l10n.t;
    if (geometry['type'] == 'Circle')
      return '${t('admin_region_latitude')}: ${geometry['lat']} · ${t('admin_region_longitude')}: ${geometry['lng']} · ${t('admin_region_radius')}: ${geometry['radiusKm']} km';
    return t('admin_region_points').replaceAll(
      '{count}',
      '${(geometry['coordinates'] as List).first.length}',
    );
  }

  Future<void> _editRegion(Map r) async {
    final t = context.l10n.t;
    final g = Map<String, dynamic>.from(r['geometry'] as Map);
    final circle = g['type'] == 'Circle';
    final geometry = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(g),
    );
    final lat = TextEditingController(text: '${g['lat'] ?? ''}');
    final lng = TextEditingController(text: '${g['lng'] ?? ''}');
    final radius = TextEditingController(text: '${g['radiusKm'] ?? ''}');
    final priority = TextEditingController(text: '${r['priority']}');
    final form = GlobalKey<FormState>();
    Widget number(
      TextEditingController c,
      String label,
      double min,
      double max,
    ) => TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: t(label)),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      validator: (v) {
        final n = double.tryParse(v ?? '');
        return n == null || !n.isFinite || n < min || n > max || (c == priority && n % 1 != 0)
            ? t('admin_region_invalid')
            : null;
      },
    );
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t('admin_region_boundary')} · ${r['code']}'),
        content: SizedBox(
          width: AppTokens.maxContentWidth,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (circle) ...[
                    number(lat, 'admin_region_latitude', -90, 90),
                    number(lng, 'admin_region_longitude', -180, 180),
                    number(radius, 'admin_region_radius', 0.001, 200),
                  ] else ...[
                    Text(t('admin_region_geometry_help')),
                    TextFormField(
                      controller: geometry,
                      minLines: 5,
                      maxLines: 12,
                      decoration: InputDecoration(
                        labelText: t('admin_region_geometry'),
                      ),
                      validator: (v) {
                        try {
                          final m = jsonDecode(v ?? '');
                          if (m is! Map || m['type'] != 'Polygon')
                            return t('admin_region_invalid');
                        } catch (_) {
                          return t('admin_region_invalid');
                        }
                        return null;
                      },
                    ),
                  ],
                  number(priority, 'admin_region_priority', 0, 1000),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('admin_region_cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text(t('admin_region_save')),
          ),
        ],
      ),
    );
    final ok = await Navigator.of(context).push(route);
    await route.completed;
    if (ok == true && mounted) {
      await _save(
        () => _regionApi.updatePricingRegion(r['id'] as int, {
          'geometry': circle
              ? {
                  'type': 'Circle',
                  'lat': double.parse(lat.text),
                  'lng': double.parse(lng.text),
                  'radiusKm': double.parse(radius.text),
                }
              : jsonDecode(geometry.text),
          'priority': int.parse(priority.text),
          'isActive': r['is_active'] == 1 || r['is_active'] == true,
        }),
      );
    }
    for (final c in [geometry, lat, lng, radius, priority]) {
      c.dispose();
    }
  }

  Iterable<Map> get _matrixRoutes sync* {
    for (final row in _routes) {
      final origins = _regions
          .where((r) => r['fare_location_code'] == row['originLocationCode'])
          .toList();
      final destinations = _regions
          .where(
            (r) => r['fare_location_code'] == row['destinationLocationCode'],
          )
          .toList();
      for (final o
          in origins.isEmpty
              ? [
                  {'code': row['originLocationCode']},
                ]
              : origins) {
        for (final d
            in destinations.isEmpty
                ? [
                    {'code': row['destinationLocationCode']},
                  ]
                : destinations) {
          yield {
            ...row as Map,
            'originRegionCode': o['code'],
            'destinationRegionCode': d['code'],
          };
        }
      }
    }
  }

  Future<void> _editPrice(Map row) async {
    final t = context.l10n.t;
    final amount = TextEditingController(text: '${row['price']}');
    final form = GlobalKey<FormState>();
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('admin_region_fixed_price')),
        semanticLabel: t('admin_region_shared'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('admin_region_shared')),
            TextFormField(
            controller: amount,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = double.tryParse(v ?? '');
              return n == null || !n.isFinite || n <= 0
                  ? t('admin_region_invalid')
                  : null;
            },
          ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('admin_region_cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text(t('admin_region_save')),
          ),
        ],
      ),
    );
    final ok = await Navigator.of(context).push(route);
    await route.completed;
    if (ok == true && mounted)
      await _save(
        () => widget.api.updateVehiclePrice(row['id'] as int, {
          'price': double.parse(amount.text),
        }),
      );
    amount.dispose();
  }

  Future<void> _save(Future<dynamic> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      await _load();
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      children: [
        Text(
          t('admin_region_proposal'),
          style: const TextStyle(color: AppTokens.textSecondary),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppTokens.error)),
        Text(
          t('admin_region_boundary'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final r in _regions)
          Card(
            child: ListTile(
              title: Text('${r['code']} → ${r['fare_location_code']}'),
              subtitle: Text(_geometrySummary(r['geometry'] as Map)),
              isThreeLine: false,
              trailing: IconButton(
                tooltip: t('admin_region_edit'),
                onPressed: _saving ? null : () => _editRegion(r as Map),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          ),
        const SizedBox(height: AppTokens.spaceMd),
        Text(
          t('admin_region_fares'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final route in _matrixRoutes)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${route['serviceTypeCode']} · ${route['originRegionCode']} → ${route['destinationRegionCode']}',
                  ),
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      for (final price in _prices.where(
                        (p) => p['routeId'] == route['id'],
                      ))
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _editPrice(price as Map),
                          child: Text(
                            '${price['vehicleTypeCode']} · ${price['price']} THB',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppTokens.spaceMd),
        Text(
          t('admin_region_pending'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final candidate in _candidates)
          Card(
            child: ListTile(
              title: Text(
                '${candidate['origin']} → ${candidate['destination']}',
              ),
              subtitle: Text(
                '${t('fare_inquiry_title')} · ${candidate['prices']}',
              ),
            ),
          ),
      ],
    );
  }
}
