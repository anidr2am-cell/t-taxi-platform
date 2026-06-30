import 'package:flutter/foundation.dart';
import '../models/booking_wizard_state.dart';
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
  bool _isInitialized = false;

  BookingWizardState get state => _state;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  static const vehicleTierOrder = [
    'SEDAN',
    'SUV',
    'VIP_SUV',
    'VAN',
    'VIP_VAN',
    'LUXURY',
  ];

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
  };

  Future<void> initialize() async {
    final restored = await _storage.load();
    if (restored != null) {
      _state = restored;
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
    final today = DateTime(thailandNow().year, thailandNow().month, thailandNow().day);
    if (bangkokValue.isBefore(today)) {
      _state = _state.copyWith(
        errorMessage: 'Pickup date cannot be in the past',
      );
      await _persist();
      notifyListeners();
      return false;
    }
    if (!isPickupDateTimeAllowed(bangkokValue)) {
      _state = _state.copyWith(
        errorMessage: 'Pickup time must be at least 2 hours from now',
      );
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
    await _persist();
    notifyListeners();
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
            'flightNumber': _state.flightNumber.trim().replaceAll(' ', '').toUpperCase(),
        },
      'customer': {
        'name': _state.customerName.trim(),
        'email': _state.customerEmail.trim(),
        'phone': _state.customerPhone.trim(),
        if (_state.customerCountryCode.trim().isNotEmpty)
          'countryCode': _state.customerCountryCode.trim().toUpperCase(),
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

  Future<BookingCreateResult?> submitBooking() async {
    _setLoading(true);
    try {
      final result = await _api.createBooking(buildCreatePayload());
      await _storage.clear();
      _state = const BookingWizardState();
      notifyListeners();
      return result;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadRecommendation() async {
    _setLoading(true);
    try {
      final recommendation = await _api.recommendVehicle(
        adults: _state.adults,
        children: _state.children,
        infants: _state.infants,
        luggage20: _state.luggage20,
        luggage24: _state.luggage24,
        golfBags: _state.golfBags,
        specialLuggageCount: _state.specialLuggageCount,
      );
      final selected = recommendation.multipleVehicles
          ? null
          : recommendation.recommendedVehicle;
      _state = _state.copyWith(
        recommendation: recommendation,
        selectedVehicle: selected,
        clearPricing: true,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(
        errorMessage: e.toString(),
        clearRecommendation: true,
      );
    } finally {
      _setLoading(false);
      await _persist();
    }
  }

  bool isVehicleEnabled(String vehicleCode) {
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
    if (!isVehicleEnabled(vehicleCode)) return;
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
      originAirportIata = _airportIataFromOption(destination);
      destinationLocationCode = _internalLocationCodeFromOption(origin);
      destinationRegion = destinationLocationCode == null
          ? _regionFromLocation(origin)
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
    if (_state.serviceType == null || _state.selectedVehicle == null) return;

    final scheduledPickupAt = scheduledPickupAtIso();
    if (scheduledPickupAt == null) {
      _state = _state.copyWith(
        errorMessage: 'Pickup date and time are required',
        clearPricing: true,
      );
      await _persist();
      notifyListeners();
      return;
    }

    final locations = _pricingLocationParams();
    _setLoading(true);
    try {
      final pricing = await _api.calculatePricing(
        serviceTypeCode: _state.serviceType!.apiCode,
        vehicleTypeCode: _state.selectedVehicle!,
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
      _state = _state.copyWith(pricing: pricing, clearError: true);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString(), clearPricing: true);
    } finally {
      _setLoading(false);
      await _persist();
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

  bool canProceedFromCurrentStep() {
    switch (_state.step) {
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
        return true;
      case 7:
        return _state.customerName.trim().isNotEmpty &&
            _state.customerEmail.trim().isNotEmpty &&
            _state.customerPhone.trim().isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> reset() async {
    _state = const BookingWizardState();
    await _storage.clear();
    notifyListeners();
  }
}
