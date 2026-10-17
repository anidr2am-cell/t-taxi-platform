import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../booking/widgets/golf_trip_fields.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../admin_coupon/services/admin_coupon_api_service.dart';
import '../../booking/models/flight_lookup_models.dart';
import '../../booking/services/flight_lookup_api_service.dart';
import '../../booking/services/booking_api_service.dart';
import '../../booking/services/vehicle_type_api_service.dart';
import '../../booking/models/location_option.dart';
import '../../booking/models/service_type_option.dart';
import '../../../services/api_service.dart';
import '../../booking/utils/pickup_time_format.dart';
import '../../booking/utils/pricing_location_params.dart';
import '../../booking/utils/booking_contact_preference.dart';
import '../../booking/utils/thailand_pickup_datetime.dart';
import '../../booking/widgets/google_places_search_field.dart';
import '../../booking/widgets/pickup_time_picker_sheet.dart';
import '../widgets/admin_manual_flight_section.dart';
import '../../driver/widgets/driver_workflow_widgets.dart';
import '../services/admin_dispatch_api_service.dart';
import '../widgets/assign_driver_dialog.dart';
import 'admin_booking_detail_page.dart';

Map<String, dynamic> _bookingDetailMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

int? _bookingDetailInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _bookingDetailString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

double? _bookingDetailDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool _bookingDetailBool(dynamic value) {
  if (value == true || value == 1 || value == '1') return true;
  if (value is String && value.toLowerCase() == 'true') return true;
  return false;
}

@visibleForTesting
String normalizeAdminManualPhone(String dialCode, String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('+')) {
    final international = '+${trimmed.substring(1).replaceAll(RegExp(r'\D'), '')}';
    return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(international)
        ? international
        : '';
  }
  return BookingContactPreference.normalizeInternationalPhone(
    dialCode,
    trimmed,
  );
}

List<dynamic> _bookingDetailList(dynamic value) {
  if (value is List) return value;
  return const [];
}

void _applySpecialLuggageFromDetail(
  Map<String, dynamic> luggage, {
  required void Function(int count) setCount,
  required void Function(String text) setText,
}) {
  final items = _bookingDetailString(luggage['specialItems']);
  if (items != null && items.isNotEmpty) {
    final asCount = int.tryParse(items.trim());
    if (asCount != null) {
      setCount(asCount.clamp(0, 20));
      setText('');
    } else {
      setCount(0);
      setText(items);
    }
    return;
  }
  final explicit = _bookingDetailInt(luggage['specialLuggageCount']);
  setCount((explicit ?? 0).clamp(0, 20));
  setText('');
}

class AdminManualBookingCreatePage extends StatefulWidget {
  const AdminManualBookingCreatePage({
    super.key,
    this.dispatchApi,
    this.couponApi,
    this.flightLookupApi,
    this.bookingApi,
    this.vehicleTypeApi,
    this.editBookingNumber,
    this.initialOrigin,
    this.initialDestination,
    this.initialServiceTypeCode,
    this.initialPickupAt,
  });

  final AdminDispatchApiService? dispatchApi;
  final AdminCouponApiService? couponApi;
  final FlightLookupApiService? flightLookupApi;
  final BookingApiService? bookingApi;
  final VehicleTypeApiService? vehicleTypeApi;
  final String? editBookingNumber;
  @visibleForTesting
  final LocationOption? initialOrigin;
  @visibleForTesting
  final LocationOption? initialDestination;
  @visibleForTesting
  final String? initialServiceTypeCode;
  @visibleForTesting
  final DateTime? initialPickupAt;

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
  final _messengerIdController = TextEditingController();
  final _memoController = TextEditingController();
  final _nameSignTextController = TextEditingController();
  final _specialItemsTextController = TextEditingController();

  AdminDispatchApiService get _dispatchApi =>
      widget.dispatchApi ?? const AdminDispatchApiService();
  AdminCouponApiService get _couponApi =>
      widget.couponApi ?? const AdminCouponApiService();
  BookingApiService get _bookingApi => widget.bookingApi ?? BookingApiService();
  VehicleTypeApiService get _vehicleTypeApi =>
      widget.vehicleTypeApi ?? VehicleTypeApiService();

  LocationOption? _origin;
  LocationOption? _destination;
  DateTime? _pickupAt;
  String _vehicleTypeCode = 'SEDAN';
  String _serviceTypeCode = 'CITY_TRANSFER';
  String _paymentCollection = 'DRIVER_COLLECTS';
  int _adults = 1;
  int _children = 0;
  int _infants = 0;
  int _luggage20 = 0;
  int _luggage24 = 0;
  int _golfBags = 0;
  int _specialLuggageCount = 0;
  bool _nameSign = false;
  bool _preferFemaleDriver = false;
  String _flightNumber = '';
  String? _originAirportIata;
  String? _flightScheduledArrivalAt;
  String? _flightEstimatedArrivalAt;
  String? _golfRegion;
  int? _golfCourseId;
  bool _driverIncluded = false;
  String _dispatchMode = 'OPEN';
  int? _selectedDirectDriverId;
  String? _messengerType;
  String _guestPhoneDialCode = '+66';
  List<Map<String, dynamic>> _directDrivers = const [];
  bool _loadingDirectDrivers = false;
  List<String> _golfRegions = const [];
  List<Map<String, dynamic>> _golfCourses = const [];
  List<String> _activeVehicleTypes = const ['SEDAN', 'SUV', 'VIP_SUV', 'VAN'];
  bool _loadingStandardPrice = false;
  bool _applyingStandardPrice = false;
  bool _customerChargeManuallyEdited = false;
  bool _standardPriceStale = false;
  String? _standardPriceError;
  int _pricingRequestGeneration = 0;

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

