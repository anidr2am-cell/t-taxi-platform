import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_pricing_api_service.dart';

class AdminPricingManagerPage extends StatefulWidget {
  const AdminPricingManagerPage({super.key, this.api});

  final AdminPricingApiService? api;

  @override
  State<AdminPricingManagerPage> createState() => _AdminPricingManagerPageState();
}

class _AdminPricingManagerPageState extends State<AdminPricingManagerPage>
    with SingleTickerProviderStateMixin {
  late final AdminPricingApiService _api =
      widget.api ?? const AdminPricingApiService();
  late final TabController _tabController;

  Map<String, dynamic>? _summary;
  List<dynamic> _routes = [];
  List<dynamic> _prices = [];
  List<dynamic> _policies = [];

  bool _loading = true;
  String? _error;
  bool _saving = false;

  String? _routeServiceFilter;
  String _routeOriginFilter = '';
  String _routeDestFilter = '';
  String? _routeActiveFilter;
  String _routeSearch = '';

  String? _priceRouteFilter;
  String? _priceStatusFilter;

  String? _policyActiveFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getSummary(),
        _api.listRoutes(includeInactive: true),
        _api.listVehiclePrices(includeInactive: true),
        _api.listChargePolicies(includeInactive: true),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _routes = results[1] as List<dynamic>;
        _prices = results[2] as List<dynamic>;
        _policies = results[3] as List<dynamic>;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  int _priceCountForRoute(int routeId) {
    return _prices.where((row) => row['routeId'] == routeId).length;
  }

  List<dynamic> get _filteredRoutes {
    return _routes.where((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_routeServiceFilter != null &&
          _routeServiceFilter!.isNotEmpty &&
          map['serviceTypeCode'] != _routeServiceFilter) {
        return false;
      }
      if (_routeOriginFilter.isNotEmpty &&
          !(map['originLocationCode'] as String? ?? '')
              .toUpperCase()
              .contains(_routeOriginFilter.toUpperCase())) {
        return false;
      }
      if (_routeDestFilter.isNotEmpty &&
          !(map['destinationLocationCode'] as String? ?? '')
              .toUpperCase()
              .contains(_routeDestFilter.toUpperCase())) {
        return false;
      }
      if (_routeActiveFilter == 'active' && map['isActive'] != true) return false;
      if (_routeActiveFilter == 'inactive' && map['isActive'] == true) return false;
      if (_routeSearch.isNotEmpty) {
        final haystack =
            '${map['id']} ${map['serviceTypeCode']} ${map['originLocationCode']} ${map['destinationLocationCode']}'
                .toLowerCase();
        if (!haystack.contains(_routeSearch.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  List<dynamic> get _filteredPrices {
    return _prices.where((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_priceRouteFilter != null && '${map['routeId']}' != _priceRouteFilter) {
        return false;
      }
      if (_priceStatusFilter != null &&
          vehiclePriceStatus(map) != _priceStatusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<dynamic> get _filteredPolicies {
    return _policies.where((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (_policyActiveFilter == 'active' && map['isActive'] != true) return false;
      if (_policyActiveFilter == 'inactive' && map['isActive'] == true) return false;
      return true;
    }).toList();
  }

  String _routeLabel(Map<String, dynamic> route) {
    return '#${route['id']} ${route['serviceTypeCode']} '
        '${route['originLocationCode']} → ${route['destinationLocationCode']}';
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _showRouteDialog({Map<String, dynamic>? existing}) async {
    final serviceType = ValueNotifier<String>(
      existing?['serviceTypeCode'] as String? ?? kServiceTypes.first,
    );
    final originCtrl = TextEditingController(
      text: existing?['originLocationCode'] as String? ?? '',
    );
    final destCtrl = TextEditingController(
      text: existing?['destinationLocationCode'] as String? ?? '',
    );
    final active = ValueNotifier<bool>(existing?['isActive'] as bool? ?? true);
    final formKey = GlobalKey<FormState>();
    Map<String, String>? fieldErrors;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create route' : 'Edit route'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder(
                    valueListenable: serviceType,
                    builder: (context, selected, child) => DropdownButtonFormField<String>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: 'Service type'),
                      items: kServiceTypes
                          .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                          .toList(),
                      onChanged: existing == null ? (v) => serviceType.value = v ?? selected : null,
                    ),
                  ),
                  TextFormField(
                    controller: originCtrl,
                    decoration: InputDecoration(
                      labelText: 'Origin code',
                      errorText: fieldErrors?['originLocationCode'],
                    ),
                    enabled: existing == null,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Origin is required' : null,
                  ),
                  TextFormField(
                    controller: destCtrl,
                    decoration: InputDecoration(
                      labelText: 'Destination code',
                      errorText: fieldErrors?['destinationLocationCode'],
                    ),
                    enabled: existing == null,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Destination is required' : null,
                  ),
                  ValueListenableBuilder(
                    valueListenable: active,
                    builder: (context, selected, child) => SwitchListTile(
                      title: const Text('Active'),
                      value: selected,
                      onChanged: (v) => active.value = v,
                    ),
                  ),
                  if (fieldErrors?['general'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(fieldErrors!['general']!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => _saving = true);
                      setDialogState(() => fieldErrors = null);
                      try {
                        if (existing == null) {
                          await _api.createRoute({
                            'serviceTypeCode': serviceType.value,
                            'originLocationCode': originCtrl.text.trim().toUpperCase(),
                            'destinationLocationCode': destCtrl.text.trim().toUpperCase(),
                            'isActive': active.value,
                          });
                        } else {
                          await _api.updateRoute(existing['id'] as int, {
                            'isActive': active.value,
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadAll();
                      } on AdminPricingApiException catch (err) {
                        setDialogState(() => fieldErrors = err.fieldErrors ?? {'general': err.message});
                      } catch (err) {
                        setDialogState(() => fieldErrors = {'general': err.toString()});
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );

    originCtrl.dispose();
    destCtrl.dispose();
    serviceType.dispose();
    active.dispose();
  }

  Future<void> _copyRoute(Map<String, dynamic> route) async {
    final destCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Map<String, String>? fieldErrors;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Copy route #${route['id']}'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: destCtrl,
              decoration: InputDecoration(
                labelText: 'New destination code',
                errorText: fieldErrors?['destinationLocationCode'],
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Destination is required' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => _saving = true);
                      try {
                        await _api.copyRoute(route['id'] as int, {
                          'originLocationId': route['originLocationId'],
                          'destinationLocationCode': destCtrl.text.trim().toUpperCase(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadAll();
                      } on AdminPricingApiException catch (err) {
                        setDialogState(() => fieldErrors = err.fieldErrors ?? {'general': err.message});
                      } catch (err) {
                        setDialogState(() => fieldErrors = {'general': err.toString()});
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
    destCtrl.dispose();
  }

  Future<void> _showPriceDialog({Map<String, dynamic>? existing}) async {
    final routeId = ValueNotifier<String?>(
      existing != null ? '${existing['routeId']}' : (_routes.isNotEmpty ? '${_routes.first['id']}' : null),
    );
    final vehicleType = ValueNotifier<String>(
      existing?['vehicleTypeCode'] as String? ?? kVehicleTypes.first,
    );
    final priceCtrl = TextEditingController(text: '${existing?['price'] ?? ''}');
    final currencyCtrl = TextEditingController(text: existing?['currency'] as String? ?? 'THB');
    final fromCtrl = TextEditingController(text: existing?['effectiveFrom'] as String? ?? '');
    final toCtrl = TextEditingController(text: existing?['effectiveTo'] as String? ?? '');
    final active = ValueNotifier<bool>(existing?['isActive'] as bool? ?? true);
    final formKey = GlobalKey<FormState>();
    Map<String, String>? fieldErrors;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create vehicle price' : 'Edit vehicle price'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: routeId,
                      builder: (context, selected, child) => DropdownButtonFormField<String>(
                        key: ValueKey(selected),
                        initialValue: selected,
                        decoration: const InputDecoration(labelText: 'Route'),
                        items: _routes
                            .map((row) {
                              final map = Map<String, dynamic>.from(row as Map);
                              return DropdownMenuItem(
                                value: '${map['id']}',
                                child: Text(_routeLabel(map)),
                              );
                            })
                            .toList(),
                        onChanged: existing == null ? (v) => routeId.value = v : null,
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: vehicleType,
                      builder: (context, selected, child) => DropdownButtonFormField<String>(
                        key: ValueKey(selected),
                        initialValue: selected,
                        decoration: const InputDecoration(labelText: 'Vehicle type'),
                        items: kVehicleTypes
                            .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                            .toList(),
                        onChanged: existing == null ? (v) => vehicleType.value = v ?? selected : null,
                      ),
                    ),
                    TextFormField(
                      controller: priceCtrl,
                      decoration: InputDecoration(
                        labelText: 'Price',
                        errorText: fieldErrors?['price'],
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'Price must be greater than 0';
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: currencyCtrl,
                      decoration: InputDecoration(
                        labelText: 'Currency',
                        errorText: fieldErrors?['currency'],
                      ),
                      maxLength: 3,
                    ),
                    TextFormField(
                      controller: fromCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Effective from (ISO, optional)',
                      ),
                    ),
                    TextFormField(
                      controller: toCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Effective to (ISO, optional)',
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: active,
                      builder: (context, selected, child) => SwitchListTile(
                        title: const Text('Active'),
                        value: selected,
                        onChanged: (v) => active.value = v,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => _saving = true);
                      try {
                        final body = <String, dynamic>{
                          'price': double.parse(priceCtrl.text.trim()),
                          'currency': currencyCtrl.text.trim().toUpperCase(),
                          'isActive': active.value,
                        };
                        if (fromCtrl.text.trim().isNotEmpty) {
                          body['effectiveFrom'] = fromCtrl.text.trim();
                        }
                        if (toCtrl.text.trim().isNotEmpty) {
                          body['effectiveTo'] = toCtrl.text.trim();
                        }
                        if (existing == null) {
                          body['routeId'] = int.parse(routeId.value!);
                          body['vehicleTypeCode'] = vehicleType.value;
                          await _api.createVehiclePrice(body);
                        } else {
                          await _api.updateVehiclePrice(existing['id'] as int, body);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadAll();
                      } on AdminPricingApiException catch (err) {
                        setDialogState(() => fieldErrors = err.fieldErrors ?? {'general': err.message});
                      } catch (err) {
                        setDialogState(() => fieldErrors = {'general': err.toString()});
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    routeId.dispose();
    vehicleType.dispose();
    priceCtrl.dispose();
    currencyCtrl.dispose();
    fromCtrl.dispose();
    toCtrl.dispose();
    active.dispose();
  }

  Future<void> _showPolicyDialog({Map<String, dynamic>? existing}) async {
    final chargeType = ValueNotifier<String>(
      existing?['chargeType'] as String? ?? kChargePolicyTypes.first,
    );
    final calcType = ValueNotifier<String>(
      existing?['calculationType'] as String? ?? kCalculationTypes.first,
    );
    final amountCtrl = TextEditingController(text: '${existing?['amount'] ?? ''}');
    final fromCtrl = TextEditingController(text: existing?['effectiveFrom'] as String? ?? '');
    final toCtrl = TextEditingController(text: existing?['effectiveTo'] as String? ?? '');
    final active = ValueNotifier<bool>(existing?['isActive'] as bool? ?? true);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Create charge policy' : 'Edit charge policy'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder(
                    valueListenable: chargeType,
                    builder: (context, selected, child) => DropdownButtonFormField<String>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: 'Charge type'),
                      items: kChargePolicyTypes
                          .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                          .toList(),
                      onChanged: existing == null ? (v) => chargeType.value = v ?? selected : null,
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: calcType,
                    builder: (context, selected, child) => DropdownButtonFormField<String>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: 'Calculation type'),
                      items: kCalculationTypes
                          .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                          .toList(),
                      onChanged: (v) => calcType.value = v ?? selected,
                    ),
                  ),
                  TextFormField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Amount must be zero or greater';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: fromCtrl,
                    decoration: const InputDecoration(labelText: 'Effective from (optional)'),
                  ),
                  TextFormField(
                    controller: toCtrl,
                    decoration: const InputDecoration(labelText: 'Effective to (optional)'),
                  ),
                  ValueListenableBuilder(
                    valueListenable: active,
                    builder: (context, selected, child) => SwitchListTile(
                      title: const Text('Active'),
                      value: selected,
                      onChanged: (v) => active.value = v,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() => _saving = true);
                    try {
                      final body = <String, dynamic>{
                        'calculationType': calcType.value,
                        'amount': double.parse(amountCtrl.text.trim()),
                        'isActive': active.value,
                      };
                      if (fromCtrl.text.trim().isNotEmpty) body['effectiveFrom'] = fromCtrl.text.trim();
                      if (toCtrl.text.trim().isNotEmpty) body['effectiveTo'] = toCtrl.text.trim();
                      if (existing == null) {
                        body['chargeType'] = chargeType.value;
                        await _api.createChargePolicy(body);
                      } else {
                        body['chargeType'] = chargeType.value;
                        await _api.updateChargePolicy(existing['id'] as int, body);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadAll();
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    chargeType.dispose();
    calcType.dispose();
    amountCtrl.dispose();
    fromCtrl.dispose();
    toCtrl.dispose();
    active.dispose();
  }

  Widget _summaryCards() {
    final summary = _summary ?? {};
    final cards = [
      ('Active routes', summary['activeRouteCount'] ?? 0, Icons.route, AppStatusTone.info),
      ('Active vehicle prices', summary['activeVehiclePriceCount'] ?? 0, Icons.directions_car_filled_outlined, AppStatusTone.success),
      ('Active charge policies', summary['activeChargePolicyCount'] ?? 0, Icons.policy_outlined, AppStatusTone.neutral),
      ('Current prices', summary['currentPriceCount'] ?? 0, Icons.payments_outlined, AppStatusTone.success),
      ('Expiring soon', summary['expiringSoonPriceCount'] ?? 0, Icons.schedule, AppStatusTone.warning),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map(
            (item) => AppUi.kpiMetricCard(
              label: item.$1,
              value: '${item.$2}',
              icon: item.$3,
              tone: item.$4,
            ),
          )
          .toList(),
    );
  }

  Widget _routesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_routeServiceFilter),
                  initialValue: _routeServiceFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Service type', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...kServiceTypes.map((code) => DropdownMenuItem(value: code, child: Text(code))),
                  ],
                  onChanged: (v) => setState(() => _routeServiceFilter = v),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Origin', isDense: true),
                  onChanged: (v) => setState(() => _routeOriginFilter = v),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Destination', isDense: true),
                  onChanged: (v) => setState(() => _routeDestFilter = v),
                ),
              ),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_routeActiveFilter),
                  initialValue: _routeActiveFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Active', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => _routeActiveFilter = v),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Search', isDense: true),
                  onChanged: (v) => setState(() => _routeSearch = v),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showRouteDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Create route'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredRoutes.isEmpty
              ? const Center(child: Text('No routes found'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('ID')),
                      DataColumn(label: Text('Service')),
                      DataColumn(label: Text('Origin')),
                      DataColumn(label: Text('Destination')),
                      DataColumn(label: Text('Active')),
                      DataColumn(label: Text('Prices')),
                      DataColumn(label: Text('Updated')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: _filteredRoutes.map((row) {
                      final map = Map<String, dynamic>.from(row as Map);
                      return DataRow(cells: [
                        DataCell(Text('${map['id']}')),
                        DataCell(Text('${map['serviceTypeCode']}')),
                        DataCell(Text('${map['originLocationCode']}')),
                        DataCell(Text('${map['destinationLocationCode']}')),
                        DataCell(Text(map['isActive'] == true ? 'Yes' : 'No')),
                        DataCell(Text('${_priceCountForRoute(map['id'] as int)}')),
                        DataCell(Text('${map['updatedAt'] ?? '-'}')),
                        DataCell(Row(
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showRouteDialog(existing: map),
                            ),
                            IconButton(
                              tooltip: 'Copy',
                              icon: const Icon(Icons.copy),
                              onPressed: () => _copyRoute(map),
                            ),
                            IconButton(
                              tooltip: 'View prices',
                              icon: const Icon(Icons.price_change),
                              onPressed: () {
                                setState(() {
                                  _priceRouteFilter = '${map['id']}';
                                  _tabController.index = 1;
                                });
                              },
                            ),
                            if (map['isActive'] == true)
                              IconButton(
                                tooltip: 'Deactivate',
                                icon: const Icon(Icons.block),
                                onPressed: () async {
                                  if (!await _confirm(
                                    'Deactivate route',
                                    'This route will be excluded from customer pricing.',
                                  )) {
                                    return;
                                  }
                                  setState(() => _saving = true);
                                  try {
                                    await _api.updateRoute(map['id'] as int, {'isActive': false});
                                    await _loadAll();
                                  } finally {
                                    if (mounted) setState(() => _saving = false);
                                  }
                                },
                              ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _pricesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_priceRouteFilter),
                  initialValue: _priceRouteFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Route', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All routes')),
                    ..._routes.map((row) {
                      final map = Map<String, dynamic>.from(row as Map);
                      return DropdownMenuItem(
                        value: '${map['id']}',
                        child: Text(_routeLabel(map)),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _priceRouteFilter = v),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_priceStatusFilter),
                  initialValue: _priceStatusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: 'current', child: Text('Current')),
                    DropdownMenuItem(value: 'future', child: Text('Future')),
                    DropdownMenuItem(value: 'expired', child: Text('Expired')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => _priceStatusFilter = v),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showPriceDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Create price'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredPrices.isEmpty
              ? const Center(child: Text('No vehicle prices found'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Route')),
                      DataColumn(label: Text('Vehicle')),
                      DataColumn(label: Text('Price')),
                      DataColumn(label: Text('Currency')),
                      DataColumn(label: Text('Effective from')),
                      DataColumn(label: Text('Effective to')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: _filteredPrices.map((row) {
                      final map = Map<String, dynamic>.from(row as Map);
                      final route = _routes.cast<Map?>().firstWhere(
                            (r) => r?['id'] == map['routeId'],
                            orElse: () => null,
                          );
                      final status = vehiclePriceStatus(map);
                      return DataRow(cells: [
                        DataCell(Text(route != null ? _routeLabel(Map<String, dynamic>.from(route)) : '${map['routeId']}')),
                        DataCell(Text('${map['vehicleTypeCode']}')),
                        DataCell(Text('${map['price']}')),
                        DataCell(Text('${map['currency']}')),
                        DataCell(Text('${map['effectiveFrom'] ?? '-'}')),
                        DataCell(Text('${map['effectiveTo'] ?? '-'}')),
                        DataCell(Text(status)),
                        DataCell(Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showPriceDialog(existing: map),
                            ),
                            if (map['isActive'] == true)
                              IconButton(
                                icon: const Icon(Icons.block),
                                onPressed: () async {
                                  if (!await _confirm(
                                    'Deactivate price',
                                    'This price will no longer apply to customer pricing.',
                                  )) {
                                    return;
                                  }
                                  await _api.updateVehiclePrice(map['id'] as int, {'isActive': false});
                                  await _loadAll();
                                },
                              ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _policiesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_policyActiveFilter),
                  initialValue: _policyActiveFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Active', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => _policyActiveFilter = v),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showPolicyDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Create policy'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredPolicies.isEmpty
              ? const Center(child: Text('No charge policies found'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Calculation')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Active')),
                      DataColumn(label: Text('Period')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: _filteredPolicies.map((row) {
                      final map = Map<String, dynamic>.from(row as Map);
                      final status = chargePolicyStatus(map);
                      return DataRow(cells: [
                        DataCell(Text('${map['chargeType']}')),
                        DataCell(Text('${map['calculationType']}')),
                        DataCell(Text('${map['amount']}')),
                        DataCell(Text(map['isActive'] == true ? 'Yes' : 'No')),
                        DataCell(Text('${map['effectiveFrom'] ?? '-'} → ${map['effectiveTo'] ?? '-'}')),
                        DataCell(Text(status)),
                        DataCell(Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showPolicyDialog(existing: map),
                            ),
                            if (map['isActive'] == true)
                              IconButton(
                                icon: const Icon(Icons.block),
                                onPressed: () async {
                                  if (!await _confirm(
                                    'Deactivate policy',
                                    'This policy will be excluded from pricing calculations.',
                                  )) {
                                    return;
                                  }
                                  await _api.updateChargePolicy(map['id'] as int, {'isActive': false});
                                  await _loadAll();
                                },
                              ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _simulatorTab() {
    return _PricingSimulatorPanel(api: _api, routes: _routes, prices: _prices);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return AppUi.loadingState();
    }
    if (_error != null && _summary == null) {
      return AppUi.errorState(
        message: _error!,
        onRetry: _loadAll,
        retryLabel: 'Retry',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: AppUi.pagePadding(context).copyWith(bottom: 0),
          child: AppUi.sectionHeader(
            context,
            title: 'Pricing Manager',
            trailing: IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          ),
        ),
        Padding(
          padding: AppUi.pagePadding(context),
          child: _summaryCards(),
        ),
        Material(
          color: AppTokens.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTokens.primary,
            unselectedLabelColor: AppTokens.textSecondary,
            indicatorColor: AppTokens.primary,
            tabs: const [
              Tab(text: 'Routes'),
              Tab(text: 'Vehicle Prices'),
              Tab(text: 'Charge Policies'),
              Tab(text: 'Simulator'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _routesTab(),
              _pricesTab(),
              _policiesTab(),
              _simulatorTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _PricingSimulatorPanel extends StatefulWidget {
  const _PricingSimulatorPanel({
    required this.api,
    required this.routes,
    required this.prices,
  });

  final AdminPricingApiService api;
  final List<dynamic> routes;
  final List<dynamic> prices;

  @override
  State<_PricingSimulatorPanel> createState() => _PricingSimulatorPanelState();
}

class _PricingSimulatorPanelState extends State<_PricingSimulatorPanel> {
  String? _routeId;
  String? _vehicleTypeId;
  bool _nameSign = false;
  bool _waiting = false;
  bool _parking = false;
  bool _toll = false;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  List<Map<String, dynamic>> get _activeRoutes =>
      widget.routes.where((row) => row['isActive'] == true).map((row) => Map<String, dynamic>.from(row as Map)).toList();

  List<Map<String, dynamic>> _vehicleOptionsForRoute(String? routeId) {
    if (routeId == null) return [];
    final routePrices = widget.prices.where((row) => '${row['routeId']}' == routeId);
    final seen = <String>{};
    final options = <Map<String, dynamic>>[];
    for (final row in routePrices) {
      final map = Map<String, dynamic>.from(row as Map);
      final key = '${map['vehicleTypeId']}';
      if (seen.add(key)) options.add(map);
    }
    return options;
  }

  Future<void> _run() async {
    final route = _activeRoutes.cast<Map<String, dynamic>?>().firstWhere(
          (row) => '${row?['id']}' == _routeId,
          orElse: () => null,
        );
    if (route == null || _vehicleTypeId == null) {
      setState(() => _error = 'Select a route and vehicle type');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await widget.api.simulatePricing({
        'serviceType': route['serviceTypeCode'],
        'originLocationId': route['originLocationId'],
        'destinationLocationId': route['destinationLocationId'],
        'vehicleTypeId': int.parse(_vehicleTypeId!),
        'options': {
          'nameSign': _nameSign,
          'waiting': _waiting,
          'parking': _parking,
          'toll': _toll,
        },
      });
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleOptions = _vehicleOptionsForRoute(_routeId);

    return ListView(
      padding: AppUi.pagePadding(context),
      children: [
        AppUi.surfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
          key: Key('simulator_route_dropdown:${_routeId ?? ''}'),
          initialValue: _routeId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Route'),
          items: _activeRoutes
              .map(
                (route) => DropdownMenuItem(
                  value: '${route['id']}',
                  child: Text(
                    '${route['serviceTypeCode']} ${route['originLocationCode']} → ${route['destinationLocationCode']}',
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _routeId = v;
            _vehicleTypeId = null;
          }),
        ),
        DropdownButtonFormField<String?>(
          key: Key('simulator_vehicle_dropdown:${_vehicleTypeId ?? ''}'),
          initialValue: _vehicleTypeId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Vehicle type'),
          items: vehicleOptions
              .map(
                (price) => DropdownMenuItem(
                  value: '${price['vehicleTypeId']}',
                  child: Text('${price['vehicleTypeCode']} (${price['price']} ${price['currency']})'),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _vehicleTypeId = v),
        ),
        SwitchListTile(title: const Text('Name sign'), value: _nameSign, onChanged: (v) => setState(() => _nameSign = v)),
        SwitchListTile(title: const Text('Waiting'), value: _waiting, onChanged: (v) => setState(() => _waiting = v)),
        SwitchListTile(title: const Text('Parking'), value: _parking, onChanged: (v) => setState(() => _parking = v)),
        SwitchListTile(title: const Text('Toll'), value: _toll, onChanged: (v) => setState(() => _toll = v)),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _loading ? null : _run,
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Calculate'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.errorLight,
            child: Text(_error!, style: const TextStyle(color: AppTokens.error)),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.primaryLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total: ${_result!['totalAmount']} ${_result!['currency']}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTokens.primaryDark,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Text('Subtotal: ${_result!['subtotal']}  Discount: ${_result!['discount']}'),
                const SizedBox(height: AppTokens.spaceSm),
                Text('Matched route: ${_result!['matchedRoute']?['id']}'),
                Text(
                  'Base price: ${_result!['vehicleBasePrice']?['price']} ${_result!['vehicleBasePrice']?['currency']}',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          AppUi.adminDetailSection(
            context: context,
            title: 'Charge items',
            child: Column(
              children: ((_result!['chargeItems'] as List<dynamic>? ?? []).map(
                (item) {
                  final map = Map<String, dynamic>.from(item as Map);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('${map['description'] ?? map['chargeType']}')),
                        Text('${map['amount']}'),
                      ],
                    ),
                  );
                },
              )).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
