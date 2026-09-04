import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import '../services/mileage_api_service.dart';
import '../utils/auth_provider_display.dart';

class MileageHistoryPage extends StatefulWidget {
  const MileageHistoryPage({super.key, this.mileageApiService});

  final MileageApiService? mileageApiService;

  @override
  State<MileageHistoryPage> createState() => _MileageHistoryPageState();
}

class _MileageHistoryPageState extends State<MileageHistoryPage> {
  final List<MileageTransactionItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _errorMessage;
  int _page = 1;
  int _total = 0;
  static const _limit = 20;

  MileageApiService _resolveApiService() {
    return widget.mileageApiService ??
        MileageApiService(
          session: AuthScope.of(context).customerSession,
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTransactions(reset: true);
    });
  }

  Future<void> _loadTransactions({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _errorMessage = null;
        _page = 1;
        _items.clear();
      });
    } else {
      if (_loadingMore || _items.length >= _total) return;
      setState(() => _loadingMore = true);
    }

    try {
      final result = await _resolveApiService().getTransactions(
        page: reset ? 1 : _page + 1,
        limit: _limit,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
          _page = result.page;
        } else {
          _items.addAll(result.items);
          _page = result.page;
        }
        _total = result.total;
        _loading = false;
        _loadingMore = false;
      });
    } on MileageApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _errorMessage = context.l10n.t('account_mileage_history_load_failed');
      });
    }
  }

  String _typeLabel(AppLocalizations l10n, String type) {
    switch (type.toUpperCase()) {
      case 'ACCRUE':
        return l10n.t('account_mileage_type_accrue');
      case 'REVERSAL':
        return l10n.t('account_mileage_type_reversal');
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      key: const Key('mileage_history_page'),
      appBar: AppBar(title: Text(l10n.t('account_mileage_history_title'))),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: AppUi.pagePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTokens.error),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.primaryButton(
                label: l10n.t('account_mileage_retry'),
                onPressed: () => _loadTransactions(reset: true),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: AppUi.pagePadding(context),
          child: Text(
            l10n.t('account_mileage_history_empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadTransactions(reset: true),
      child: ListView.separated(
        padding: AppUi.pagePadding(context),
        itemCount: _items.length + (_items.length < _total ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppTokens.spaceSm),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (!_loadingMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadTransactions(reset: false);
              });
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.spaceMd),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final item = _items[index];
          final signedAmount = item.amount >= 0
              ? '+${AuthProviderDisplay.formatPoints(item.amount)}P'
              : '${AuthProviderDisplay.formatPoints(item.amount)}P';

          return AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.bookingNumber,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      signedAmount,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: item.amount >= 0
                            ? AppTokens.primary
                            : AppTokens.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_typeLabel(l10n, item.type)} · ${item.date ?? '-'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