  static const _serviceTypeCodes = [
    'CITY_TRANSFER',
    'AIRPORT_PICKUP',
    'AIRPORT_DROPOFF',
    'GOLF_TRANSFER',
  ];

  Map<String, dynamic> get _luggagePayload {
    final payload = <String, dynamic>{
      'carriers20Inch': _luggage20,
      'carriers24InchPlus': _luggage24,
      'golfBags': _golfBags,
    };
    final specialText = _specialItemsTextController.text.trim();
    if (specialText.isNotEmpty) {
      payload['specialItems'] = specialText;
    } else if (_specialLuggageCount > 0) {
      payload['specialLuggageCount'] = _specialLuggageCount;
    } else {
      payload['specialItems'] = '';
    }
    return payload;
  }

  String? get _pickupDateYmdForFlight {
    if (_pickupAt == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_pickupAt!.year}-${two(_pickupAt!.month)}-${two(_pickupAt!.day)}';
  }

  Map<String, dynamic>? get _transferPayload {
    if (_showsGolfSection) {
      return {
        if (_golfRegion != null && _golfRegion!.isNotEmpty)
          'golfRegion': _golfRegion,
        if (_golfCourseId != null) 'golfCourseId': _golfCourseId,
        'driverIncluded': _driverIncluded,
      };
    }
    if (!_showsFlightSection) return null;
    final normalized = _flightNumber.trim().toUpperCase();
    return {
      if (_originAirportIata != null && _originAirportIata!.isNotEmpty)
        'airportIata': _originAirportIata,
      'flightNumber': normalized.isEmpty ? null : normalized,
      if (_flightScheduledArrivalAt != null && _flightScheduledArrivalAt!.isNotEmpty)
        'flightScheduledArrivalAt': _flightScheduledArrivalAt,
      if (_flightEstimatedArrivalAt != null && _flightEstimatedArrivalAt!.isNotEmpty)
        'flightEstimatedArrivalAt': _flightEstimatedArrivalAt,
    };
  }

