import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('정산')),
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
                Text(error.userMessage, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('다시 시도')),
              ],
            ),
          ),
        ),
        (false, final items?, _) when items.isEmpty => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const Key('settlementListEmpty'),
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 180),
              Icon(Icons.receipt_long_outlined, size: 56),
              SizedBox(height: 12),
              Center(child: Text('정산 내역이 없습니다.')),
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
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListTile(
        key: Key('settlement-${item.bookingNumber}'),
        onTap: onTap,
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(item.bookingNumber),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatSettlementMoney(
                item.companyCommissionAmount ?? item.commissionAmount,
                item.companyCommissionCurrency ?? item.currency,
              ),
            ),
            if (item.dueAt != null) Text('마감: ${item.dueAt}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(status: item.commissionStatus),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: colors.outline),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SettlementStatus status;

  @override
  Widget build(BuildContext context) {
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
      label: Text(status.label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }
}
