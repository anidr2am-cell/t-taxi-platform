import 'package:flutter/foundation.dart';

import '../../../utils/user_facing_error.dart';
import '../models/booking_wizard_state.dart';
import '../models/booking_complete_review.dart';
import '../models/booking_create_result.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';
import '../services/booking_api_service.dart';
import '../services/booking_state_storage.dart';
import '../services/recent_locations_storage.dart';

class BookingWizardController extends ChangeNotifier {
  BookingWizardController({
    BookingApiService? apiService,
    BookingStateStorage? storage,
    RecentLocationsStorage? recentLocationsStorage,
    DateTime Function()? now,
  }) : _api = apiService ?? BookingApiService(),
       _storage = storage ?? BookingStateStorage(),
       _recentLocations = recentLocationsStorage ?? RecentLocationsStorage(),
       _now = now ?? DateTime.now;

  final BookingApiService _api;
  final BookingStateStorage _storage;
  final RecentLocationsStorage _recentLocations;
  final DateTime Function() _now;

  BookingWizardState _state = const BookingWizardState();
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _isInitialized = false;
  int _recommendationGeneration = 0;
  int _pricingGeneration = 0;

  BookingWizardState get state => _state;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get isInitialized => _isInitialized;

  static const validationSteps = [0, 1, 2, 3, 4, 5, 6];

  static const vehicleTierOrder = [
    'SEDAN',
    'SUV',
    'VIP_SUV',
    'VAN',
    'VIP_VAN',
    'LUXURY',
  ];

  static const customerHiddenVehicleCodes = {'VIP_SUV', 'VIP_VAN', 'LUXURY'};

  static List<String> get customerVehicleTierOrder => vehicleTierOrder
      .where((code) => !customerHiddenVehicleCodes.contains(code))
      .toList(growable: false);

  bool _isCustomerVisibleVehicle(String? vehicleCode) {
    return vehicleCode != null &&
        !customerHiddenVehicleCodes.contains(vehicleCode);
  }

  void _sanitizeCustomerVehicleSelection() {
    if (!_isCustomerVisibleVehicle(_state.selectedVehicle)) {
      _state = _state.copyWith(clearSelectedVehicle: true, clearPricing: true);
      return;
    }

    final selected = _state.selectedVehicle;
    final recommendation = _state.recommendation;
    if (selected == null || recommendation == null) return;

    if (!recommendation.selectableVehicles.contains(selected) ||
        !isVehicleEnabled(selected)) {
      _state = _state.copyWith(clearSelectedVehicle: true, clearPricing: true);
    }
  }

  static const Map<String, String> _knownAirportIataByText = {
    'BKK': 'BKK',
    'SUVARNABHUMI': 'BKK',
    'สุวรรณภูมิ': 'BKK',
    'スワンナプーム': 'BKK',
    '素万那普': 'BKK',
    'DMK': 'DMK',
    'DON MUEANG': 'DMK',
    'DON MUANG': 'DMK',
    'ดอนเมือง': 'DMK',
    'ドンムアン': 'DMK',
    '廊曼': 'DMK',
    'HKT': 'HKT',
    'PHUKET AIRPORT': 'HKT',
    'CNX': 'CNX',
    'CHIANG MAI AIRPORT': 'CNX',
    'UTP': 'UTP',
    'U-TAPAO': 'UTP',
    'UTAPAO': 'UTP',
  };

