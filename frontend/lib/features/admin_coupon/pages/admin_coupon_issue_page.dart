import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_coupon_api_service.dart';

class AdminCouponIssuePage extends StatefulWidget {
  const AdminCouponIssuePage({
    super.key,
    this.apiService,
    this.pickImageFile,
  });

  final AdminCouponApiService? apiService;
  final Future<PlatformFile?> Function()? pickImageFile;

  @override
  State<AdminCouponIssuePage> createState() => _AdminCouponIssuePageState();
}

class _AdminCouponIssuePageState extends State<AdminCouponIssuePage> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _templateTitleController = TextEditingController();
  final _templateAmountController = TextEditingController();

  AdminCouponApiService get _api =>
      widget.apiService ?? const AdminCouponApiService();

  bool _searching = false;
  bool _issuing = false;
  bool _loadingRecent = true;
  bool _loadingRecentCustomers = true;
  bool _loadingTemplates = true;
  bool _creatingTemplate = false;
  String? _searchError;
  String? _issueError;
  String? _templateError;
  List<AdminCustomerSearchResult> _searchResults = const [];
  List<AdminCustomerSearchResult> _recentCustomers = const [];
  List<AdminIssuedCouponItem> _recentCoupons = const [];
  List<AdminCouponTemplateItem> _templates = const [];
  AdminCustomerSearchResult? _selectedCustomer;
  AdminCouponTemplateItem? _selectedTemplate;
  final Map<int, Uint8List> _templateImageCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecentCoupons();
      _loadRecentCustomers();
      _loadTemplates();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    _templateTitleController.dispose();
    _templateAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCoupons() async {
    setState(() => _loadingRecent = true);
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

  Future<void> _loadRecentCustomers() async {
    setState(() => _loadingRecentCustomers = true);
    try {
      final customers = await _api.listRecentCustomers(limit: 20);
      if (!mounted) return;
      setState(() {
        _recentCustomers = customers;
        _loadingRecentCustomers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecentCustomers = false);
    }
  }

  Future<void> _loadTemplates() async {
    setState(() => _loadingTemplates = true);
    try {
      final templates = await _api.listTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loadingTemplates = false;
      });
      await _prefetchTemplateImages(templates);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTemplates = false);
    }
  }

  Future<void> _prefetchTemplateImages(List<AdminCouponTemplateItem> templates) async {
    for (final template in templates) {
      if (_templateImageCache.containsKey(template.id)) continue;
      try {
        final bytes = await _api.fetchImageBytes(template.imageUrl);
        if (!mounted) return;
        setState(() => _templateImageCache[template.id] = bytes);
      } catch (_) {
        // ignore individual image failures
      }
    }
  }

  void _selectCustomer(AdminCustomerSearchResult customer) {
    setState(() => _selectedCustomer = customer);
  }

  void _selectTemplate(AdminCouponTemplateItem? template) {
    setState(() {
      _selectedTemplate = template;
      if (template != null) {
        _titleController.text = template.title;
        _amountController.text = '${template.discountAmount}';
      } else {
        _titleController.clear();
        _amountController.clear();
      }
    });
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
    final template = _selectedTemplate;
    final title = _titleController.text.trim();
    final amount = int.tryParse(_amountController.text.trim());

    if (customer == null) return;
    if (template == null && (title.isEmpty || amount == null || amount <= 0)) {
      return;
    }

    setState(() {
      _issuing = true;
      _issueError = null;
    });

    try {
      await _api.issueCoupon(
        customerUserId: customer.id,
        templateId: template?.id,
        title: template == null ? title : null,
        discountAmount: template == null ? amount : null,
      );
      if (!mounted) return;
      if (template == null) {
        _titleController.clear();
        _amountController.clear();
      }
      setState(() {
        _issuing = false;
        _selectedCustomer = null;
        _selectedTemplate = null;
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

  Future<PlatformFile?> _pickImageFile() async {
    if (widget.pickImageFile != null) return widget.pickImageFile!();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    return picked?.files.single;
  }

  Future<void> _createTemplate() async {
    final title = _templateTitleController.text.trim();
    final amount = int.tryParse(_templateAmountController.text.trim());
    if (title.isEmpty || amount == null || amount <= 0) return;

    final file = await _pickImageFile();
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    setState(() {
      _creatingTemplate = true;
      _templateError = null;
    });

    try {
      await _api.createTemplate(
        title: title,
        discountAmount: amount,
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      _templateTitleController.clear();
      _templateAmountController.clear();
      setState(() => _creatingTemplate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_coupon_template_create_success'))),
      );
      await _loadTemplates();
    } on AdminCouponApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _creatingTemplate = false;
        _templateError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creatingTemplate = false;
        _templateError = context.l10n.t('admin_coupon_template_create_failed');
      });
    }
  }

  Future<void> _toggleTemplateActive(AdminCouponTemplateItem template) async {
    try {
      await _api.setTemplateActive(
        templateId: template.id,
        isActive: !template.isActive,
      );
      if (!mounted) return;
      await _loadTemplates();
    } on AdminCouponApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  String _customerLabel(AdminCustomerSearchResult customer) {
    return [
      customer.name,
      customer.phone,
      customer.email,
    ].where((part) => part != null && part.trim().isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final templateSelected = _selectedTemplate != null;
    final canIssue = _selectedCustomer != null &&
        (templateSelected ||
            (_titleController.text.trim().isNotEmpty &&
                int.tryParse(_amountController.text.trim()) != null &&
                int.parse(_amountController.text.trim()) > 0));

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
                Text(
                  l10n.t('admin_coupon_recent_customers_title'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppTokens.spaceSm),
                if (_loadingRecentCustomers)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTokens.spaceMd),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_recentCustomers.isEmpty)
                  Text(l10n.t('admin_coupon_recent_customers_empty'))
                else
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: _recentCustomers.map((customer) {
                      final selected = _selectedCustomer?.id == customer.id;
                      final label = _customerLabel(customer);
                      return FilterChip(
                        label: Text(label.isEmpty ? '#${customer.id}' : label),
                        selected: selected,
                        onSelected: (_) => _selectCustomer(customer),
                      );
                    }).toList(growable: false),
                  ),
                const SizedBox(height: AppTokens.spaceLg),
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
                    final label = _customerLabel(customer);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(label.isEmpty ? '#${customer.id}' : label),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: AppTokens.primary)
                          : null,
                      onTap: () => _selectCustomer(customer),
                    );
                  }),
                ] else if (!_searching &&
                    _searchController.text.trim().isNotEmpty &&
                    _searchError == null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(l10n.t('admin_coupon_search_empty')),
                ],
                if (_selectedCustomer != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    '${l10n.t('admin_coupon_selected_customer')}: ${_customerLabel(_selectedCustomer!).isEmpty ? '#${_selectedCustomer!.id}' : _customerLabel(_selectedCustomer!)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                Text(
                  l10n.t('admin_coupon_template_picker_title'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppTokens.spaceSm),
                if (_loadingTemplates)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTokens.spaceMd),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.t('admin_coupon_template_manual')),
                        selected: _selectedTemplate == null,
                        onSelected: (_) => _selectTemplate(null),
                      ),
                      ..._templates.where((t) => t.isActive).map((template) {
                        final selected = _selectedTemplate?.id == template.id;
                        final bytes = _templateImageCache[template.id];
                        return InkWell(
                          onTap: () => _selectTemplate(template),
                          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                          child: Container(
                            width: 120,
                            padding: const EdgeInsets.all(AppTokens.spaceSm),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                              border: Border.all(
                                color: selected
                                    ? AppTokens.primary
                                    : AppTokens.border,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                if (bytes != null)
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(AppTokens.radiusSm),
                                    child: Image.memory(
                                      bytes,
                                      height: 64,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Container(
                                    height: 64,
                                    alignment: Alignment.center,
                                    color: AppTokens.surfaceMuted,
                                    child: const Icon(Icons.image_outlined),
                                  ),
                                const SizedBox(height: AppTokens.spaceXs),
                                Text(
                                  template.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  '${template.discountAmount} ${l10n.t('thb')}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                TextField(
                  controller: _titleController,
                  readOnly: templateSelected,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_coupon_title_label'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _amountController,
                  readOnly: templateSelected,
                  keyboardType: TextInputType.number,
                  inputFormatters: templateSelected
                      ? null
                      : [FilteringTextInputFormatter.digitsOnly],
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
                  onPressed: _issuing || !canIssue ? null : _issueCoupon,
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
            title: l10n.t('admin_coupon_template_manage_title'),
          ),
          AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _templateTitleController,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_coupon_title_label'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _templateAmountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_coupon_amount_label'),
                    suffixText: l10n.t('thb'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                OutlinedButton.icon(
                  onPressed: _creatingTemplate ? null : _createTemplate,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l10n.t('admin_coupon_template_create_button')),
                ),
                if (_templateError != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    _templateError!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ],
                if (_templates.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spaceLg),
                  ..._templates.map((template) {
                    final bytes = _templateImageCache[template.id];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: bytes != null
                          ? ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusSm),
                              child: Image.memory(bytes, width: 48, height: 48, fit: BoxFit.cover),
                            )
                          : const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.image_outlined),
                            ),
                      title: Text(template.title),
                      subtitle: Text(
                        '${template.discountAmount} ${l10n.t('thb')} · ${template.isActive ? l10n.t('admin_coupon_template_active') : l10n.t('admin_coupon_template_inactive')}',
                      ),
                      trailing: Switch(
                        value: template.isActive,
                        onChanged: (_) => _toggleTemplateActive(template),
                      ),
                    );
                  }),
                ],
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
              final customerLabel = _customerLabel(coupon.customer);
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
