import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/calling_countries.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/browser_download.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_dispatch/services/admin_dispatch_api_service.dart';
import '../../booking/utils/thailand_pickup_datetime.dart';

class AdminStatisticsPage extends StatefulWidget {
  const AdminStatisticsPage({
    super.key,
    this.api = const AdminDispatchApiService(),
  });

  final AdminDispatchApiService api;

  @override
  State<AdminStatisticsPage> createState() => _AdminStatisticsPageState();
}

class _AdminStatisticsPageState extends State<AdminStatisticsPage> {
  static const _optionKeys = [
    'nameSign',
    'femaleDriver',
    'golfDriver',
    'coupon',
  ];
  final _dateFormat = DateFormat('yyyy-MM-dd');
  late DateTimeRange _range;
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _failed = false;
  bool _tooLong = false;
  bool _monthly = false;

  @override
  void initState() {
    super.initState();
    final now = ThailandPickupDateTime.thailandNow();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _data = null;
    });
    try {
      final data = await widget.api.getStatistics(
        _dateFormat.format(_range.start),
        _dateFormat.format(_range.end),
      );
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final now = ThailandPickupDateTime.thailandNow();
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (selected == null || !mounted) return;
    final days =
        DateTime.utc(selected.end.year, selected.end.month, selected.end.day)
            .difference(
              DateTime.utc(
                selected.start.year,
                selected.start.month,
                selected.start.day,
              ),
            )
            .inDays;
    setState(() => _tooLong = days >= 366);
    if (_tooLong) return;
    setState(() => _range = selected);
    await _load();
  }

  List<Map<String, dynamic>> _rows(String key) => (_data?[key] as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  String _countryLabel(Object? code, AppLocalizations l10n) {
    if (code == null) return l10n.t('admin_stats_unknown');
    final countries = callingCountries
        .where((country) => country.dialCode == code)
        .toList();
    if (countries.length == 1) return countries.single.label(l10n.languageCode);
    return '$code · ${l10n.t('admin_stats_shared')}';
  }

  String _serviceLabel(Object? code, AppLocalizations l10n) {
    final key = switch (code) {
      'AIRPORT_PICKUP' => 'airport_pickup',
      'AIRPORT_DROPOFF' => 'airport_dropoff',
      'CITY_TRANSFER' => 'city_transfer',
      'GOLF_TRANSFER' => 'golf_transfer',
      _ => null,
    };
    return key == null ? (code?.toString() ?? '') : l10n.t(key);
  }

  void _export() {
    final records = <List<Object?>>[
      [
        'section',
        'key',
        'bookings',
        'passengers',
        ..._optionKeys,
        'from',
        'to',
        'timezone',
      ],
      for (final section in [
        'daily',
        'monthly',
        'countries',
        'flights',
        'services',
      ])
        for (final row in _rows(section))
          [
            section,
            row['key'],
            row['bookings'],
            row['passengers'],
            for (final option in _optionKeys) row['options']?[option],
            _data!['from'],
            _data!['to'],
            _data!['timezone'],
          ],
    ];
    String cell(Object? value) {
      var text = value?.toString() ?? '';
      if (RegExp(r'^[=+@-]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    final csv = records.map((row) => row.map(cell).join(',')).join('\r\n');
    downloadBytes(
      Uint8List.fromList(utf8.encode('\ufeff$csv')),
      'booking-statistics-${_data!['from']}-${_data!['to']}.csv',
      'text/csv;charset=utf-8',
    );
  }

  Widget _table(
    String title,
    String keyLabel,
    List<Map<String, dynamic>> rows,
    String Function(Object?) label, {
    bool options = false,
  }) {
    final l = context.l10n;
    final format = NumberFormat.decimalPattern(l.languageCode);
    String count(Object? value) => format.format(value is num ? value : 0);
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSm),
              child: Text(l.t('admin_stats_empty')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(keyLabel)),
                  DataColumn(
                    label: Text(l.t('admin_stats_bookings')),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l.t('admin_stats_passengers')),
                    numeric: true,
                  ),
                  if (options)
                    for (final option in _optionKeys)
                      DataColumn(
                        label: Text(l.t('admin_stats_$option')),
                        numeric: true,
                      ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(label(row['key']))),
                        DataCell(Text(count(row['bookings']))),
                        DataCell(Text(count(row['passengers']))),
                        if (options)
                          for (final option in _optionKeys)
                            DataCell(Text(count(row['options']?[option]))),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final totals = _data?['totals'];
    final number = NumberFormat.decimalPattern(l.languageCode);
    final flights = _rows('flights');
    return ListView(
      padding: AppUi.pagePadding(context),
      children: [
        Text(
          l.t('admin_statistics'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(l.t('admin_stats_scope')),
        const SizedBox(height: AppTokens.spaceMd),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                '${_dateFormat.format(_range.start)} – ${_dateFormat.format(_range.end)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _data == null ? null : _export,
              icon: const Icon(Icons.download),
              label: Text(l.t('admin_stats_csv')),
            ),
          ],
        ),
        if (_tooLong) Text(l.t('admin_stats_range_limit')),
        if (_loading) const LinearProgressIndicator(),
        if (_failed)
          TextButton(onPressed: _load, child: Text(l.t('admin_stats_retry'))),
        if (totals != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            child: Wrap(
              spacing: AppTokens.spaceLg,
              runSpacing: AppTokens.spaceMd,
              children: [
                for (final key in ['bookings', 'passengers', ..._optionKeys])
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.t('admin_stats_$key')),
                      Text(
                        number.format(
                          totals[key] ?? totals['options']?[key] ?? 0,
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l.t('admin_stats_daily')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l.t('admin_stats_monthly')),
                ),
              ],
              selected: {_monthly},
              onSelectionChanged: (value) =>
                  setState(() => _monthly = value.single),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _table(
            l.t(_monthly ? 'admin_stats_monthly' : 'admin_stats_daily'),
            l.t('admin_stats_period'),
            _rows(_monthly ? 'monthly' : 'daily'),
            (key) => key.toString(),
            options: true,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _table(
            l.t('admin_stats_services'),
            l.t('admin_stats_service'),
            _rows('services'),
            (key) => _serviceLabel(key, l),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(l.t('admin_stats_country_note')),
          const SizedBox(height: AppTokens.spaceSm),
          _table(
            l.t('admin_stats_countries'),
            l.t('admin_stats_dial_code'),
            _rows('countries'),
            (key) => _countryLabel(key, l),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _table(
            l.t('admin_stats_flights'),
            l.t('flight_number'),
            flights.take(20).toList(),
            (key) => key.toString(),
          ),
        ],
      ],
    );
  }
}
