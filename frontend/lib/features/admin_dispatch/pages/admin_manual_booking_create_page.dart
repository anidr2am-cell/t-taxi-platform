import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_coupon/services/admin_coupon_api_service.dart';
import '../../booking/models/location_option.dart';
import '../../booking/widgets/google_places_search_field.dart';
import '../../driver/widgets/driver_workflow_widgets.dart';
import '../services/admin_dispatch_api_service.dart';
import '../widgets/assign_driver_dialog.dart';
import 'admin_booking_detail_page.dart';

class AdminManualBookingCreatePage extends StatefulWidget {
  const AdminManualBookingCreatePage({
    super.key,
    this.dispatchApi,
    this.couponApi,
    this.editBookingNumber,
  });

  final AdminDispatchApiService? dispatchApi;
  final AdminCouponApiService? couponApi;
  final String? editBookingNumber;

  @override
  State<AdminManualBookingCreatePage> createState() =>
      _AdminManualBookingCreatePageState();
}

class _AdminManualBookingCreatePageState
    extends State<AdminManualBookingCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _payoutController = TextEditingController();
  final _customerChargeController = TextEditingController();
  final _guestNameController = TextEditingController();
  final _guestPhoneController = TextEditingController();
  final _guestEmailController = TextEditingController();
  final _memoController = TextEditingController();

  AdminDispatchApiService get _dispatchApi =>
      widget.dispatchApi ?? const AdminDispatchApiService();
  AdminCouponApiService get _couponApi =>
      widget.couponApi ?? const AdminCouponApiService();

  LocationOption? _origin;
  LocationOption? _destination;
  DateTime? _pickupAt;
  String _vehicleTypeCode = 'SEDAN';
  String _paymentCollection = 'DRIVER_COLLECTS';
  int _adults = 1;

  bool _searching = false;
  bool _submitting = false;
  String? _searchError;
  String? _submitError;
  String? _createdBookingNumber;
  String? _editingBookingNumber;
  bool _loadingEdit = false;
  String? _loadEditError;
  List<AdminCustomerSearchResult> _searchResults = const [];
  AdminCustomerSearchResult? _selectedCustomer;

  static const _vehicleTypes = [
    'SEDAN',
    'SUV',
    'VIP_SUV',
    'VAN',
    'VIP_VAN',
  ];

  @override
  void initState() {
    super.initState();
    final initialEdit = widget.editBookingNumber?.trim();
    if (initialEdit != null && initialEdit.isNotEmpty) {
      _editingBookingNumber = initialEdit;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadForEdit());
    }
  }

  bool get _isEditMode =>
      _editingBookingNumber != null && _editingBookingNumber!.isNotEmpty;

  String? get _activeBookingNumber =>
      _createdBookingNumber ?? _editingBookingNumber;

  LocationOption _routeLocation(Map<String, dynamic> side) {
    final address = side['address'] as String? ?? '';
    final placeId = side['placeId'] as String?;
    final name = side['name'] as String?;
    return LocationOption(
      id: placeId ?? address,
      displayName: (name != null && name.isNotEmpty) ? name : address,
      kind: LocationKind.place,
      placeId: placeId,
      name: name,
      address: address.isNotEmpty ? address : null,
      latitude: (side['lat'] as num?)?.toDouble(),
      longitude: (side['lng'] as num?)?.toDouble(),
    );
  }

  Future<void> _loadForEdit() async {
    final bookingNumber = _editingBookingNumber;
    if (bookingNumber == null) return;
    setState(() {
      _loadingEdit = true;
      _loadEditError = null;
    });
    try {
      final detail = await _dispatchApi.getBookingDetail(bookingNumber);
      if (!mounted) return;
      final manualActions =
          detail['manualCallActions'] as Map<String, dynamic>? ?? {};
      if (manualActions['canEdit'] != true) {
        setState(() {
          _loadingEdit = false;
          _loadEditError = context.l10n.t('admin_manual_booking_edit_not_allowed');
        });
        return;
      }

      final route = Map<String, dynamic>.from(detail['route'] as Map);
      final origin = Map<String, dynamic>.from(route['origin'] as Map);
      final destination = Map<String, dynamic>.from(route['destination'] as Map);
      final vehicle = Map<String, dynamic>.from(detail['vehicle'] as Map);
      final passengers = Map<String, dynamic>.from(detail['passengers'] as Map);
      final pricing = Map<String, dynamic>.from(detail['pricing'] as Map);
      final customer = Map<String, dynamic>.from(detail['customer'] as Map);
      final items = pricing['chargeItems'] as List<dynamic>? ?? [];
      var payout = 0;
      for (final item in items) {
        if (item is Map && item['chargeType'] == 'OTHER') {
          payout = (item['amount'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      final pickupRaw = detail['scheduledPickupAt'] as String?;
      DateTime? pickupAt;
      if (pickupRaw != null && pickupRaw.isNotEmpty) {
        pickupAt = DateTime.tryParse(pickupRaw)?.toLocal();
      }
      final paymentMethod = pricing['paymentMethod'] as String? ?? 'PAY_DRIVER';
      final customerUserId = customer['customerUserId'] as int?;

      setState(() {
        _origin = _routeLocation(origin);
        _destination = _routeLocation(destination);
        _pickupAt = pickupAt;
        _vehicleTypeCode = vehicle['typeCode'] as String? ?? 'SEDAN';
        _adults = (passengers['adults'] as num?)?.toInt().clamp(1, 8) ?? 1;
        _payoutController.text = payout > 0 ? '$payout' : '';
        _customerChargeController.clear();
        _paymentCollection =
            paymentMethod == 'ADMIN_COLLECTED' ? 'ADMIN_COLLECTED' : 'DRIVER_COLLECTS';
        _memoController.text = detail['specialRequests'] as String? ?? '';
        _selectedCustomer = null;
        _guestNameController.clear();
        _guestPhoneController.clear();
        _guestEmailController.clear();
        if (customerUserId != null) {
          _selectedCustomer = AdminCustomerSearchResult(
            id: customerUserId,
            name: customer['name'] as String?,
            phone: customer['phone'] as String?,
            email: customer['email'] as String?,
          );
        } else {
          _guestNameController.text = customer['name'] as String? ?? '';
          _guestPhoneController.text = customer['phone'] as String? ?? '';
          _guestEmailController.text = customer['email'] as String? ?? '';
        }
        _loadingEdit = false;
        _createdBookingNumber = null;
      });
    } on AdminDispatchApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingEdit = false;
        _loadEditError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingEdit = false;
        _loadEditError = context.l10n.t('ui_load_failed');
      });
    }
  }

  Future<void> _openDetail() async {
    final bookingNumber = _activeBookingNumber;
    if (bookingNumber == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _dispatchApi,
          onChanged: () {},
        ),
      ),
    );
  }

  Future<void> _assignDriver() async {
    final bookingNumber = _activeBookingNumber;
    if (bookingNumber == null) return;
    final result = await showAssignDriverDialog(
      context: context,
      api: _dispatchApi,
      isReassign: false,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await _dispatchApi.assignDriver(bookingNumber, result.driverId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('admin_manual_booking_assign_success'))),
      );
    } on AdminDispatchApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('ui_action_failed'))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelBooking() async {
    final bookingNumber = _activeBookingNumber;
    if (bookingNumber == null) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('admin_manual_booking_cancel')),
        content: Text(l10n.t('admin_manual_booking_cancel_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('driver_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('admin_manual_booking_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _dispatchApi.cancelManualBooking(bookingNumber);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('admin_manual_booking_cancel_success'))),
      );
      setState(() {
        _submitting = false;
        _createdBookingNumber = null;
        _editingBookingNumber = null;
      });
      if (widget.editBookingNumber != null && mounted) {
        Navigator.of(context).pop(true);
      }
    } on AdminDispatchApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('ui_action_failed'))),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _payoutController.dispose();
    _customerChargeController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _guestEmailController.dispose();
    _memoController.dispose();
    super.dispose();
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
      final results = await _couponApi.searchCustomers(query);
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

  Future<void> _pickPickupDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _pickupAt ?? now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickupAt ?? now.add(const Duration(hours: 2))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _pickupAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Map<String, dynamic> _locationPayload(LocationOption location) {
    return {
      'address': location.address ?? location.displayName,
      if (location.placeId != null) 'placeId': location.placeId,
      if (location.latitude != null) 'lat': location.latitude,
      if (location.longitude != null) 'lng': location.longitude,
      if (location.name != null) 'name': location.name,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_origin == null || _destination == null || _pickupAt == null) {
      setState(() => _submitError = context.l10n.t('admin_manual_booking_validation_required'));
      return;
    }
    if (_selectedCustomer == null &&
        (_guestNameController.text.trim().isEmpty ||
            _guestPhoneController.text.trim().isEmpty)) {
      setState(() => _submitError = context.l10n.t('admin_manual_booking_validation_customer'));
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
      _createdBookingNumber = null;
    });

    try {
      final customerCharge = int.tryParse(_customerChargeController.text.trim());
      final payload = {
        'origin': _locationPayload(_origin!),
        'destination': _locationPayload(_destination!),
        'scheduledPickupAt': _pickupAt!.toUtc().toIso8601String(),
        'vehicleTypeCode': _vehicleTypeCode,
        'payoutAmount': int.parse(_payoutController.text.trim()),
        'customerChargeAmount': customerCharge,
        'paymentCollection': _paymentCollection,
        'customer': _selectedCustomer != null
            ? {'customerUserId': _selectedCustomer!.id}
            : {
                'name': _guestNameController.text.trim(),
                'phone': _guestPhoneController.text.trim(),
                if (_guestEmailController.text.trim().isNotEmpty)
                  'email': _guestEmailController.text.trim(),
              },
        'memo': _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
        'passengers': {'adults': _adults, 'children': 0, 'infants': 0},
      };

      final Map<String, dynamic> result;
      if (_isEditMode) {
        result = await _dispatchApi.updateManualBooking(
          _editingBookingNumber!,
          origin: payload['origin'] as Map<String, dynamic>,
          destination: payload['destination'] as Map<String, dynamic>,
          scheduledPickupAt: payload['scheduledPickupAt'] as String,
          vehicleTypeCode: payload['vehicleTypeCode'] as String,
          payoutAmount: payload['payoutAmount'] as int,
          customerChargeAmount: payload['customerChargeAmount'] as int?,
          paymentCollection: payload['paymentCollection'] as String,
          customer: payload['customer'] as Map<String, dynamic>,
          memo: payload['memo'] as String?,
          passengers: payload['passengers'] as Map<String, dynamic>,
        );
      } else {
        result = await _dispatchApi.createManualBooking(
          origin: payload['origin'] as Map<String, dynamic>,
          destination: payload['destination'] as Map<String, dynamic>,
          scheduledPickupAt: payload['scheduledPickupAt'] as String,
          vehicleTypeCode: payload['vehicleTypeCode'] as String,
          payoutAmount: payload['payoutAmount'] as int,
          customerChargeAmount: payload['customerChargeAmount'] as int?,
          paymentCollection: payload['paymentCollection'] as String,
          customer: payload['customer'] as Map<String, dynamic>,
          memo: payload['memo'] as String?,
          passengers: payload['passengers'] as Map<String, dynamic>,
        );
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        final bookingNumber =
            result['bookingNumber'] as String? ?? _editingBookingNumber;
        _createdBookingNumber = bookingNumber;
        if (_isEditMode && widget.editBookingNumber != null) {
          Navigator.of(context).pop(true);
        }
      });
      if (_isEditMode && widget.editBookingNumber == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('admin_manual_booking_update_success'))),
        );
      }
    } on AdminDispatchApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = context.l10n.t('admin_manual_booking_failed');
      });
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
    final languageCode = l10n.languageCode;

    if (_loadingEdit) {
      return AppUi.centeredContent(
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadEditError != null) {
      return AppUi.centeredContent(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_loadEditError!, style: const TextStyle(color: AppTokens.error)),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton(
              onPressed: _loadForEdit,
              child: Text(l10n.t('ui_retry')),
            ),
          ],
        ),
      );
    }

    return AppUi.centeredContent(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: AppUi.pagePadding(context),
          children: [
              AppUi.sectionHeader(
                context,
                title: _isEditMode
                    ? l10n.t('admin_manual_booking_edit_title')
                    : l10n.t('admin_manual_booking_title'),
              ),
              if (_createdBookingNumber != null && !_isEditMode) ...[
                AppUi.surfaceCard(
                  backgroundColor: AppTokens.successLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.t('admin_manual_booking_success'),
                        style: const TextStyle(
                          color: AppTokens.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      SelectableText(
                        _createdBookingNumber!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _submitting ? null : _openDetail,
                            icon: const Icon(Icons.open_in_new),
                            label: Text(l10n.t('admin_manual_booking_view_detail')),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _submitting ? null : _assignDriver,
                            icon: const Icon(Icons.person_add_alt),
                            label: Text(l10n.t('admin_manual_booking_assign_driver')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => setState(
                                    () => _editingBookingNumber = _createdBookingNumber,
                                  ),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(l10n.t('admin_manual_booking_edit')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _submitting ? null : _cancelBooking,
                            icon: const Icon(Icons.cancel_outlined),
                            label: Text(l10n.t('admin_manual_booking_cancel')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],
              if (_isEditMode && widget.editBookingNumber != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _cancelBooking,
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(l10n.t('admin_manual_booking_cancel')),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              AppUi.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GooglePlacesSearchField(
                      label: l10n.t('admin_manual_booking_origin'),
                      languageCode: languageCode,
                      selected: _origin,
                      onSelected: (value) => setState(() => _origin = value),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    GooglePlacesSearchField(
                      label: l10n.t('admin_manual_booking_destination'),
                      languageCode: languageCode,
                      selected: _destination,
                      onSelected: (value) => setState(() => _destination = value),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.t('admin_manual_booking_pickup_datetime')),
                      subtitle: Text(
                        _pickupAt == null
                            ? l10n.t('admin_manual_booking_pickup_datetime_hint')
                            : _pickupAt!.toLocal().toString(),
                      ),
                      trailing: const Icon(Icons.event),
                      onTap: _pickPickupDateTime,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    DropdownButtonFormField<String>(
                      value: _vehicleTypeCode,
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_vehicle_type'),
                      ),
                      items: _vehicleTypes
                          .map(
                            (code) => DropdownMenuItem(
                              value: code,
                              child: Text(code),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) setState(() => _vehicleTypeCode = value);
                      },
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    DropdownButtonFormField<int>(
                      value: _adults,
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_passengers'),
                      ),
                      items: List.generate(
                        8,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('${index + 1}'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) setState(() => _adults = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('adminManualBookingPayoutAmount'),
                      controller: _payoutController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_payout_amount'),
                      ),
                      validator: (value) {
                        final amount = int.tryParse(value?.trim() ?? '');
                        if (amount == null || amount <= 0) return l10n.t('admin_manual_booking_validation_required');
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    TextFormField(
                      controller: _customerChargeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_customer_charge_amount'),
                        helperText: l10n.t('admin_manual_booking_customer_charge_hint'),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    Text(
                      l10n.t('admin_manual_booking_payment_method'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioListTile<String>(
                      value: 'ADMIN_COLLECTED',
                      groupValue: _paymentCollection,
                      onChanged: (value) {
                        if (value != null) setState(() => _paymentCollection = value);
                      },
                      title: Text(l10n.t('admin_manual_booking_payment_admin_collected')),
                    ),
                    RadioListTile<String>(
                      value: 'DRIVER_COLLECTS',
                      groupValue: _paymentCollection,
                      onChanged: (value) {
                        if (value != null) setState(() => _paymentCollection = value);
                      },
                      title: Text(l10n.t('admin_manual_booking_payment_driver_collects')),
                    ),
                    if (_paymentCollection == 'ADMIN_COLLECTED') ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      DriverAdminManualCallNotice(
                        isAdminManualCall: true,
                        requiresBankAccountConfirmation: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                        child: Text(
                          l10n.t('admin_manual_booking_preview_notice'),
                          style: const TextStyle(color: AppTokens.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.t('admin_manual_booking_customer_section'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
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
                    if (_searchError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                        child: Text(
                          _searchError!,
                          style: const TextStyle(color: AppTokens.error),
                        ),
                      ),
                    if (_searchResults.isNotEmpty)
                      ..._searchResults.map((customer) {
                        final selected = _selectedCustomer?.id == customer.id;
                        final label = _customerLabel(customer);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(label.isEmpty ? '#${customer.id}' : label),
                          trailing: selected
                              ? const Icon(Icons.check_circle, color: AppTokens.primary)
                              : null,
                          onTap: () => setState(() {
                            _selectedCustomer = customer;
                            _guestNameController.clear();
                            _guestPhoneController.clear();
                            _guestEmailController.clear();
                          }),
                        );
                      }),
                    if (_selectedCustomer == null) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      TextFormField(
                        key: const Key('adminManualBookingGuestName'),
                        controller: _guestNameController,
                        decoration: InputDecoration(
                          labelText: l10n.t('admin_manual_booking_guest_name'),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      TextFormField(
                        key: const Key('adminManualBookingGuestPhone'),
                        controller: _guestPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: l10n.t('admin_manual_booking_guest_phone'),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      TextFormField(
                        controller: _guestEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: l10n.t('admin_manual_booking_guest_email'),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        '${l10n.t('admin_coupon_selected_customer')}: ${_customerLabel(_selectedCustomer!)}',
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedCustomer = null),
                        child: Text(l10n.t('admin_manual_booking_clear_customer')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                child: TextFormField(
                  controller: _memoController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_manual_booking_memo'),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  _submitError!,
                  style: const TextStyle(color: AppTokens.error),
                ),
              ],
              const SizedBox(height: AppTokens.spaceLg),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('adminManualBookingSubmit'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_call),
                  label: Text(
                    _isEditMode
                        ? l10n.t('admin_manual_booking_update_submit')
                        : l10n.t('admin_manual_booking_submit'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
