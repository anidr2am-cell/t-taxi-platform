import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../../../core/network/api_exception.dart';
import '../data/settlement_api.dart';
import '../data/settlement_models.dart';
import 'settlement_detail_page.dart';

class SettlementListPage extends StatefulWidget {
  const SettlementListPage({
    super.key,
    required this.api,
    required this.onUnauthorized,
    this.refreshRequest = 0,
    this.onChanged,
  });

  final SettlementDataSource api;
  final Future<void> Function() onUnauthorized;
  final int refreshRequest;
  final VoidCallback? onChanged;

  @override
  State<SettlementListPage> createState() => _SettlementListPageState();
}

class _SettlementListPageState extends State<SettlementListPage> {
  List<SettlementItem>? _items;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SettlementListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRequest != widget.refreshRequest) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listSettlements();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      widget.onChanged?.call();
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const ApiException(ApiFailureKind.unknown);
        _loading = false;
      });
    }
  }

  Future<void> _open(SettlementItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettlementDetailPage(
          api: widget.api,
          bookingNumber: item.bookingNumber,
          onUnauthorized: widget.onUnauthorized,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _load();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settlementTitle)),
      body: switch ((_loading, _items, _error)) {
        (true, _, _) => const Center(
          key: Key('settlementListLoading'),
          child: CircularProgressIndicator(),
        ),
        (false, _, final error?) => Center(
          key: const Key('settlementListError'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.localizedMessage(l10n), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: Text(l10n.retry)),
              ],
            ),
          ),
        ),
        (false, final items?, _) when items.isEmpty => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const Key('settlementListEmpty'),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 180),
              Icon(Icons.receipt_long_outlined, size: 56),
              SizedBox(height: 12),
              Center(child: Text(l10n.settlementListEmpty)),
            ],
          ),
        ),
        (false, final items?, _) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            key: const Key('settlementListSuccess'),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (_, index) => _SettlementCard(
              item: items[index],
              onTap: () => _open(items[index]),
            ),
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.item, required this.onTap});

  final SettlementItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final customerCurrency =
        item.customerPaymentCurrency ??
        item.customerTotalCurrency ??
        item.currency;
    final commissionAmount =
        item.companyCommissionAmount ?? item.commissionAmount;
    final commissionCurrency =
        item.companyCommissionCurrency ?? item.currency;
    final driverIncomeCurrency =
        item.driverExpectedIncomeCurrency ?? item.currency;
    final nameSignAmount = item.nameSignAmount;
    final showNameSignNote =
        nameSignAmount != null && nameSignAmount > 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InkWell(
        key: Key('settlement-${item.bookingNumber}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.receipt_long_outlined, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.bookingNumber,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SettlementAmountLine(
                                key: Key(
                                  'settlementCustomerPayment-${item.bookingNumber}',
                                ),
                                label: l10n.customerPaymentAmount,
                                amount:
                                    item.customerPaymentAmount ??
                                    item.customerTotalAmount,
                                currency: customerCurrency,
                              ),
                              const SizedBox(height: 8),
                              _SettlementAmountLine(
                                key: Key(
                                  'settlementDriverIncome-${item.bookingNumber}',
                                ),
                                label: l10n.driverIncome,
                                amount: item.driverExpectedIncomeAmount,
                                currency: driverIncomeCurrency,
                                emphasized: true,
                              ),
                              if (showNameSignNote) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.nameSignCostIncluded(
                                    formatSettlementMoneyLocalized(
                                      l10n,
                                      nameSignAmount,
                                      null,
                                    ),
                                  ),
                                  key: Key(
                                    'settlementNameSignNote-${item.bookingNumber}',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colors.outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _SettlementAmountLine(
                          key: Key(
                            'settlementCommission-${item.bookingNumber}',
                          ),
                          label: l10n.commissionFee,
                          amount: commissionAmount,
                          currency: commissionCurrency,
                          alignEnd: true,
                        ),
                      ],
                    ),
                    if (item.dueAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.dueAtLabel(item.dueAt!),
                        key: Key('settlementDueAt-${item.bookingNumber}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  _StatusChip(status: item.commissionStatus),
                  Icon(Icons.chevron_right, color: colors.outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementAmountLine extends StatelessWidget {
  const _SettlementAmountLine({
    super.key,
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasized = false,
    this.alignEnd = false,
  });

  final String label;
  final num? amount;
  final String? currency;
  final bool emphasized;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final crossAxis = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final valueStyle = emphasized
        ? theme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primary,
          )
        : theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: crossAxis,
      children: [
        Text(
          label,
          style: theme.bodySmall?.copyWith(color: colors.outline),
        ),
        const SizedBox(height: 2),
        Text(
          formatSettlementMoneyLocalized(l10n, amount, currency),
          style: valueStyle,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SettlementStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final color = switch (status.code) {
      SettlementStatusCode.due => Colors.orange,
      SettlementStatusCode.overdue ||
      SettlementStatusCode.rejected => colors.error,
      SettlementStatusCode.receiptSubmitted => colors.primary,
      SettlementStatusCode.approved ||
      SettlementStatusCode.waived => Colors.green,
      _ => colors.outline,
    };
    return Chip(
      key: Key('settlementStatus-${status.raw}'),
      label: Text(status.localizedLabel(l10n)),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }
}
