import 'package:flutter/material.dart';
import '../config/app_config.dart';

class BookingState extends ChangeNotifier {
  ServiceType? serviceType;
  int adults = 1;
  int children = 0;
  int smallCarriers = 0;
  int largeCarriers = 0;
  int golfBags = 0;
  String specialItems = '';
  bool nameSignService = false;

  String? originPlaceId;
  String? originAddress;
  String? destinationPlaceId;
  String? destinationAddress;
  String? airportCode;
  String? flightNumber;
  String? pickupDate;
  String? pickupTime;
  String? golfRegion;
  int? golfCourseId;
  String? golfCourseName;
  bool driverIncluded = false;

  Map<String, dynamic>? flightInfo;
  String? recommendedVehicle;
  List<String> selectableVehicles = [];
  String? selectedVehicle;
  int vehicleCount = 1;
  double totalPrice = 0;
  String specialRequests = '';

  String customerName = '';
  String customerEmail = '';
  String customerPhone = '';
  String customerCountry = '';

  Map<String, dynamic>? createdReservation;

  void setServiceType(ServiceType type) {
    serviceType = type;
    notifyListeners();
  }

  void updatePassengers({int? adultsVal, int? childrenVal}) {
    if (adultsVal != null) adults = adultsVal;
    if (childrenVal != null) children = childrenVal;
    notifyListeners();
  }

  void updateLuggage({
    int? small,
    int? large,
    int? golf,
    String? special,
  }) {
    if (small != null) smallCarriers = small;
    if (large != null) largeCarriers = large;
    if (golf != null) golfBags = golf;
    if (special != null) specialItems = special;
    notifyListeners();
  }

  void setRouteInfo({
    String? originId,
    String? originAddr,
    String? destId,
    String? destAddr,
    String? airport,
    String? flightNum,
    String? date,
    String? time,
    String? region,
    int? courseId,
    String? courseName,
    bool? driverInc,
    Map<String, dynamic>? flightInfoData,
  }) {
    if (originId != null) originPlaceId = originId;
    if (originAddr != null) originAddress = originAddr;
    if (destId != null) destinationPlaceId = destId;
    if (destAddr != null) destinationAddress = destAddr;
    if (airport != null) airportCode = airport;
    if (flightNum != null) flightNumber = flightNum;
    if (date != null) pickupDate = date;
    if (time != null) pickupTime = time;
    if (region != null) golfRegion = region;
    if (courseId != null) golfCourseId = courseId;
    if (courseName != null) golfCourseName = courseName;
    if (driverInc != null) driverIncluded = driverInc;
    if (flightInfoData != null) flightInfo = flightInfoData;
    notifyListeners();
  }

  void setVehicleRecommendation(Map<String, dynamic> data) {
    recommendedVehicle = data['recommendation']['recommended'] as String?;
    selectableVehicles = (data['selectable'] as List?)?.map((e) => e.toString()).toList() ?? [];
    vehicleCount = data['recommendation']['vehicleCount'] as int? ?? 1;
    selectedVehicle = recommendedVehicle;
    notifyListeners();
  }

  void selectVehicle(String vehicle) {
    selectedVehicle = vehicle;
    notifyListeners();
  }

  void setTotalPrice(double price) {
    totalPrice = price;
    notifyListeners();
  }

  void setCustomerInfo({
    String? name,
    String? email,
    String? phone,
    String? country,
    String? requests,
  }) {
    if (name != null) customerName = name;
    if (email != null) customerEmail = email;
    if (phone != null) customerPhone = phone;
    if (country != null) customerCountry = country;
    if (requests != null) specialRequests = requests;
    notifyListeners();
  }

  void setNameSignService(bool value) {
    nameSignService = value;
    notifyListeners();
  }

  void setAirportCode(String? code) {
    airportCode = code;
    notifyListeners();
  }

  void setPickupDate(String date) {
    pickupDate = date;
    notifyListeners();
  }

  void setPickupTime(String time) {
    pickupTime = time;
    notifyListeners();
  }

  void setGolfRegion(String region) {
    golfRegion = region;
    notifyListeners();
  }

  void setDriverIncluded(bool value) {
    driverIncluded = value;
    notifyListeners();
  }

  void setFlightNumber(String number) {
    flightNumber = number;
    notifyListeners();
  }

  void setCreatedReservation(Map<String, dynamic> reservation) {
    createdReservation = reservation;
    notifyListeners();
  }

  void reset() {
    serviceType = null;
    adults = 1;
    children = 0;
    smallCarriers = 0;
    largeCarriers = 0;
    golfBags = 0;
    specialItems = '';
    nameSignService = false;
    originPlaceId = null;
    originAddress = null;
    destinationPlaceId = null;
    destinationAddress = null;
    airportCode = null;
    flightNumber = null;
    pickupDate = null;
    pickupTime = null;
    golfRegion = null;
    golfCourseId = null;
    golfCourseName = null;
    driverIncluded = false;
    flightInfo = null;
    recommendedVehicle = null;
    selectableVehicles = [];
    selectedVehicle = null;
    vehicleCount = 1;
    totalPrice = 0;
    specialRequests = '';
    customerName = '';
    customerEmail = '';
    customerPhone = '';
    customerCountry = '';
    createdReservation = null;
    notifyListeners();
  }

  Map<String, dynamic> toReservationPayload() {
    return {
      'serviceType': serviceType!.apiValue,
      'passengers': {'adults': adults, 'children': children},
      'luggage': {
        'smallCarriers': smallCarriers,
        'largeCarriers': largeCarriers,
        'golfBags': golfBags,
        'specialItems': specialItems,
      },
      'nameSignService': nameSignService,
      'originPlaceId': originPlaceId,
      'originAddress': originAddress,
      'destinationPlaceId': destinationPlaceId,
      'destinationAddress': destinationAddress,
      'airportCode': airportCode,
      'flightNumber': flightNumber,
      'pickupDate': pickupDate,
      'pickupTime': pickupTime,
      'golfRegion': golfRegion,
      'golfCourseId': golfCourseId,
      'driverIncluded': driverIncluded,
      'selectedVehicle': selectedVehicle,
      'vehicleCount': vehicleCount,
      'specialRequests': specialRequests,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'customerPhone': customerPhone,
      'customerCountry': customerCountry,
      if (flightInfo != null) ...{
        'flightScheduledArrival': flightInfo!['scheduledArrival'],
        'flightEstimatedArrival': flightInfo!['estimatedArrival'],
        'flightDelayStatus': flightInfo!['delayStatus'],
        'flightData': flightInfo!['raw'],
      },
    };
  }
}

class LocaleState extends ChangeNotifier {
  String _languageCode = 'ko';

  String get languageCode => _languageCode;

  void setLanguage(String code) {
    _languageCode = code;
    notifyListeners();
  }
}