  static const Map<String, String> _knownLocationCodeByText = {
    'PATTAYA': 'PATTAYA',
    '파타야': 'PATTAYA',
    'เมืองพัทยา': 'PATTAYA',
    'พัทยา': 'PATTAYA',
    '芭堤雅': 'PATTAYA',
    'パタヤ': 'PATTAYA',
    'パッタヤ': 'PATTAYA',
    'BANGKOK': 'BANGKOK',
    '방콕': 'BANGKOK',
    'กรุงเทพ': 'BANGKOK',
    'กรุงเทพมหานคร': 'BANGKOK',
    '曼谷': 'BANGKOK',
    'バンコク': 'BANGKOK',
    'HUA_HIN': 'HUA_HIN',
    'HUAHIN': 'HUA_HIN',
    'หัวหิน': 'HUA_HIN',
    '华欣': 'HUA_HIN',
    'フアヒン': 'HUA_HIN',
    '후아힌': 'HUA_HIN',
    'RAYONG': 'RAYONG',
    'ระยอง': 'RAYONG',
    '罗勇': 'RAYONG',
    'ラヨン': 'RAYONG',
    '라용': 'RAYONG',
    'AYUTTHAYA': 'AYUTTHAYA',
    'อยุธยา': 'AYUTTHAYA',
    '大城': 'AYUTTHAYA',
    'アユタヤ': 'AYUTTHAYA',
    '아유타야': 'AYUTTHAYA',
  };

