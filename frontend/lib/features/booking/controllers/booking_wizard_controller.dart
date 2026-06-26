import 'package:flutter/foundation.dart';
import '../models/booking_wizard_state.dart';
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
  })  : _api = apiService ?? BookingApiService(),
        _storage = storage ?? BookingStateStorage(),
        _recentLocations = recentLocationsStorage ?? RecentLocationsStorage();

  final BookingApiService _api;
  final BookingStateStorage _storage;
  final RecentLocationsStorage _recentLocations;

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

  Future<void> initialize() async {
    final restored = await _storage.load();
    if (restored != null) {
      _state = restored;
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
    if (recommendedIndex >= 0 && vehicleIndex >= 0 && vehicleIndex < recommendedIndex) {
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
      if (origin?.kind == LocationKind.airport) originAirportIata = origin?.code;
      destinationRegion = _regionFromLocation(destination);
    } else if (service == BookingServiceType.airportDropoff) {
      if (destination?.kind == LocationKind.airport) {
        originAirportIata = destination?.code;
      }
      destinationRegion = _regionFromLocation(origin);
    } else if (service == BookingServiceType.cityTransfer) {
      originLocationCode = _locationCodeFromOption(origin);
      destinationLocationCode = _locationCodeFromOption(destination);
      destinationRegion = _regionFromLocation(destination);
      originAirportIata = origin?.kind == LocationKind.airport ? origin?.code : null;
    } else if (service == BookingServiceType.golfTransfer) {
      destinationRegion = _regionFromLocation(destination ?? origin);
      if (origin?.kind == LocationKind.airport) originAirportIata = origin?.code;
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

  String? _locationCodeFromOption(LocationOption? location) {
    if (location == null) return null;
    if (location.code != null && location.kind != LocationKind.place) {
      return location.code!.toUpperCase();
    }
    return null;
  }

  Future<void> loadPricing() async {
    if (_state.serviceType == null || _state.selectedVehicle == null) return;

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
        nameSign: _state.nameSign,
      );
      _state = _state.copyWith(pricing: pricing, clearError: true);
    } catch (e) {
      _state = _state.copyWith(
        errorMessage: e.toString(),
        clearPricing: true,
      );
    } finally {
      _setLoading(false);
      await _persist();
    }
  }

  Future<bool> goNext() async {
    if (_state.step == 3) {
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

      if (nextStep == 3 && _state.recommendation == null) {
        await loadRecommendation();
      }
      if (nextStep == 4 && _state.selectedVehicle != null && _state.pricing == null) {
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
        return _state.adults >= 1;
      case 4:
        return _state.selectedVehicle != null && _state.pricing != null;
      case 5:
        return true;
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
