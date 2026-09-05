import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_coupon_api_service.dart';

class AdminCouponIssuePage extends StatefulWidget {
  const AdminCouponIssuePage({super.key, this.apiService});

  final AdminCouponApiService? apiService;

  @override
  State<AdminCouponIssuePage> createState() => _AdminCouponIssuePageState();
}

class _AdminCouponIssuePageState extends State<AdminCouponIssuePage> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  AdminCouponApiService get _api =>
      widget.apiService ?? const AdminCouponApiService();

  bool _searching = false;
  bool _issuing = false;
  bool _loadingRecent = true;
  String? _searchError;
  String? _issueError;
  List<AdminCustomerSearchResult> _searchResults = const [];
  AdminCustomerSearchResult? _selectedCustomer;
  List<AdminIssuedCouponItem> _recentCoupons = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecentCoupons();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCoupons() async {
    setState(() {
      _loadingRecent = true;
    });
    try {
      final coupons = await _api.listRecentCoupons(limit: 20);
      if (!mounted) return;
      setState(() {
        _recentCoupons = coupons;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecent = false);
    }
  }

  Future<void> _searchCustomers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = const [];
      _selectedCustomer = null;
    });

    try {
      final results = await _api.searchCustomers(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } on AdminCouponApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = context.l10n.t('ui_load_failed');
      });
    }
  }

  Future<void> _issueCoupon() async {
    final customer = _selectedCustomer;
    final title = _titleController.text.trim();
    final amount = int.tryParse(_amountController.text.trim());
    if (customer == null || title.isEmpty || amount == null || amount <= 0) {
      return;
    }

    setState(() {
      _issuing = true;
      _issueError = null;
    });

    try {
      await _api.issueCoupon(
        customerUserId: customer.id,
        title: title,
        discountAmount: amount,
      );
      if (!mounted) return;
      _titleController.clear();
      _amountController.clear();
      setState(() {
        _issuing = false;
        _selectedCustomer = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_coupon_issue_success'))),
      );
      await _loadRecentCoupons();
    } on AdminCouponApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _issuing = false;
        _issueError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _issuing = false;
        _issueError = context.l10n.t('admin_coupon_issue_failed');
      });
    }
  }

  Future<void> _cancelCoupon(AdminIssuedCouponItem coupon) async {
    if (coupon.status != 'AVAILABLE') return;
    try {
      await _api.cancelCoupon(coupon.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_coupon_cancel_success'))),
      );
      await _loadRecentCoupons();
    } on AdminCouponApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppUi.centeredContent(
      child: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('admin_coupon_issue_title'),
          ),
          AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_coupon_search_hint'),
                    suffixIcon: IconButton(
                      onPressed: _searching ? null : _searchCustomers,
                      icon: _searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _searchCustomers(),
                ),
                if (_searchError != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    _searchError!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ],
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(
                    l10n.t('admin_coupon_select_customer'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  ..._searchResults.map((customer) {
                    final selected = _selectedCustomer?.id == customer.id;
                    final label = [
                      customer.name,
                      customer.phone,
                      customer.email,
                    ].where((part) => part != null && part.trim().isNotEmpty).join(' · ');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(label.isEmpty ? '#${customer.id}' : label),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: AppTokens.primary)
                          : null,
                      onTap: () => setState(() => _selectedCustomer = customer),
                    );
                  }),
                ] else if (!_searching &&
                    _searchController.text.trim().isNotEmpty &&
                    _searchError == null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(l10n.t('admin_coupon_search_empty')),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_coupon_title_label'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_coupon_amount_label'),
                    suffixText: l10n.t('thb'),
                  ),
                ),
                if (_issueError != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    _issueError!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                FilledButton(
                  onPressed: _issuing || _selectedCustomer == null
                      ? null
                      : _issueCoupon,
                  child: _issuing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.t('admin_coupon_issue_button')),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.sectionHeader(
            context,
            title: l10n.t('admin_coupon_recent_title'),
          ),
          if (_loadingRecent)
            const Padding(
              padding: EdgeInsets.all(AppTokens.spaceLg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recentCoupons.isEmpty)
            AppUi.surfaceCard(child: Text(l10n.t('admin_coupon_recent_empty')))
          else
            ..._recentCoupons.map((coupon) {
              final customerLabel = [
                coupon.customer.name,
                coupon.customer.phone,
                coupon.customer.email,
              ].where((part) => part != null && part.trim().isNotEmpty).join(' · ');
              return Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                child: AppUi.surfaceCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              coupon.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${coupon.discountAmount} ${l10n.t('thb')} · ${coupon.status == 'AVAILABLE' ? l10n.t('admin_coupon_status_available') : l10n.t('admin_coupon_status_used')}',
                            ),
                            if (customerLabel.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(customerLabel),
                            ],
                            if (coupon.issuedAt != null) ...[
                              const SizedBox(height: 4),
                              Text(coupon.issuedAt!),
                            ],
                          ],
                        ),
                      ),
                      if (coupon.status == 'AVAILABLE')
                        TextButton(
                          onPressed: () => _cancelCoupon(coupon),
                          child: Text(l10n.t('admin_coupon_cancel')),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