  Future<void> initialize() async {
    final restored = await _storage.load();
    if (restored != null) {
      final step = restored.step >= BookingWizardState.stepCount
          ? BookingWizardState.stepCount - 1
          : restored.step;
      _state = restored.copyWith(
        step: step,
        pickupTime: _normalizePickupTime(restored.pickupTime),
      );
      _sanitizeCustomerVehicleSelection();
    } else {
      final initialPickup = defaultPickupDateTime();
      _state = _state.copyWith(
        pickupDate: formatDate(initialPickup),
        pickupTime: formatTime(initialPickup),
      );
      await _persist();
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storage.save(_state);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> selectService(BookingServiceType type) async {
    _state = _state.copyWith(
      serviceType: type,
      clearOrigin: true,
      clearDestination: true,
      clearRecommendation: true,
      clearPricing: true,
      clearError: true,
    );
    await _persist();
    notifyListeners();
    await syncDerivedData();
  }

  Future<void> setOrigin(LocationOption location) async {
    _state = _state.copyWith(
      origin: location,
      clearRecommendation: true,
      clearPricing: true,
      clearError: true,
    );
    await _recentLocations.add(location);
    await _persist();
    notifyListeners();
    await syncDerivedData();
  }

  Future<void> setDestination(LocationOption location) async {
    _state = _state.copyWith(
      destination: location,
      clearRecommendation: true,
      clearPricing: true,
      clearError: true,
    );
    await _recentLocations.add(location);
    await _persist();
    notifyListeners();
    await syncDerivedData();
  }

  DateTime _bangkokWallTime(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  DateTime thailandNow() {
    final adjusted = _now().toUtc().add(const Duration(hours: 7));
    return _bangkokWallTime(adjusted);
  }

  DateTime minimumPickupDateTime() {
    return thailandNow().add(const Duration(hours: 2));
  }

  DateTime defaultPickupDateTime() => minimumPickupDateTime();

  String formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String formatTime(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String? _normalizePickupTime(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?:\s*(.*))?$',
    ).firstMatch(trimmed);
    if (match == null) return value;

    final rawHour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (rawHour == null || minute == null || minute < 0 || minute > 59) {
      return value;
    }

    final suffix = (match.group(3) ?? '').trim().toLowerCase();
    var hour = rawHour;
    if (suffix.isNotEmpty) {
      final isPm =
          suffix.contains('pm') ||
          suffix.contains('오후') ||
          suffix.contains('午後') ||
          suffix.contains('下午');
      final isAm =
          suffix.contains('am') ||
          suffix.contains('오전') ||
          suffix.contains('午前') ||
          suffix.contains('上午');
      if (!isPm && !isAm) return value;
      if (rawHour < 1 || rawHour > 12) return value;
      hour = rawHour % 12;
      if (isPm) hour += 12;
    } else if (hour < 0 || hour > 23) {
      return value;
    }

    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  DateTime? selectedPickupDateTime() {
    final date = _state.pickupDate;
    final time = _state.pickupTime;
    if (date == null || time == null) return null;
    final dateParts = date.split('-').map(int.tryParse).toList();
    final timeParts = time.split(':').map(int.tryParse).toList();
    if (dateParts.length != 3 || timeParts.length != 2) return null;
    if (dateParts.any((part) => part == null) ||
        timeParts.any((part) => part == null)) {
      return null;
    }
    return DateTime(
      dateParts[0]!,
      dateParts[1]!,
      dateParts[2]!,
      timeParts[0]!,
      timeParts[1]!,
    );
  }

  String? scheduledPickupAtIso() {
    final selected = selectedPickupDateTime();
    if (selected == null) return null;
    return serializeThailandPickupAt(selected);
  }

  String serializeThailandPickupAt(DateTime value) {
    final thailandWallTime = value.isUtc
        ? value.add(const Duration(hours: 7))
        : value;
    return '${formatDate(thailandWallTime)}T${formatTime(thailandWallTime)}:00+07:00';
  }

  bool isPickupDateTimeAllowed(DateTime value) {
    return !_bangkokWallTime(value).isBefore(minimumPickupDateTime());
  }

  Future<bool> setPickupDateTime(DateTime value) async {
    final bangkokValue = _bangkokWallTime(value);
    final today = DateTime(
      thailandNow().year,
      thailandNow().month,
      thailandNow().day,
    );
    if (bangkokValue.isBefore(today)) {
      _state = _state.copyWith(errorMessage: 'pickup_date_past');
      await _persist();
      notifyListeners();
      return false;
    }
    if (!isPickupDateTimeAllowed(bangkokValue)) {
      _state = _state.copyWith(errorMessage: 'pickup_time_minimum');
      await _persist();
      notifyListeners();
      return false;
    }
    _state = _state.copyWith(
      pickupDate: formatDate(bangkokValue),
      pickupTime: formatTime(bangkokValue),
      clearPricing: true,
      clearError: true,
    );
    await _persist();
    notifyListeners();
    await syncDerivedData();
    return true;
  }

  Future<List<LocationOption>> loadRecentLocations() {
    return _recentLocations.load();
  }

  Future<void> updatePassengersAndLuggage({
    int? adults,
    int? children,
    int? infants,
    int? luggage20,
    int? luggage24,
    int? golfBags,
    int? specialLuggageCount,
    bool? nameSign,
  }) async {
    _state = _state.copyWith(
      adults: adults,
      children: children,
      infants: infants,
      luggage20: luggage20,
      luggage24: luggage24,
      golfBags: golfBags,
      specialLuggageCount: specialLuggageCount,
      nameSign: nameSign,
      clearRecommendation: true,
      clearPricing: true,
      clearError: true,
    );
    _recommendationGeneration += 1;
    _pricingGeneration += 1;
    await _persist();
    if (canLoadRecommendation()) {
      _setLoading(true);
    }
    notifyListeners();
    if (canLoadRecommendation()) {
      await loadRecommendation();
    }
  }

  Future<void> updateCustomerInfo({
    String? name,
    String? email,
    String? phone,
    String? countryCode,
    String? messengerType,
    String? messengerId,
    String? additionalRequests,
    String? flightNumber,
  }) async {
    _state = _state.copyWith(
      customerName: name,
      customerEmail: email,
      customerPhone: phone,
      customerCountryCode: countryCode,
      messengerType: messengerType,
      messengerId: messengerId,
      additionalRequests: additionalRequests,
      flightNumber: flightNumber,
      clearError: true,
    );
    await _persist();
    notifyListeners();
  }

  Map<String, dynamic> _placePayload(LocationOption? location) {
    if (location == null) return {};
    return {
      'address': location.address ?? location.displayName,
      'placeId': location.placeId,
      'lat': location.latitude,
      'lng': location.longitude,
      'name': location.name,
    };
  }

  String? _airportIataForTransfer() {
    final service = _state.serviceType;
    if (service == BookingServiceType.airportPickup &&
        _state.origin?.kind == LocationKind.airport) {
      return _state.origin?.code;
    }
    if (service == BookingServiceType.airportDropoff &&
        _state.destination?.kind == LocationKind.airport) {
      return _state.destination?.code;
    }
    return null;
  }

  Map<String, dynamic> buildCreatePayload() {
    final locations = _pricingLocationParams();
    final airportIata = _airportIataForTransfer();
    final scheduledPickupAt = scheduledPickupAtIso();
    if (scheduledPickupAt == null) {
      throw StateError('Pickup date and time are required');
    }

    return {
      'serviceTypeCode': _state.serviceType!.apiCode,
      'vehicleTypeCode': _state.selectedVehicle!,
      'vehicleCount': 1,
      'origin': _placePayload(_state.origin),
      'destination': _placePayload(_state.destination),
      if (locations['originAirportIata'] != null)
        'originAirportIata': locations['originAirportIata'],
      if (locations['destinationRegion'] != null)
        'destinationRegion': locations['destinationRegion'],
      if (locations['originLocationCode'] != null)
        'originLocationCode': locations['originLocationCode'],
      if (locations['destinationLocationCode'] != null)
        'destinationLocationCode': locations['destinationLocationCode'],
      'scheduledPickupAt': scheduledPickupAt,
      'passengers': {
        'adults': _state.adults,
        'children': _state.children,
        'infants': _state.infants,
      },
      'luggage': {
        'carriers20Inch': _state.luggage20,
        'carriers24InchPlus': _state.luggage24,
        'golfBags': _state.golfBags,
        'specialLuggageCount': _state.specialLuggageCount,
      },
      'options': {'nameSign': _state.nameSign},
      if (airportIata != null)
        'transfer': {
          'airportIata': airportIata,
          if (_state.serviceType == BookingServiceType.airportPickup &&
              _state.flightNumber.trim().isNotEmpty)
            'flightNumber': _state.flightNumber
                .trim()
                .replaceAll(' ', '')
                .toUpperCase(),
        },
      'customer': {
        'name': _state.customerName.trim(),
        'phone': _state.customerPhone.trim(),
        if (_state.customerCountryCode.trim().isNotEmpty)
          'countryCode': _state.customerCountryCode.trim(),
        if (_state.customerEmail.trim().isNotEmpty)
          'email': _state.customerEmail.trim(),
        if (_state.messengerType.trim().isNotEmpty)
          'messengerType': _state.messengerType.trim(),
        if (_state.messengerId.trim().isNotEmpty)
          'messengerId': _state.messengerId.trim(),
      },
      if (_state.additionalRequests.trim().isNotEmpty)
        'additionalRequests': _state.additionalRequests.trim(),
    };
  }

  String formatLocationLabel(LocationOption? location) {
    if (location == null) return '-';
    final name = location.name ?? location.displayName;
    if (location.address != null && location.address!.isNotEmpty) {
      return '$name — ${location.address}';
    }
    return name;
  }

  BookingCompleteReview buildCompleteReview() {
    return BookingCompleteReview(
      pickupDate: _state.pickupDate,
      pickupTime: _state.pickupTime,
      serviceType: _state.serviceType,
      flightNumber: _state.flightNumber,
      adults: _state.adults,
      children: _state.children,
      infants: _state.infants,
      luggage20: _state.luggage20,
      luggage24: _state.luggage24,
      golfBags: _state.golfBags,
      specialLuggageCount: _state.specialLuggageCount,
      nameSign: _state.nameSign,
      selectedVehicle: _state.selectedVehicle,
      pricing: _state.pricing,
      customerName: _state.customerName,
      customerEmail: _state.customerEmail,
      customerPhone: _state.customerPhone,
      customerCountryCode: _state.customerCountryCode,
      messengerType: _state.messengerType,
      messengerId: _state.messengerId,
      additionalRequests: _state.additionalRequests,
    );
  }

  Future<BookingCreateResult?> submitBooking() async {
    if (_isSubmitting || _isLoading) return null;
    if (!canSubmitAll()) return null;

    _isSubmitting = true;
    _setLoading(true);
    try {
      final result = await _api.createBooking(buildCreatePayload());
      await _storage.clear();
      _state = const BookingWizardState();
      notifyListeners();
      return result;
    } catch (e) {
      final fieldError = _bookingValidationError(e);
      _state = _state.copyWith(
        step: fieldError?.step ?? _state.step,
        errorMessage:
            fieldError?.messageKey ??
            userFacingError(e, fallback: 'ui_load_failed'),
      );
      notifyListeners();
      return null;
    } finally {
      _isSubmitting = false;
      _setLoading(false);
    }
  }

  ({int step, String messageKey})? _bookingValidationError(Object error) {
    if (error is! BookingApiException ||
        error.errorCode != 'VALIDATION_ERROR' ||
        error.errors.isEmpty) {
      return null;
    }

    final first = error.errors.firstWhere(
      (item) => item.field.isNotEmpty,
      orElse: () => error.errors.first,
    );
    final field = first.field;
    if (field == 'customer.name') {
      return (step: 6, messageKey: 'wizard_required_customer_name');
    }
    if (field == 'customer.phone') {
      return (step: 6, messageKey: 'wizard_required_customer_phone');
    }
    if (field == 'customer.email') {
      return (step: 6, messageKey: 'wizard_customer_email_invalid');
    }
    if (field.startsWith('customer.')) {
      return (step: 6, messageKey: 'wizard_required_customer');
    }
    if (field == 'origin' || field.startsWith('origin.')) {
      return (step: 1, messageKey: 'wizard_required_origin');
    }
    if (field == 'destination' || field.startsWith('destination.')) {
      return (step: 2, messageKey: 'wizard_required_destination');
    }
    if (field == 'scheduledPickupAt') {
      return (step: 3, messageKey: 'pickup_datetime_required');
    }
    if (field.startsWith('passengers.') || field.startsWith('luggage.')) {
      return (step: 4, messageKey: 'wizard_required_passengers');
    }
    if (field == 'vehicleTypeCode' || field == 'vehicleCount') {
      return (step: 5, messageKey: 'wizard_required_vehicle');
    }
    return (step: _state.step, messageKey: 'ui_action_failed');
  }

  Future<void> loadRecommendation() async {
    if (!canLoadRecommendation()) return;

    final generation = ++_recommendationGeneration;
    final requestCounts = (
      adults: _state.adults,
      children: _state.children,
      infants: _state.infants,
      luggage20: _state.luggage20,
      luggage24: _state.luggage24,
      golfBags: _state.golfBags,
      specialLuggageCount: _state.specialLuggageCount,
    );

    _setLoading(true);
    try {
      final recommendation = await _api.recommendVehicle(
        adults: requestCounts.adults,
        children: requestCounts.children,
        infants: requestCounts.infants,
        luggage20: requestCounts.luggage20,
        luggage24: requestCounts.luggage24,
        golfBags: requestCounts.golfBags,
        specialLuggageCount: requestCounts.specialLuggageCount,
      );
      if (generation != _recommendationGeneration) return;
      if (_state.adults != requestCounts.adults ||
          _state.children != requestCounts.children ||
          _state.infants != requestCounts.infants ||
          _state.luggage20 != requestCounts.luggage20 ||
          _state.luggage24 != requestCounts.luggage24 ||
          _state.golfBags != requestCounts.golfBags ||
          _state.specialLuggageCount != requestCounts.specialLuggageCount) {
        return;
      }

      final autoSelected = recommendation.multipleVehicles
          ? null
          : (_isCustomerVisibleVehicle(recommendation.recommendedVehicle)
                ? recommendation.recommendedVehicle
                : null);
      _state = _state.copyWith(
        recommendation: recommendation,
        selectedVehicle: _state.selectedVehicle ?? autoSelected,
        clearPricing: true,
        clearError: true,
      );
      _sanitizeCustomerVehicleSelection();
      await _persist();
    } catch (e) {
      if (generation != _recommendationGeneration) return;
      _state = _state.copyWith(
        errorMessage: userFacingError(e, fallback: 'ui_load_failed'),
        clearRecommendation: true,
      );
    } finally {
      if (generation == _recommendationGeneration) {
        _setLoading(false);
        notifyListeners();
        if (_state.selectedVehicle != null && _state.pricing == null) {
          await loadPricing();
        }
      }
    }
  }

  bool isVehicleEnabled(String vehicleCode) {
    if (!_isCustomerVisibleVehicle(vehicleCode)) return false;
    final recommendation = _state.recommendation;
    if (recommendation == null) return false;
    if (!recommendation.selectableVehicles.contains(vehicleCode)) return false;

    final recommended = recommendation.recommendedVehicle;
    if (recommended == null) return true;

    final recommendedIndex = vehicleTierOrder.indexOf(recommended);
    final vehicleIndex = vehicleTierOrder.indexOf(vehicleCode);
    if (recommendedIndex >= 0 &&
        vehicleIndex >= 0 &&
        vehicleIndex < recommendedIndex) {
      return false;
    }
    return true;
  }

  Future<void> selectVehicle(String vehicleCode) async {
    if (!_isCustomerVisibleVehicle(vehicleCode) ||
        !isVehicleEnabled(vehicleCode)) {
      return;
    }
    _state = _state.copyWith(
      selectedVehicle: vehicleCode,
      clearPricing: true,
      clearError: true,
    );
    await _persist();
    notifyListeners();
    await loadPricing();
  }

  Map<String, String?> _pricingLocationParams() {
    final service = _state.serviceType;
    final origin = _state.origin;
    final destination = _state.destination;

    String? originAirportIata;
    String? destinationRegion;
    String? originLocationCode;
    String? destinationLocationCode;

    if (service == BookingServiceType.airportPickup) {
      originAirportIata = _airportIataFromOption(origin);
      destinationLocationCode = _internalLocationCodeFromOption(destination);
      destinationRegion = destinationLocationCode == null
          ? _regionFromLocation(destination)
          : null;
    } else if (service == BookingServiceType.airportDropoff) {
      originLocationCode =
          _internalLocationCodeFromOption(origin) ??
          _regionFromLocation(origin);
      final destinationAirportIata = _airportIataFromOption(destination);
      destinationLocationCode =
          _internalLocationCodeFromOption(destination) ??
          destinationAirportIata;
      destinationRegion = destinationLocationCode == null
          ? _regionFromLocation(destination)
          : null;
    } else if (service == BookingServiceType.cityTransfer) {
      originAirportIata = _airportIataFromOption(origin);
      originLocationCode = originAirportIata == null
          ? (_internalLocationCodeFromOption(origin) ??
                _regionFromLocation(origin))
          : null;
      destinationLocationCode = _internalLocationCodeFromOption(destination);
      destinationRegion = destinationLocationCode == null
          ? _regionFromLocation(destination)
          : null;
    } else if (service == BookingServiceType.golfTransfer) {
      originAirportIata = _airportIataFromOption(origin);
      originLocationCode = originAirportIata == null
          ? (_internalLocationCodeFromOption(origin) ??
                _regionFromLocation(origin))
          : null;
      destinationLocationCode = _internalLocationCodeFromOption(destination);
      destinationRegion = destinationLocationCode == null
          ? _regionFromLocation(destination ?? origin)
          : null;
    }

    return {
      'originAirportIata': originAirportIata,
      'destinationRegion': destinationRegion,
      'originLocationCode': originLocationCode,
      'destinationLocationCode': destinationLocationCode,
    };
  }

  String? _regionFromLocation(LocationOption? location) {
    if (location == null) return null;
    if (location.region != null && location.region!.isNotEmpty) {
      return location.region;
    }
    if (location.code != null &&
        location.kind != LocationKind.place &&
        location.kind != LocationKind.golf) {
      return location.code;
    }
    if (location.name != null && location.name!.isNotEmpty) {
      return location.name;
    }
    if (location.address != null && location.address!.isNotEmpty) {
      return location.address!.split(',').first.trim();
    }
    final name = location.displayName.split(',').first.trim();
    return name.isEmpty ? null : name;
  }

  String? _airportIataFromOption(LocationOption? location) {
    if (location == null) return null;
    final code = location.code?.trim().toUpperCase();
    if (code != null && _knownAirportIataByText.containsValue(code)) {
      return code;
    }

    final text = [
      location.code,
      location.name,
      location.displayName,
      location.address,
    ].whereType<String>().join(' ').toUpperCase();

    for (final entry in _knownAirportIataByText.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  String? _internalLocationCodeFromOption(LocationOption? location) {
    if (location == null) return null;
    final code = location.code?.trim().toUpperCase();
    if (code != null &&
        code.isNotEmpty &&
        _knownLocationCodeByText.containsValue(code)) {
      return code;
    }
    if (code != null &&
        code.isNotEmpty &&
        location.kind != LocationKind.place) {
      return code;
    }

    final text = [
      location.region,
      location.name,
      location.displayName,
      location.address,
    ].whereType<String>().join(' ').toUpperCase();

    for (final entry in _knownLocationCodeByText.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  Future<void> loadPricing() async {
    if (!canLoadPricing()) return;
    if (_state.serviceType == null || _state.selectedVehicle == null) return;

    final generation = ++_pricingGeneration;
    final scheduledPickupAt = scheduledPickupAtIso();
    if (scheduledPickupAt == null) {
      _state = _state.copyWith(
        errorMessage: 'pickup_datetime_required',
        clearPricing: true,
      );
      await _persist();
      notifyListeners();
      return;
    }

    final locations = _pricingLocationParams();
    final requestVehicle = _state.selectedVehicle!;
    _setLoading(true);
    try {
      final pricing = await _api.calculatePricing(
        serviceTypeCode: _state.serviceType!.apiCode,
        vehicleTypeCode: requestVehicle,
        originAirportIata: locations['originAirportIata'],
        destinationRegion: locations['destinationRegion'],
        originLocationCode: locations['originLocationCode'],
        destinationLocationCode: locations['destinationLocationCode'],
        scheduledPickupAt: scheduledPickupAt,
        nameSign: _state.nameSign,
        adults: _state.adults,
        children: _state.children,
        infants: _state.infants,
        luggage20: _state.luggage20,
        luggage24: _state.luggage24,
        golfBags: _state.golfBags,
        specialLuggageCount: _state.specialLuggageCount,
      );
      if (generation != _pricingGeneration ||
          _state.selectedVehicle != requestVehicle) {
        return;
      }
      _state = _state.copyWith(pricing: pricing, clearError: true);
    } catch (e) {
      if (generation != _pricingGeneration ||
          _state.selectedVehicle != requestVehicle) {
        return;
      }
      _state = _state.copyWith(
        errorMessage:
            bookingPricingInquiryMessage(e) ??
            userFacingError(e, fallback: 'ui_action_failed'),
        clearPricing: true,
      );
    } finally {
      if (generation == _pricingGeneration) {
        _setLoading(false);
        await _persist();
        notifyListeners();
      }
    }
  }

  Future<bool> goNext() async {
    if (_state.step == 4) {
      await loadRecommendation();
      if (_state.recommendation == null && _state.errorMessage != null) {
        return false;
      }
    }

    if (_state.step < BookingWizardState.stepCount - 1) {
      final nextStep = _state.step + 1;
      _state = _state.copyWith(step: nextStep, clearError: true);
      await _persist();
      notifyListeners();

      if (nextStep == 4 && _state.recommendation == null) {
        await loadRecommendation();
      }
      if (nextStep == 5 &&
          _state.selectedVehicle != null &&
          _state.pricing == null) {
        await loadPricing();
      }
      return true;
    }
    return false;
  }

  Future<void> goBack() async {
    if (_state.step > 0) {
      _state = _state.copyWith(step: _state.step - 1, clearError: true);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> goToStep(int step) async {
    if (step < 0 || step >= BookingWizardState.stepCount) return;
    _state = _state.copyWith(step: step, clearError: true);
    await _persist();
    notifyListeners();

    if (step == 4 && _state.recommendation == null) {
      await loadRecommendation();
    }
    if (step == 5 && _state.selectedVehicle != null && _state.pricing == null) {
      await loadPricing();
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  bool _isCustomerStepValid() {
    if (_state.customerName.trim().isEmpty) return false;
    if (_state.customerPhone.trim().isEmpty) return false;
    final email = _state.customerEmail.trim();
    if (email.isNotEmpty && !_isValidEmail(email)) return false;
    return true;
  }

  bool canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _state.serviceType != null;
      case 1:
        return _state.origin != null;
      case 2:
        return _state.destination != null;
      case 3:
        final selected = selectedPickupDateTime();
        return selected != null && isPickupDateTimeAllowed(selected);
      case 4:
        return _state.adults >= 1;
      case 5:
        return _state.selectedVehicle != null && _state.pricing != null;
      case 6:
        return _isCustomerStepValid();
      default:
        return false;
    }
  }

  bool isStepComplete(int step) => canProceedFromStep(step);

  bool canProceedFromCurrentStep() => canProceedFromStep(_state.step);

  bool canLoadRecommendation() {
    if (_state.serviceType == null ||
        _state.origin == null ||
        _state.destination == null ||
        _state.adults < 1) {
      return false;
    }
    final selected = selectedPickupDateTime();
    return selected != null && isPickupDateTimeAllowed(selected);
  }

  bool canLoadPricing() {
    return canLoadRecommendation() &&
        _state.recommendation != null &&
        _state.selectedVehicle != null;
  }

  Future<void> syncDerivedData() async {
    if (_isSubmitting) return;
    if (canLoadRecommendation() &&
        (_state.recommendation == null || !_isLoading)) {
      await loadRecommendation();
      return;
    }
    if (canLoadPricing() && _state.pricing == null && !_isLoading) {
      await loadPricing();
    }
  }

  Future<bool> prepareForSubmit() async {
    if (!canLoadRecommendation()) return false;
    if (_state.recommendation == null) {
      await loadRecommendation();
      if (_state.recommendation == null) return false;
    }
    if (_state.selectedVehicle == null) return false;
    if (_state.pricing == null) {
      await loadPricing();
    }
    return canSubmitAll();
  }

  int get completedRequiredCount =>
      validationSteps.where(canProceedFromStep).length;

  int get totalRequiredCount => validationSteps.length;

  bool canSubmitAll() {
    for (final step in validationSteps) {
      if (!canProceedFromStep(step)) return false;
    }
    return true;
  }

  int? firstIncompleteStep() {
    for (final step in validationSteps) {
      if (!canProceedFromStep(step)) return step;
    }
    return null;
  }

  String? stepValidationMessageKey(int step) {
    if (canProceedFromStep(step)) return null;
    switch (step) {
      case 0:
        return 'wizard_required_service';
      case 1:
        return 'wizard_required_origin';
      case 2:
        return 'wizard_required_destination';
      case 3:
        if (selectedPickupDateTime() == null) {
          return 'pickup_datetime_required';
        }
        return _state.errorMessage ?? 'pickup_time_minimum';
      case 4:
        return 'wizard_required_passengers';
      case 5:
        if (_state.selectedVehicle == null) {
          return canLoadRecommendation()
              ? 'wizard_required_vehicle'
              : 'wizard_vehicle_prerequisites';
        }
        return 'wizard_pricing_after_vehicle';
      case 6:
        if (_state.customerEmail.trim().isNotEmpty &&
            !_isValidEmail(_state.customerEmail.trim())) {
          return 'wizard_customer_email_invalid';
        }
        return 'wizard_required_customer';
      default:
        return null;
    }
  }

  Future<void> reset() async {
    _state = const BookingWizardState();
    await _storage.clear();
    notifyListeners();
  }
}

String? bookingPricingInquiryMessage(Object err) {
  if (err is! BookingApiException) return null;
  if (err.errorCode != 'NOT_FOUND') return null;
  final message = err.message;
  if (message.contains('Route not found') ||
      message.contains('Vehicle price not configured') ||
      message.contains('Origin or destination location not found')) {
    return 'pricing_inquiry_required';
  }
  return null;
}