  String _formatPickupDisplay(AppLocalizations l10n) {
    if (_pickupAt == null) {
      return l10n.t('admin_manual_booking_pickup_datetime_hint');
    }
    final value = _pickupAt!;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${value.year}-${two(value.month)}-${two(value.day)}';
    final time = PickupTimeFormat.formatDisplay(
      hour24: value.hour,
      minute: value.minute,
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
    return '$date · $time';
  }

  @override
  void initState() {
    super.initState();
    _origin = widget.initialOrigin;
    _destination = widget.initialDestination;
    _serviceTypeCode = widget.initialServiceTypeCode ?? _serviceTypeCode;
    _pickupAt = widget.initialPickupAt;
    _customerChargeController.addListener(_onCustomerChargeEdited);
    final initialEdit = widget.editBookingNumber?.trim();
    if (initialEdit != null && initialEdit.isNotEmpty) {
      _editingBookingNumber = initialEdit;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadForEdit());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGolfRegions());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDirectDrivers());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVehicleTypes());
  }

  void _onCustomerChargeEdited() {
    if (_applyingStandardPrice || _isEditMode) return;
    _customerChargeManuallyEdited = true;
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final values = await _vehicleTypeApi.listActiveCodes();
      final supportedValues = values.where((code) => code != 'VIP_VAN').toList();
      if (!mounted) return;
      setState(() {
        if (supportedValues.isNotEmpty) {
          _activeVehicleTypes = supportedValues;
        }
        if (!_activeVehicleTypes.contains(_vehicleTypeCode)) {
          _vehicleTypeCode = _activeVehicleTypes.first;
          _selectedDirectDriverId = null;
        }
      });
      _onQuoteInputsChanged();
    } catch (_) {
      // Keep the safe built-in list when the active-type endpoint is unavailable.
      _onQuoteInputsChanged();
    }
  }

  bool _vehicleCodeCompatible(String? driverCode) {
    if (driverCode == null || driverCode.isEmpty) return false;
    if (driverCode == _vehicleTypeCode) return true;
    const tiers = {'SEDAN': 1, 'SUV': 2, 'VAN': 3};
    final requested = tiers[_vehicleTypeCode];
    final driver = tiers[driverCode];
    return requested != null && driver != null && driver >= requested;
  }

  List<Map<String, dynamic>> get _eligibleDirectDrivers => _directDrivers
      .where((driver) {
        final archive = _bookingDetailMap(driver['archive']);
        final vehicle = _bookingDetailMap(driver['primaryVehicle']);
        final vehicleCodes = _bookingDetailList(driver['vehicleTypeCodes'])
            .map((code) => code.toString())
            .toList(growable: false);
        return driver['activeState'] == 'ACTIVE'
            && driver['driverStatus'] != 'SUSPENDED'
            && driver['assignmentEligible'] == true
            && archive['isArchived'] != true
            && (vehicleCodes.any(_vehicleCodeCompatible)
                || _vehicleCodeCompatible(
                  _bookingDetailString(vehicle['vehicleTypeCode']),
                ));
      })
      .toList(growable: false);

  Future<void> _loadDirectDrivers() async {
    if (_isEditMode) return;
    setState(() => _loadingDirectDrivers = true);
    try {
      final rows = await _dispatchApi.listDrivers();
      if (!mounted) return;
      setState(() {
        _directDrivers = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        _loadingDirectDrivers = false;
        if (!_eligibleDirectDrivers.any(
          (driver) => _bookingDetailInt(driver['driverId']) == _selectedDirectDriverId,
        )) {
          _selectedDirectDriverId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDirectDrivers = false);
    }
  }

  Future<void> _loadGolfRegions() async {
    try {
      final regions = await ApiService().getGolfRegions();
      if (!mounted) return;
      setState(() => _golfRegions = regions);
    } catch (_) {}
  }

  Future<void> _loadGolfCourses(String region) async {
    try {
      final courses = await ApiService().getGolfCourses(region: region);
      if (!mounted) return;
      setState(() {
        _golfCourses = courses
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {}
  }

  void _applyFlightLookup(FlightSearchResult? result) {
    if (result == null) {
      _flightScheduledArrivalAt = null;
      _flightEstimatedArrivalAt = null;
      return;
    }
    _flightScheduledArrivalAt = result.arrival.scheduledAt;
    _flightEstimatedArrivalAt =
        result.arrival.estimatedAt ?? result.arrival.scheduledAt;
  }

  bool get _isEditMode =>
      _editingBookingNumber != null && _editingBookingNumber!.isNotEmpty;

  String? get _activeBookingNumber =>
      _createdBookingNumber ?? _editingBookingNumber;

  LocationOption _routeLocation(
    Map<String, dynamic> side, {
    required String fallbackId,
  }) {
    final address = _bookingDetailString(side['address']) ?? '';
    final placeId = _bookingDetailString(side['placeId']);
    final name = _bookingDetailString(side['name']);
    final displayName = (name != null && name.isNotEmpty) ? name : address;
    final id = (placeId != null && placeId.isNotEmpty)
        ? placeId
        : (address.isNotEmpty ? address : fallbackId);
    return LocationOption(
      id: id,
      displayName: displayName.isNotEmpty ? displayName : '—',
      kind: LocationKind.place,
      placeId: placeId,
      name: name,
      address: address.isNotEmpty ? address : null,
      latitude: _bookingDetailDouble(side['lat']),
      longitude: _bookingDetailDouble(side['lng']),
    );
  }

  List<String> get _vehicleTypeOptions {
    if (_activeVehicleTypes.contains(_vehicleTypeCode)) return _activeVehicleTypes;
    if (_vehicleTypeCode == 'VIP_VAN') return _activeVehicleTypes;
    return [..._activeVehicleTypes, _vehicleTypeCode];
  }

  bool get _showsFlightSection =>
      _serviceTypeCode == 'AIRPORT_PICKUP' ||
      _serviceTypeCode == 'AIRPORT_DROPOFF';

  Map<String,dynamic>? _golf;

  bool get _showsGolfSection => _serviceTypeCode == 'GOLF_TRANSFER';

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
      final manualActions = _bookingDetailMap(detail['manualCallActions']);
      if (!_bookingDetailBool(manualActions['canEdit'])) {
        setState(() {
          _loadingEdit = false;
          _loadEditError = context.l10n.t('admin_manual_booking_edit_not_allowed');
        });
        return;
      }

      final route = _bookingDetailMap(detail['route']);
      final origin = _bookingDetailMap(route['origin']);
      final destination = _bookingDetailMap(route['destination']);
      final vehicle = _bookingDetailMap(detail['vehicle']);
      final passengers = _bookingDetailMap(detail['passengers']);
      final luggage = _bookingDetailMap(detail['luggage']);
      final serviceType = _bookingDetailMap(detail['serviceType']);
      final pricing = _bookingDetailMap(detail['pricing']);
      final customer = _bookingDetailMap(detail['customer']);
      final items = _bookingDetailList(pricing['chargeItems']);
      final options = _bookingDetailMap(detail['options']);
      var payout = 0;
      for (final item in items) {
        if (item is Map) {
          final chargeType = _bookingDetailString(item['chargeType']);
          if (chargeType == 'OTHER') {
            payout = _bookingDetailInt(item['amount']) ?? 0;
            break;
          }
        }
      }
      final nameSign = options['nameSign'] == true
          || items.any(
            (item) =>
                item is Map && _bookingDetailString(item['chargeType']) == 'NAME_SIGN',
          );
      final pickupAt = ThailandPickupDateTime.tryBangkokWallFromIso(
        _bookingDetailString(detail['scheduledPickupAt']),
      );
      final flight = _bookingDetailMap(detail['flight']);
      final paymentMethod =
          _bookingDetailString(pricing['paymentMethod']) ?? 'PAY_DRIVER';
      final customerUserId = _bookingDetailInt(customer['customerUserId']);

      setState(() {
        _origin = _routeLocation(
          origin,
          fallbackId: '$bookingNumber-origin',
        );
        _destination = _routeLocation(
          destination,
          fallbackId: '$bookingNumber-destination',
        );
        _pickupAt = pickupAt;
        _vehicleTypeCode =
            (_bookingDetailString(vehicle['typeCode']) ?? 'SEDAN')
                .trim()
                .toUpperCase();
        final adultsRaw = _bookingDetailInt(passengers['adults']);
        _adults = (adultsRaw ?? 1).clamp(1, 8);
        _children = (_bookingDetailInt(passengers['children']) ?? 0).clamp(0, 8);
        _infants = (_bookingDetailInt(passengers['infants']) ?? 0).clamp(0, 8);
        _luggage20 =
            (_bookingDetailInt(luggage['carriers20Inch']) ?? 0).clamp(0, 20);
        _luggage24 =
            (_bookingDetailInt(luggage['carriers24InchPlus']) ?? 0).clamp(0, 20);
        _golfBags = (_bookingDetailInt(luggage['golfBags']) ?? 0).clamp(0, 20);
        _specialItemsTextController.clear();
        _applySpecialLuggageFromDetail(
          luggage,
          setCount: (value) => _specialLuggageCount = value,
          setText: (value) => _specialItemsTextController.text = value,
        );
        final serviceCode =
            _bookingDetailString(serviceType['code'])?.toUpperCase();
        if (serviceCode != null && serviceCode.isNotEmpty) {
          _serviceTypeCode = _serviceTypeCodes.contains(serviceCode)
              ? serviceCode
              : serviceCode;
        }
        _preferFemaleDriver = _bookingDetailBool(options['preferFemaleDriver']);
        _flightNumber = _bookingDetailString(flight['flightNumber']) ?? '';
        _originAirportIata = _bookingDetailString(flight['airportIata']);
        _flightScheduledArrivalAt =
            _bookingDetailString(flight['scheduledArrivalAt']);
        _flightEstimatedArrivalAt =
            _bookingDetailString(flight['estimatedArrivalAt']);
        _golfRegion = _bookingDetailString(flight['golfRegion']);
        _golfCourseId = _bookingDetailInt(flight['golfCourseId']);
        _driverIncluded = _bookingDetailBool(flight['driverIncluded']);
        if (_golfRegion != null && _golfRegion!.isNotEmpty) {
          _loadGolfCourses(_golfRegion!);
        }
        _payoutController.text = payout > 0 ? '$payout' : '';
        _customerChargeController.clear();
        _paymentCollection =
            paymentMethod == 'ADMIN_COLLECTED' ? 'ADMIN_COLLECTED' : 'DRIVER_COLLECTS';
        _memoController.text = _bookingDetailString(detail['specialRequests']) ?? '';
        _nameSign = nameSign;
        _nameSignTextController.text =
            _bookingDetailString(options['nameSignText']) ??
            _bookingDetailString(customer['name']) ??
            '';
        _selectedCustomer = null;
        _guestNameController.clear();
        _guestPhoneController.clear();
        _guestEmailController.clear();
        if (customerUserId != null) {
          _selectedCustomer = AdminCustomerSearchResult(
            id: customerUserId,
            name: _bookingDetailString(customer['name']),
            phone: _bookingDetailString(customer['phone']),
            email: _bookingDetailString(customer['email']),
          );
        } else {
          _guestNameController.text = _bookingDetailString(customer['name']) ?? '';
          _guestPhoneController.text = _bookingDetailString(customer['phone']) ?? '';
          _guestEmailController.text = _bookingDetailString(customer['email']) ?? '';
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
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'AdminManualBookingCreatePage._loadForEdit failed for '
          '$bookingNumber: $error\n$stackTrace',
        );
      }
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
      bookingNumber: bookingNumber,
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
    _customerChargeController.removeListener(_onCustomerChargeEdited);
    _searchController.dispose();
    _payoutController.dispose();
    _customerChargeController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _guestEmailController.dispose();
    _messengerIdController.dispose();
    _memoController.dispose();
    _nameSignTextController.dispose();
    _specialItemsTextController.dispose();
    super.dispose();
  }

  String? _defaultNameSignText() {
    final fromCustomer = _selectedCustomer?.name?.trim();
    if (fromCustomer != null && fromCustomer.isNotEmpty) return fromCustomer;
    final guest = _guestNameController.text.trim();
    return guest.isEmpty ? null : guest;
  }

  void _onNameSignChanged(bool? value) {
    final enabled = value ?? false;
    setState(() {
      _nameSign = enabled;
      if (enabled && _nameSignTextController.text.trim().isEmpty) {
        final suggested = _defaultNameSignText();
        if (suggested != null) {
          _nameSignTextController.text = suggested;
        }
      }
      if (!enabled) {
        _nameSignTextController.clear();
      }
    });
    _onQuoteInputsChanged();
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
    final now = ThailandPickupDateTime.thailandNow();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _pickupAt ?? now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: ThailandPickupDateTime.datePickerFirstDate(
        thailandToday: today,
        currentPickup: _pickupAt,
      ),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await PickupTimePickerSheet.show(
      context,
      initialHour24: _pickupAt?.hour ?? initial.hour,
      initialMinute: _pickupAt?.minute ?? initial.minute,
    );
    if (time == null || !mounted) return;
    setState(() {
      _pickupAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour24,
        time.minute,
      );
    });
    _onQuoteInputsChanged();
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

  void _onQuoteInputsChanged() {
    if (_isEditMode || _origin == null || _destination == null) return;
    if (_customerChargeManuallyEdited) {
      if (!_standardPriceStale && mounted) setState(() => _standardPriceStale = true);
      return;
    }
    _fillStandardPrice();
  }

  Future<void> _fillStandardPrice() async {
    final origin = _origin;
    final destination = _destination;
    final service = BookingServiceTypeX.fromApiCode(_serviceTypeCode);
    if (origin == null || destination == null || service == null) return;
    final generation = ++_pricingRequestGeneration;
    setState(() { _loadingStandardPrice = true; _standardPriceError = null; });
    final locations = pricingLocationParams(
      service: service, origin: origin, destination: destination,
    );
    try {
      final result = await _bookingApi.calculatePricing(
        serviceTypeCode: _serviceTypeCode,
        golf: _showsGolfSection ? _golf : null,
        vehicleTypeCode: _vehicleTypeCode,
        originAirportIata: locations['originAirportIata'],
        destinationRegion: locations['destinationRegion'],
        originLocationCode: locations['originLocationCode'],
        destinationLocationCode: locations['destinationLocationCode'],
        nameSign: _nameSign,
        scheduledPickupAt: _pickupAt == null ? null : ThailandPickupDateTime.serializeWallClock(_pickupAt!),
        adults: _adults, children: _children, infants: _infants,
        luggage20: _luggage20, luggage24: _luggage24,
        golfBags: _golfBags, specialLuggageCount: _specialLuggageCount,
        originLat: origin.latitude, originLng: origin.longitude,
        destinationLat: destination.latitude, destinationLng: destination.longitude,
      );
      if (!mounted || generation != _pricingRequestGeneration) return;
      _applyingStandardPrice = true;
      _customerChargeController.text = result.totalAmount.round().toString();
      _applyingStandardPrice = false;
      setState(() {
        _loadingStandardPrice = false;
        _standardPriceStale = false;
        _customerChargeManuallyEdited = false;
      });
    } catch (_) {
      if (!mounted || generation != _pricingRequestGeneration) return;
      setState(() {
        _loadingStandardPrice = false;
        _standardPriceError = context.l10n.t('admin_manual_booking_standard_price_error');
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_origin == null || _destination == null || _pickupAt == null) {
      setState(() => _submitError = context.l10n.t('admin_manual_booking_validation_required'));
      return;
    }
    final enteredMessengerId = _messengerIdController.text.trim();
    final hasMessenger = _messengerType != null;
    final enteredPhone = _guestPhoneController.text.trim();
    final guestPhone = enteredPhone.isEmpty
        ? ''
        : normalizeAdminManualPhone(_guestPhoneDialCode, enteredPhone);
    final phoneRequired = const {'WHATSAPP', 'SMS'}
        .contains(_messengerType);
    if ((phoneRequired && guestPhone.isEmpty) ||
        (enteredPhone.isNotEmpty && guestPhone.isEmpty)) {
      setState(() => _submitError =
          context.l10n.t('admin_manual_booking_validation_customer'));
      return;
    }
    final messengerId = const {'WHATSAPP', 'SMS'}.contains(_messengerType)
        ? guestPhone
        : enteredMessengerId;
    if (_selectedCustomer == null &&
        (_guestNameController.text.trim().isEmpty ||
            (guestPhone.isEmpty && !hasMessenger))) {
      setState(() => _submitError = context.l10n.t('admin_manual_booking_validation_customer'));
      return;
    }
    if (!_isEditMode &&
        _dispatchMode == 'DIRECT' &&
        _selectedDirectDriverId == null) {
      setState(() => _submitError = context.l10n.t('admin_manual_booking_driver_required'));
      return;
    }
    if (_nameSign && _nameSignTextController.text.trim().isEmpty) {
      setState(() => _submitError = context.l10n.t('wizard_required_name_sign_text'));
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
        'scheduledPickupAt':
            ThailandPickupDateTime.serializeWallClock(_pickupAt!),
        'vehicleTypeCode': _vehicleTypeCode,
        if (_showsGolfSection && _golf != null) 'golf': _golf,
        'serviceTypeCode': _serviceTypeCode,
        'payoutAmount': int.parse(_payoutController.text.trim()),
        'customerChargeAmount': customerCharge,
        'paymentCollection': _paymentCollection,
        'customer': _selectedCustomer != null
            ? {
                'customerUserId': _selectedCustomer!.id,
                if (hasMessenger) 'messengerType': _messengerType,
                if (messengerId.isNotEmpty) 'messengerId': messengerId,
                if (guestPhone.isNotEmpty) 'phone': guestPhone,
              }
            : {
                'name': _guestNameController.text.trim(),
                'phone': guestPhone.isEmpty ? null : guestPhone,
                if (_guestEmailController.text.trim().isNotEmpty)
                  'email': _guestEmailController.text.trim(),
                if (hasMessenger) 'messengerType': _messengerType,
                if (messengerId.isNotEmpty) 'messengerId': messengerId,
              },
        'memo': _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
        'passengers': {
          'adults': _adults,
          'children': _children,
          'infants': _infants,
        },
        'luggage': _luggagePayload,
        'nameSign': _nameSign,
        'nameSignText': _nameSign ? _nameSignTextController.text.trim() : null,
        'preferFemaleDriver': _preferFemaleDriver,
        if (_originAirportIata != null && _originAirportIata!.isNotEmpty)
          'originAirportIata': _originAirportIata,
        if (_transferPayload != null) 'transfer': _transferPayload,
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
          luggage: payload['luggage'] as Map<String, dynamic>,
          serviceTypeCode: payload['serviceTypeCode'] as String,
          nameSign: payload['nameSign'] as bool,
          nameSignText: payload['nameSignText'] as String?,
          preferFemaleDriver: payload['preferFemaleDriver'] as bool,
          originAirportIata: payload['originAirportIata'] as String?,
          transfer: payload['transfer'] as Map<String, dynamic>?,
        );
      } else {
        result = await _dispatchApi.createManualBooking(
          golf: _showsGolfSection ? _golf : null,
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
          luggage: payload['luggage'] as Map<String, dynamic>,
          serviceTypeCode: payload['serviceTypeCode'] as String,
          nameSign: payload['nameSign'] as bool,
          nameSignText: payload['nameSignText'] as String?,
          preferFemaleDriver: payload['preferFemaleDriver'] as bool,
          originAirportIata: payload['originAirportIata'] as String?,
          transfer: payload['transfer'] as Map<String, dynamic>?,
          driverId: _dispatchMode == 'DIRECT' ? _selectedDirectDriverId : null,
        );
      }
      if (!mounted) return;
      final bookingNumber =
          result['bookingNumber'] as String? ?? _editingBookingNumber;
      setState(() {
        _submitting = false;
        _createdBookingNumber = bookingNumber;
      });
      if (_isEditMode && widget.editBookingNumber != null) {
        Navigator.of(context).pop(true);
        return;
      }
      if (_isEditMode && widget.editBookingNumber == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('admin_manual_booking_update_success'))),
        );
      } else if (!_isEditMode && bookingNumber != null) {
        final successMessage = _dispatchMode == 'DIRECT'
            ? '${context.l10n.t('admin_manual_booking_assign_success')} · '
                '${context.l10n.t('booking_number_label')}: $bookingNumber'
            : '${context.l10n.t('admin_manual_booking_success')} $bookingNumber';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
        await _openDetail();
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

  Widget _phoneInput(AppLocalizations l10n) {
    final required = const {'WHATSAPP', 'SMS'}
        .contains(_messengerType);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: DropdownButtonFormField<String>(
            key: ValueKey('adminManualPhoneDialCode-$_guestPhoneDialCode'),
            initialValue: _guestPhoneDialCode,
            items: const ['+66', '+82', '+81', '+86']
                .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                .toList(),
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _guestPhoneDialCode = value);
                    }
                  },
          ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: TextFormField(
            key: const Key('adminManualBookingGuestPhone'),
            controller: _guestPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: required
                  ? '${l10n.t('field_required')} ${l10n.t('phone')}'
                  : l10n.t('admin_manual_booking_guest_phone'),
              hintText: '010-1234-5678',
              helperText: const {'KAKAO', 'LINE'}.contains(_messengerType)
                  ? l10n.t('admin_contact_phone_optional_warning') : null,
              helperMaxLines: 4,
            ),
          ),
        ),
      ],
    );
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
                                : () {
                                    setState(
                                      () => _editingBookingNumber =
                                          _createdBookingNumber,
                                    );
                                    WidgetsBinding.instance.addPostFrameCallback(
                                      (_) => _loadForEdit(),
                                    );
                                  },
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
              if (!_isEditMode) ...[
                AppUi.surfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.t('admin_manual_booking_dispatch_mode'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      RadioListTile<String>(
                        key: const Key('adminManualDispatchOpen'),
                        contentPadding: EdgeInsets.zero,
                        value: 'OPEN',
                        groupValue: _dispatchMode,
                        onChanged: _submitting ? null : (value) => setState(() {
                          _dispatchMode = value ?? 'OPEN';
                          _selectedDirectDriverId = null;
                        }),
                        title: Text(l10n.t('admin_manual_booking_dispatch_open')),
                      ),
                      RadioListTile<String>(
                        key: const Key('adminManualDispatchDirect'),
                        contentPadding: EdgeInsets.zero,
                        value: 'DIRECT',
                        groupValue: _dispatchMode,
                        onChanged: _submitting ? null : (value) => setState(
                          () => _dispatchMode = value ?? 'OPEN',
                        ),
                        title: Text(l10n.t('admin_manual_booking_dispatch_direct')),
                      ),
                      if (_dispatchMode == 'DIRECT') ...[
                        const SizedBox(height: AppTokens.spaceSm),
                        if (_loadingDirectDrivers)
                          const Center(child: CircularProgressIndicator())
                        else
                          DropdownButtonFormField<int>(
                            key: const Key('adminManualDirectDriver'),
                            value: _eligibleDirectDrivers.any(
                              (driver) => _bookingDetailInt(driver['driverId'])
                                  == _selectedDirectDriverId,
                            ) ? _selectedDirectDriverId : null,
                            decoration: InputDecoration(
                              labelText: l10n.t('admin_manual_booking_driver'),
                              hintText: l10n.t('admin_manual_booking_driver_hint'),
                            ),
                            items: _eligibleDirectDrivers.map((driver) {
                              final vehicle = _bookingDetailMap(driver['primaryVehicle']);
                              final name = _bookingDetailString(driver['displayName'])
                                  ?? '#${driver['driverId']}';
                              final vehicleCode = _bookingDetailString(
                                vehicle['vehicleTypeCode'],
                              );
                              return DropdownMenuItem<int>(
                                value: _bookingDetailInt(driver['driverId']),
                                child: Text(
                                  vehicleCode == null ? name : '$name · $vehicleCode',
                                ),
                              );
                            }).toList(growable: false),
                            onChanged: _submitting ? null : (value) => setState(
                              () => _selectedDirectDriverId = value,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],
              AppUi.surfaceCard(
                backgroundColor: AppTokens.primaryLight,
                child: InkWell(
                  onTap: _submitting ? null : _pickPickupDateTime,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.spaceSm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.schedule,
                          color: AppTokens.primary,
                          size: 28,
                        ),
                        const SizedBox(width: AppTokens.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.t('admin_manual_booking_pickup_datetime'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppTokens.primary,
                                    ),
                              ),
                              const SizedBox(height: AppTokens.spaceXs),
                              Text(
                                _formatPickupDisplay(l10n),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: AppTokens.spaceXs),
                              Text(
                                l10n.t('admin_manual_booking_pickup_timezone'),
                                style: const TextStyle(
                                  color: AppTokens.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GooglePlacesSearchField(
                      label: l10n.t('admin_manual_booking_origin'),
                      languageCode: languageCode,
                      selected: _origin,
                      onSelected: (value) {
                        setState(() => _origin = value);
                        _onQuoteInputsChanged();
                      },
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    GooglePlacesSearchField(
                      label: l10n.t('admin_manual_booking_destination'),
                      languageCode: languageCode,
                      selected: _destination,
                      onSelected: (value) {
                        setState(() => _destination = value);
                        _onQuoteInputsChanged();
                      },
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    DropdownButtonFormField<String>(
                      key: const Key('adminManualBookingServiceType'),
                      value: _serviceTypeCode,
                      decoration: InputDecoration(
                        labelText: l10n.t('service_type'),
                      ),
                      items: (_serviceTypeCodes.contains(_serviceTypeCode)
                              ? _serviceTypeCodes
                              : [..._serviceTypeCodes, _serviceTypeCode])
                          .map((code) {
                            final type = BookingServiceTypeX.fromApiCode(code);
                            final label = type != null
                                ? l10n.t(type.labelKey)
                                : code;
                            return DropdownMenuItem(
                              value: code,
                              child: Text(label),
                            );
                          })
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _serviceTypeCode = value;
                            if (!_showsFlightSection) {
                              _flightNumber = '';
                              _originAirportIata = null;
                              _applyFlightLookup(null);
                            }
                            if (!_showsGolfSection) {
                              _golfRegion = null;
                              _golfCourseId = null;
                              _driverIncluded = false;
                              _golfCourses = const [];
                            }
                          });
                          _onQuoteInputsChanged();
                        }
                      },
                    ),
                    if (_showsGolfSection) GolfTripFields(value:_golf,onChanged:(selection,course) {
                      setState(() {
                        final previous=_golf?['tripType'];
                        _golf=selection;
                        if(course!=null) {
                          _golfCourseId=course['id'] as int;
                          _golfRegion='PATTAYA';
                          final point=LocationOption(id:'golf:${course['id']}',displayName:course['name'].toString(),kind:LocationKind.golf,
                            code:'GOLF_${course['id']}',name:course['name'].toString(),address:course['name'].toString(),
                            latitude:(course['lat'] as num).toDouble(),longitude:(course['lng'] as num).toDouble());
                          if(selection['tripType']=='RETURN') {
                            if(previous!='RETURN' && _origin?.kind!=LocationKind.golf)_destination=_origin;
                            _origin=point;
                          } else {
                            if(previous=='RETURN' && _destination?.kind!=LocationKind.golf)_origin=_destination;
                            _destination=point;
                          }
                        }
                        _driverIncluded=true;
                      });
                      _onQuoteInputsChanged();
                    }),
                    if (_showsFlightSection) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      AdminManualFlightSection(
                        flightNumber: _flightNumber,
                        pickupDateIsoOrBangkokDate: _pickupDateYmdForFlight,
                        pickupAtBangkok: _pickupAt,
                        enabled: !_submitting,
                        onFlightNumberChanged: (value) =>
                            setState(() => _flightNumber = value),
                        onConfirmedLookup: (result) => setState(
                          () => _applyFlightLookup(result),
                        ),
                        onPickupAtApply: (value) {
                          setState(() => _pickupAt = value);
                          _onQuoteInputsChanged();
                        },
                        flightLookupApi: widget.flightLookupApi,
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    DropdownButtonFormField<String>(
                      key: const Key('adminManualBookingVehicleType'),
                      value: _vehicleTypeCode,
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_vehicle_type'),
                      ),
                      items: _vehicleTypeOptions
                          .map(
                            (code) => DropdownMenuItem(
                              value: code,
                              child: Text(code),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _vehicleTypeCode = value;
                            if (!_eligibleDirectDrivers.any(
                              (driver) => _bookingDetailInt(driver['driverId'])
                                  == _selectedDirectDriverId,
                            )) {
                              _selectedDirectDriverId = null;
                            }
                          });
                          _onQuoteInputsChanged();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.sectionHeader(context, title: l10n.t('passengers')),
              AppUi.surfaceCard(
                child: Column(
                  children: [
                    AppUi.counterRow(
                      label: l10n.t('adults'),
                      value: _adults,
                      min: 1,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _adults = value.clamp(1, 8));
                      },
                    ),
                    AppUi.counterRow(
                      label: l10n.t('children'),
                      value: _children,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _children = value.clamp(0, 8));
                      },
                    ),
                    AppUi.counterRow(
                      label: l10n.t('infants'),
                      value: _infants,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _infants = value.clamp(0, 8));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.sectionHeader(context, title: l10n.t('luggage')),
              AppUi.surfaceCard(
                child: Column(
                  children: [
                    AppUi.counterRow(
                      label: l10n.t('small_carriers'),
                      value: _luggage20,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _luggage20 = value.clamp(0, 20));
                      },
                    ),
                    AppUi.counterRow(
                      label: l10n.t('large_carriers'),
                      value: _luggage24,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _luggage24 = value.clamp(0, 20));
                      },
                    ),
                    AppUi.counterRow(
                      label: l10n.t('golf_bags'),
                      value: _golfBags,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _golfBags = value.clamp(0, 20));
                      },
                    ),
                    AppUi.counterRow(
                      label: l10n.t('special_luggage'),
                      value: _specialLuggageCount,
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() {
                          _specialLuggageCount = value.clamp(0, 20);
                          if (value > 0) _specialItemsTextController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    TextFormField(
                      key: const Key('adminManualSpecialItemsText'),
                      controller: _specialItemsTextController,
                      enabled: !_submitting,
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_special_items_text'),
                        hintText: l10n.t('admin_manual_booking_special_items_hint'),
                      ),
                      onChanged: (_) {
                        if (_specialItemsTextController.text.trim().isNotEmpty) {
                          setState(() => _specialLuggageCount = 0);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.t('booking_prefer_female_driver')),
                  subtitle: Text(l10n.t('booking_preference_disclaimer')),
                  value: _preferFemaleDriver,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _preferFemaleDriver = value),
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      key: const Key('adminManualBookingNameSign'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.t('pricing_name_sign_with_picket')),
                      subtitle: Text(l10n.t('admin_manual_booking_name_sign_hint')),
                      value: _nameSign,
                      onChanged: _submitting ? null : _onNameSignChanged,
                    ),
                    if (_nameSign) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      TextFormField(
                        key: const Key('adminManualBookingNameSignText'),
                        controller: _nameSignTextController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: l10n.t('name_sign_text_label'),
                          hintText: l10n.t('name_sign_text_hint'),
                        ),
                        validator: (value) {
                          if (!_nameSign) return null;
                          if (value == null || value.trim().isEmpty) {
                            return l10n.t('wizard_required_name_sign_text');
                          }
                          return null;
                        },
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
                      key: const Key('adminManualBookingCustomerChargeAmount'),
                      controller: _customerChargeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_customer_charge_amount'),
                        helperText: l10n.t('admin_manual_booking_customer_charge_hint'),
                      ),
                    ),
                    if (_loadingStandardPrice)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                        child: Text(l10n.t('admin_manual_booking_standard_price_loading')),
                      )
                    else if (_standardPriceStale)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('adminManualBookingRefillStandardPrice'),
                          onPressed: _submitting ? null : _fillStandardPrice,
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.t('admin_manual_booking_standard_price_refill')),
                        ),
                      )
                    else if (_standardPriceError != null)
                      Text(_standardPriceError!, style: const TextStyle(color: AppTokens.error))
                    else if (_customerChargeController.text.isNotEmpty && !_isEditMode)
                      Text(
                        l10n.t('admin_manual_booking_standard_price_applied'),
                        style: const TextStyle(color: AppTokens.success),
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
                      _phoneInput(l10n),
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
                    const SizedBox(height: AppTokens.spaceMd),
                    DropdownButtonFormField<String?>(
                      key: const Key('adminManualMessengerType'),
                      value: _messengerType,
                      decoration: InputDecoration(
                        labelText: l10n.t('admin_manual_booking_messenger_type'),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.t('admin_manual_booking_messenger_none')),
                        ),
                        for (final type in const [
                          'KAKAO',
                          'LINE',
                          'WHATSAPP',
                          'SMS',
                        ])
                          DropdownMenuItem<String?>(
                            value: type,
                            child: Text(l10n.t(
                              'admin_manual_booking_messenger_${type.toLowerCase()}',
                            )),
                          ),
                      ],
                      onChanged: _submitting ? null : (value) => setState(() {
                        _messengerType = value;
                        _guestPhoneDialCode = value == 'KAKAO' ? '+82' : '+66';
                        if (value == null ||
                            const {'WHATSAPP', 'SMS'}.contains(value)) {
                          _messengerIdController.clear();
                        }
                      }),
                    ),
                    if (_messengerType != null) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      if (_selectedCustomer != null) ...[
                        _phoneInput(l10n),
                        const SizedBox(height: AppTokens.spaceSm),
                      ],
                      if (const {'KAKAO', 'LINE'}.contains(_messengerType))
                        TextFormField(
                        key: const Key('adminManualMessengerId'),
                        controller: _messengerIdController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          labelText: _messengerType == 'KAKAO'
                              ? l10n.t('admin_manual_booking_kakao_id_optional')
                              : l10n.t('admin_manual_booking_messenger_id'),
                          hintText: l10n.t('admin_manual_booking_messenger_id_hint'),
                        ),
                        validator: (value) {
                          if (_messengerType == null ||
                              _messengerType == 'KAKAO') return null;
                          if (value == null || value.trim().isEmpty) {
                            return l10n.t('admin_manual_booking_validation_required');
                          }
                          return null;
                        },
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
                        : _dispatchMode == 'DIRECT'
                            ? l10n.t('admin_manual_booking_direct_submit')
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
