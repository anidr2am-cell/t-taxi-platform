import 'dart:async';

import 'package:tride_driver/core/network/api_exception.dart';
import 'package:tride_driver/core/storage/secure_token_storage.dart';
import 'package:tride_driver/features/auth/data/auth_api.dart';
import 'package:tride_driver/features/auth/data/auth_models.dart';
import 'package:tride_driver/features/account/data/account_api.dart';
import 'package:tride_driver/features/account/data/account_models.dart';
import 'package:tride_driver/features/bookings/data/booking_models.dart';
import 'package:tride_driver/features/bookings/data/booking_repository.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_models.dart';
import 'package:tride_driver/features/dispatch/data/dispatch_repository.dart';
import 'package:tride_driver/features/dispatch/data/driver_socket_service.dart';
import 'package:tride_driver/features/settlement/data/settlement_api.dart';
import 'package:tride_driver/features/settlement/data/settlement_models.dart';

DriverUser driverUser({int id = 7, String? name = 'Somchai'}) =>
    DriverUser(id: id, role: 'DRIVER', isActive: true, name: name);

AuthSession driverSession() => AuthSession(
  user: driverUser(),
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  expiresIn: 3600,
);

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage([this.tokens]);

  AuthTokens? tokens;
  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    tokens = null;
  }

  @override
  Future<AuthTokens?> read() async {
    readCount++;
    return tokens;
  }

  @override
  Future<void> write(AuthTokens value) async {
    writeCount++;
    tokens = value;
  }
}

class FakeAuthApi implements AuthDataSource {
  AuthSession loginResult = driverSession();
  DriverUser meResult = driverUser();
  ApiException? loginError;
  ApiException? meError;
  ApiException? logoutError;
  Completer<AuthSession>? loginCompleter;
  int loginCount = 0;
  int meCount = 0;
  int logoutCount = 0;

  @override
  Future<DriverUser> getMe(String accessToken) async {
    meCount++;
    if (meError case final error?) throw error;
    return meResult;
  }

  @override
  Future<AuthSession> login(String loginId, String password) async {
    loginCount++;
    if (loginCompleter case final completer?) return completer.future;
    if (loginError case final error?) throw error;
    return loginResult;
  }

  @override
  Future<void> logout(AuthTokens tokens) async {
    logoutCount++;
    if (logoutError case final error?) throw error;
  }
}

Map<String, dynamic> bookingJson({
  String bookingNumber = 'TX209912319999',
  String status = 'DRIVER_ASSIGNED',
  Object? assignmentStatus = 'ASSIGNED',
  String pickupDate = '2026-07-18',
  String pickupTime = '09:30',
  bool includeAssignmentStatus = true,
  bool? canConfirmStandby,
  Object? standbyAllowedAt = '2026-07-18T08:30:00.000+07:00',
  List<String>? allowedActions,
  String? scheduledPickupAt = '2026-07-18T09:30:00.000+07:00',
  String? standbyReferenceTime = '2026-07-18T09:30:00.000+07:00',
  bool includeCoordinates = true,
  String serviceTypeCode = 'AIRPORT_PICKUP',
  String serviceTypeName = '공항 픽업',
  String origin = 'Suvarnabhumi Airport',
  String pickupLocationName = 'Suvarnabhumi Airport',
  String pickupLocationAddress = '999 Nong Prue, Bang Phli',
  bool nameSignRequested = true,
  String? nameSignText = 'KIM FAMILY',
  String? nameSignPhotoUrl,
}) {
  final canConfirm =
      canConfirmStandby ??
      (status == 'DRIVER_ASSIGNED' &&
          assignmentStatus == 'ASSIGNED' &&
          standbyAllowedAt != null);
  final json = <String, dynamic>{
    'bookingNumber': bookingNumber,
    'status': status,
    'acceptedAt': null,
    'scheduledPickupAt': scheduledPickupAt,
    'standbyReferenceTimeType': 'VEHICLE_DEPARTURE',
    'standbyReferenceTime': standbyReferenceTime,
    'standbyAllowedAt': standbyAllowedAt,
    'standbyConfirmed': false,
    'standbyConfirmedAt': null,
    'canConfirmStandby': canConfirm,
    'allowedActions':
        allowedActions ??
        (canConfirm
            ? ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT', 'ACCEPT_BOOKING']
            : ['VIEW_DETAILS', 'RELEASE_ASSIGNMENT']),
    'serviceType': {'code': serviceTypeCode, 'name': serviceTypeName},
    'pickupDate': pickupDate,
    'pickupTime': pickupTime,
    'origin': origin,
    'destination': 'Test Hotel',
    'pickupLocation': {
      'name': pickupLocationName,
      'address': pickupLocationAddress,
      'latitude': includeCoordinates ? 13.6900 : null,
      'longitude': includeCoordinates ? 100.7501 : null,
      'placeId': 'pickup-place-id',
    },
    'destinationLocation': {
      'name': 'Test Hotel',
      'address': 'Bangkok',
      'latitude': includeCoordinates ? 13.7563 : null,
      'longitude': includeCoordinates ? 100.5018 : null,
      'placeId': 'destination-place-id',
    },
    'originLatitude': 13.6900,
    'originLongitude': 100.7501,
    'destinationLatitude': 13.7563,
    'destinationLongitude': 100.5018,
    'passengerCount': 2,
    'vehicleType': {'code': 'SEDAN', 'name': '세단'},
    'customerDisplayName': '테스트 고객',
    'flightNumber': 'TG100',
    'driverExpectedIncomeAmount': '900.00',
    'driverExpectedIncomeCurrency': 'THB',
    'nameSignRequested': nameSignRequested,
    'nameSignText': nameSignText,
    'nameSignPhotoUrl': nameSignPhotoUrl,
  };
  if (includeAssignmentStatus) {
    json['assignmentStatus'] = assignmentStatus;
  }
  return json;
}

BookingSummary bookingSummary({
  String bookingNumber = 'TX209912319999',
  String status = 'DRIVER_ASSIGNED',
  Object? assignmentStatus = 'ASSIGNED',
  bool includeAssignmentStatus = true,
  bool? canConfirmStandby,
  Object? standbyAllowedAt = '2026-07-18T08:30:00.000+07:00',
  List<String>? allowedActions,
  String? scheduledPickupAt = '2026-07-18T09:30:00.000+07:00',
  String? standbyReferenceTime = '2026-07-18T09:30:00.000+07:00',
  bool includeCoordinates = true,
  String serviceTypeCode = 'AIRPORT_PICKUP',
  String serviceTypeName = '공항 픽업',
  String origin = 'Suvarnabhumi Airport',
  String pickupLocationName = 'Suvarnabhumi Airport',
  String pickupLocationAddress = '999 Nong Prue, Bang Phli',
  bool nameSignRequested = true,
  String? nameSignText = 'KIM FAMILY',
  String? nameSignPhotoUrl,
}) => BookingSummary.fromJson(
  bookingJson(
    bookingNumber: bookingNumber,
    status: status,
    assignmentStatus: assignmentStatus,
    includeAssignmentStatus: includeAssignmentStatus,
    canConfirmStandby: canConfirmStandby,
    standbyAllowedAt: standbyAllowedAt,
    allowedActions: allowedActions,
    scheduledPickupAt: scheduledPickupAt,
    standbyReferenceTime: standbyReferenceTime,
    includeCoordinates: includeCoordinates,
    serviceTypeCode: serviceTypeCode,
    serviceTypeName: serviceTypeName,
    origin: origin,
    pickupLocationName: pickupLocationName,
    pickupLocationAddress: pickupLocationAddress,
    nameSignRequested: nameSignRequested,
    nameSignText: nameSignText,
    nameSignPhotoUrl: nameSignPhotoUrl,
  ),
);

BookingList bookingList({List<BookingSummary>? items}) =>
    BookingList(serviceDate: '2026-07-18', items: items ?? [bookingSummary()]);

BookingDetail bookingDetail({
  String status = 'DRIVER_ASSIGNED',
  Object? assignmentStatus = 'ASSIGNED',
  bool includeAssignmentStatus = true,
  String bookingNumber = 'TX209912319999',
  bool? canConfirmStandby,
  Object? standbyAllowedAt = '2026-07-18T08:30:00.000+07:00',
  List<String>? allowedActions,
  bool nameSignRequested = true,
  String? nameSignText = 'KIM FAMILY',
  String? nameSignPhotoUrl,
  bool releaseAssignmentAvailable = true,
  bool releaseAssignmentEmergencyOnly = false,
  String? assignmentReleaseDeadline = '2099-12-31T07:30:00.000+07:00',
  String? assignmentReleaseBlockedReason,
  bool includeCoordinates = true,
  String serviceTypeCode = 'AIRPORT_PICKUP',
  String serviceTypeName = '공항 픽업',
  String origin = 'Suvarnabhumi Airport',
  String pickupLocationName = 'Suvarnabhumi Airport',
  String pickupLocationAddress = '999 Nong Prue, Bang Phli',
}) => BookingDetail.fromEnvelope({
  'success': true,
  'data': {
    ...bookingJson(
      bookingNumber: bookingNumber,
      status: status,
      assignmentStatus: assignmentStatus,
      includeAssignmentStatus: includeAssignmentStatus,
      canConfirmStandby: canConfirmStandby,
      standbyAllowedAt: standbyAllowedAt,
      allowedActions: allowedActions,
      includeCoordinates: includeCoordinates,
      serviceTypeCode: serviceTypeCode,
      serviceTypeName: serviceTypeName,
      origin: origin,
      pickupLocationName: pickupLocationName,
      pickupLocationAddress: pickupLocationAddress,
      nameSignRequested: nameSignRequested,
      nameSignText: nameSignText,
      nameSignPhotoUrl: nameSignPhotoUrl,
    ),
    'passengers': {'adults': 2, 'children': 0, 'infants': 0},
    'luggage': {
      'carriers20Inch': 1,
      'carriers24InchPlus': 1,
      'golfBags': 0,
      'specialItems': null,
    },
    'flight': {
      'flightNumber': 'TG100',
      'flightStatus': 'ON_TIME',
      'latestEstimatedArrival': '2026-07-18 08:30:00',
      'delayMinutes': 0,
    },
    'specialInstructions': 'Synthetic fixture note',
    'customerPaymentAmount': 1200,
    'customerPaymentCurrency': 'THB',
    'companyCommissionAmount': 300,
    'companyCommissionCurrency': 'THB',
    'nameSignRequested': nameSignRequested,
    'nameSignText': nameSignText,
    'nameSignPhotoUrl': nameSignPhotoUrl,
    'capabilities': {
      'releaseAssignmentAvailable': releaseAssignmentAvailable,
      'releaseAssignmentEmergencyOnly': releaseAssignmentEmergencyOnly,
      'assignmentReleaseDeadline': assignmentReleaseDeadline,
      'assignmentReleaseBlockedReason': assignmentReleaseBlockedReason,
      'reassignmentPriority': 'NORMAL',
    },
  },
});

Map<String, dynamic> acceptanceEnvelope({
  String bookingNumber = 'TX209912319999',
  String bookingStatus = 'DRIVER_ASSIGNED',
  String assignmentStatus = 'ACCEPTED',
  String? acceptedAt = '2026-07-18T02:30:00.000Z',
  bool idempotent = false,
}) => {
  'success': true,
  'message': 'Booking accepted',
  'data': {
    'bookingNumber': bookingNumber,
    'bookingStatus': bookingStatus,
    'assignmentStatus': assignmentStatus,
    'acceptedAt': acceptedAt,
    'idempotent': idempotent,
    'ignoredExtra': 'ok',
  },
};

class FakeBookingReader implements BookingReader {
  BookingList listResult = bookingList();
  BookingDetail detailResult = bookingDetail();
  BookingAcceptance acceptResult = BookingAcceptance.fromEnvelope(
    acceptanceEnvelope(),
  );
  Object? listError;
  Object? detailError;
  Object? acceptError;
  Object? actionError;
  Object? releaseError;
  Object? nameSignPhotoError;
  Completer<BookingList>? listCompleter;
  Completer<BookingDetail>? detailCompleter;
  Completer<BookingAcceptance>? acceptCompleter;
  Completer<void>? actionCompleter;
  Completer<void>? releaseCompleter;
  int listCount = 0;
  int detailCount = 0;
  int acceptCount = 0;
  int startRouteCount = 0;
  int arriveCount = 0;
  int pickedUpCount = 0;
  int endTripCount = 0;
  int releaseCount = 0;
  int nameSignPhotoUploadCount = 0;
  int nameSignPhotoLoadCount = 0;
  String? releasedReasonCode;
  String? releasedReasonDetail;
  String? requestedBookingNumber;
  String? acceptedBookingNumber;
  List<BookingDetail> detailQueue = [];
  NameSignPhotoUploadResult nameSignPhotoResult =
      const NameSignPhotoUploadResult(
        bookingNumber: 'TX209912319999',
        nameSignPhotoFileId: 501,
        nameSignPhotoUrl:
            '/api/v1/driver/bookings/TX209912319999/name-sign-photo',
      );
  List<int> nameSignPhotoBytes = const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  @override
  Future<BookingDetail> getBookingDetail(String bookingNumber) async {
    detailCount++;
    requestedBookingNumber = bookingNumber;
    if (detailCompleter case final completer?) return completer.future;
    if (detailQueue.isNotEmpty) {
      return detailQueue.removeAt(0);
    }
    if (detailError case final error?) throw error;
    return detailResult;
  }

  @override
  Future<BookingList> getTodayBookings() async {
    listCount++;
    if (listCompleter case final completer?) return completer.future;
    if (listError case final error?) throw error;
    return listResult;
  }

  @override
  Future<BookingAcceptance> acceptBooking(String bookingNumber) async {
    acceptCount++;
    acceptedBookingNumber = bookingNumber;
    if (acceptCompleter case final completer?) return completer.future;
    if (acceptError case final error?) throw error;
    return acceptResult;
  }

  Future<void> _runAction(void Function() increment) async {
    increment();
    if (actionCompleter case final completer?) await completer.future;
    if (actionError case final error?) throw error;
  }

  @override
  Future<void> startOnRoute(String bookingNumber) =>
      _runAction(() => startRouteCount++);

  @override
  Future<void> markArrived(String bookingNumber) =>
      _runAction(() => arriveCount++);

  @override
  Future<void> markPickedUp(String bookingNumber) =>
      _runAction(() => pickedUpCount++);

  @override
  Future<void> endTrip(String bookingNumber) =>
      _runAction(() => endTripCount++);

  @override
  Future<BookingReleaseResult> releaseAssignment(
    String bookingNumber, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    releaseCount++;
    releasedReasonCode = reasonCode;
    releasedReasonDetail = reasonDetail;
    if (releaseCompleter case final completer?) await completer.future;
    if (releaseError case final error?) throw error;
    return BookingReleaseResult(
      bookingNumber: bookingNumber,
      released: true,
      status: BookingStatus.parse('OPEN'),
      reasonCode: reasonCode,
    );
  }

  @override
  Future<NameSignPhotoUploadResult> uploadNameSignPhoto(
    String bookingNumber,
    NameSignPhotoFile file,
  ) async {
    nameSignPhotoUploadCount++;
    requestedBookingNumber = bookingNumber;
    if (nameSignPhotoError case final error?) throw error;
    return nameSignPhotoResult;
  }

  @override
  Future<List<int>> getNameSignPhoto(String bookingNumber) async {
    nameSignPhotoLoadCount++;
    requestedBookingNumber = bookingNumber;
    if (nameSignPhotoError case final error?) throw error;
    return nameSignPhotoBytes;
  }
}

DriverDispatchStatus dispatchStatus({
  bool online = false,
  bool canReceiveCalls = false,
  String status = 'OFFLINE',
}) => DriverDispatchStatus(
  driverId: 7,
  active: true,
  online: online,
  status: status,
  hasActiveJob: false,
  lastSeenAt: '2026-07-27T01:00:00.000Z',
  callEligibility: DriverCallEligibility(
    canReceiveCalls: canReceiveCalls,
    reasonCode: canReceiveCalls ? 'READY' : 'OFFLINE',
  ),
);

CompatibleVehicle compatibleVehicle({
  int id = 11,
  String code = 'SEDAN',
  String name = 'Sedan',
  String plate = 'กข 1234',
  bool exact = true,
}) => CompatibleVehicle(
  driverVehicleId: id,
  vehicleTypeCode: code,
  vehicleTypeName: name,
  plateNumber: plate,
  isExactMatch: exact,
);

OpenCall openCall({
  String bookingNumber = 'TX209912319998',
  String origin = 'BKK',
  String destination = 'Pattaya Hotel',
  BookingLocation? pickupLocation,
  BookingLocation? destinationLocation,
  String vehicleMatchType = 'EXACT',
  bool isExactVehicleMatch = true,
  List<CompatibleVehicle>? compatibleVehicles,
  bool isUrgentRequest = false,
  int? negotiationId,
  int? minRequiredEtaMinutes,
  bool nameSignRequested = true,
  String? nameSignText = 'KIM FAMILY',
}) => OpenCall(
  bookingNumber: bookingNumber,
  status: 'OPEN',
  scheduledPickupAt: '2026-07-27T10:30:00.000+07:00',
  pickupDate: '2026-07-27',
  pickupTime: '10:30',
  origin: origin,
  destination: destination,
  pickupLocation: pickupLocation,
  destinationLocation: destinationLocation,
  serviceTypeCode: 'AIRPORT_PICKUP',
  serviceTypeName: 'Airport pickup',
  nameSignRequested: nameSignRequested,
  nameSignText: nameSignText,
  vehicleTypeCode: 'SEDAN',
  vehicleTypeName: 'Sedan',
  vehicleMatchType: vehicleMatchType,
  isExactVehicleMatch: isExactVehicleMatch,
  compatibleVehicles: compatibleVehicles ?? [compatibleVehicle()],
  passengerCount: 2,
  amount: 1200,
  currency: 'THB',
  customerPaymentAmount: 1200,
  customerPaymentCurrency: 'THB',
  customerPaymentMethod: 'PAY_DRIVER',
  companyCommissionAmount: 300,
  companyCommissionCurrency: 'THB',
  driverExpectedIncomeAmount: 900,
  driverExpectedIncomeCurrency: 'THB',
  luggage: const OpenCallLuggage(
    carriers20Inch: 1,
    carriers24InchPlus: 0,
    golfBags: 0,
    specialItems: null,
  ),
  isUrgentRequest: isUrgentRequest,
  negotiationId: negotiationId,
  minRequiredEtaMinutes: minRequiredEtaMinutes,
);

ClaimResult claimResult({String bookingNumber = 'TX209912319998'}) =>
    ClaimResult(
      bookingNumber: bookingNumber,
      status: 'DRIVER_ASSIGNED',
      booking: {'bookingNumber': bookingNumber, 'status': 'DRIVER_ASSIGNED'},
    );

class FakeDispatchReader implements DispatchReader {
  DriverDispatchStatus statusResult = dispatchStatus();
  DriverDispatchStatus onlineResult = dispatchStatus(
    online: true,
    canReceiveCalls: true,
    status: 'AVAILABLE',
  );
  DriverDispatchStatus offlineResult = dispatchStatus();
  OpenCallList openCallsResult = const OpenCallList(
    items: [],
    blockedReason: null,
    message: null,
  );
  ClaimResult claimResultValue = claimResult();
  UrgentCallLockResult urgentLockResult = const UrgentCallLockResult(
    bookingNumber: 'TX209912319997',
    negotiationId: 9,
    attemptId: 1,
    attemptNumber: 1,
    driverId: 7,
    status: 'LOCKED',
    lockExpiresAt: null,
  );
  UrgentCallEtaResult urgentEtaResult = const UrgentCallEtaResult(
    bookingNumber: 'TX209912319997',
    negotiationId: 9,
    attemptNumber: 1,
    driverId: 7,
    status: 'AWAITING_CUSTOMER',
    etaMinutes: 20,
    customerDecisionExpiresAt: null,
  );
  Object? statusError;
  Object? onlineError;
  Object? offlineError;
  Object? openCallsError;
  Object? claimError;
  Object? urgentLockError;
  Object? urgentEtaError;
  int statusCount = 0;
  int onlineCount = 0;
  int offlineCount = 0;
  int openCallsCount = 0;
  int claimCount = 0;
  int urgentLockCount = 0;
  int urgentEtaCount = 0;
  String? claimedBookingNumber;
  int? claimedVehicleId;
  String? lockedBookingNumber;
  String? etaBookingNumber;
  int? submittedEtaMinutes;

  @override
  Future<DriverDispatchStatus> getStatus() async {
    statusCount++;
    if (statusError case final error?) throw error;
    return statusResult;
  }

  @override
  Future<DriverDispatchStatus> goOnline() async {
    onlineCount++;
    if (onlineError case final error?) throw error;
    statusResult = onlineResult;
    return onlineResult;
  }

  @override
  Future<DriverDispatchStatus> goOffline() async {
    offlineCount++;
    if (offlineError case final error?) throw error;
    statusResult = offlineResult;
    return offlineResult;
  }

  @override
  Future<OpenCallList> getOpenCalls() async {
    openCallsCount++;
    if (openCallsError case final error?) throw error;
    return openCallsResult;
  }

  @override
  Future<ClaimResult> claimOpenCall(
    String bookingNumber,
    int driverVehicleId,
  ) async {
    claimCount++;
    claimedBookingNumber = bookingNumber;
    claimedVehicleId = driverVehicleId;
    if (claimError case final error?) throw error;
    return claimResultValue;
  }

  @override
  Future<UrgentCallLockResult> lockUrgentCall(String bookingNumber) async {
    urgentLockCount++;
    lockedBookingNumber = bookingNumber;
    if (urgentLockError case final error?) throw error;
    return urgentLockResult;
  }

  @override
  Future<UrgentCallEtaResult> submitUrgentEta(
    String bookingNumber,
    int etaMinutes,
  ) async {
    urgentEtaCount++;
    etaBookingNumber = bookingNumber;
    submittedEtaMinutes = etaMinutes;
    if (urgentEtaError case final error?) throw error;
    return urgentEtaResult;
  }
}

class FakeDriverSocketConnection implements DriverSocketConnection {
  final StreamController<DriverSocketEvent> _controller =
      StreamController<DriverSocketEvent>.broadcast();

  int connectCount = 0;
  int disconnectCount = 0;
  bool connected = false;

  @override
  Stream<DriverSocketEvent> get events => _controller.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async {
    connectCount++;
    connected = true;
  }

  @override
  void disconnect() {
    disconnectCount++;
    connected = false;
  }

  void emit(DriverSocketEventType type, [Map<String, dynamic>? payload]) {
    _controller.add(DriverSocketEvent(type, payload ?? const {}));
  }
}

DriverProfile driverProfile({
  String name = 'Somchai',
  String phone = '+66812345678',
  String email = 'driver@example.com',
  String? avatarUrl,
  DriverProfileVehicle? vehicle = const DriverProfileVehicle(
    typeCode: 'SEDAN',
    typeName: 'Sedan',
    modelName: 'Camry',
    plateNumber: 'กข 1234',
    color: 'White',
    year: 2022,
  ),
}) => DriverProfile(
  name: name,
  phone: phone,
  email: email,
  avatarUrl: avatarUrl,
  vehicle: vehicle,
);

DriverVehicle driverVehicle({
  int id = 11,
  String approvalStatus = 'APPROVED',
  bool isPrimary = true,
  String? rejectionReason,
}) => DriverVehicle(
  id: id,
  vehicleTypeId: 1,
  vehicleTypeCode: 'SEDAN',
  vehicleTypeName: 'Sedan',
  plateNumber: 'กข 1234',
  modelName: 'Camry',
  color: 'White',
  isPrimary: isPrimary,
  isActive: approvalStatus == 'APPROVED',
  approvalStatus: approvalStatus,
  rejectionReason: rejectionReason,
  documentCounts: const VehicleDocumentCounts(
    vehiclePhotos: 3,
    insuranceCertificate: 1,
    vehicleRegistration: 1,
    taxCertificate: 0,
  ),
);

class FakeAccountApi implements AccountDataSource {
  DriverProfile profile = driverProfile();
  RatingSummary rating = const RatingSummary(
    averageRating: 4.8,
    reviewCount: 12,
  );
  List<DriverVehicle> vehicles = [driverVehicle()];
  List<VehicleTypeOption> vehicleTypes = const [
    VehicleTypeOption(id: 1, code: 'SEDAN', name: 'Sedan'),
    VehicleTypeOption(id: 2, code: 'SUV', name: 'SUV'),
  ];
  Object? error;
  Object? vehicleCreateError;
  Object? vehiclePhotoError;
  int profileCount = 0;
  int ratingCount = 0;
  int vehiclesCount = 0;
  int updateCount = 0;
  int avatarCount = 0;
  int vehiclePhotoCount = 0;
  int createVehicleCount = 0;
  int assetLoadCount = 0;
  String? loadedAssetPath;
  List<int> assetBytes = const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  Map<String, dynamic>? lastChanges;
  VehicleCreateRequest? lastVehicleRequest;

  void _throwIfNeeded([Object? specific]) {
    final value = specific ?? error;
    if (value != null) throw value;
  }

  @override
  Future<DriverProfile> getProfile() async {
    profileCount++;
    _throwIfNeeded();
    return profile;
  }

  @override
  Future<RatingSummary> getRatingSummary() async {
    ratingCount++;
    _throwIfNeeded();
    return rating;
  }

  @override
  Future<List<DriverVehicle>> getVehicles() async {
    vehiclesCount++;
    _throwIfNeeded();
    return vehicles;
  }

  @override
  Future<List<VehicleTypeOption>> getVehicleTypes() async {
    _throwIfNeeded();
    return vehicleTypes;
  }

  @override
  Future<DriverProfile> updateProfile(Map<String, dynamic> changes) async {
    updateCount++;
    lastChanges = Map.of(changes);
    _throwIfNeeded();
    profile = DriverProfile(
      name: changes['name'] as String? ?? profile.name,
      phone: changes['phone'] as String? ?? profile.phone,
      email: profile.email,
      avatarUrl: profile.avatarUrl,
      vehicle: profile.vehicle,
    );
    return profile;
  }

  @override
  Future<void> uploadAvatar(AccountUploadFile file) async {
    avatarCount++;
    _throwIfNeeded();
  }

  @override
  Future<void> uploadVehiclePhoto(AccountUploadFile file) async {
    vehiclePhotoCount++;
    _throwIfNeeded(vehiclePhotoError);
  }

  @override
  Future<DriverVehicle> createVehicle(VehicleCreateRequest request) async {
    createVehicleCount++;
    lastVehicleRequest = request;
    _throwIfNeeded(vehicleCreateError);
    return driverVehicle(id: 99, approvalStatus: 'PENDING', isPrimary: false);
  }

  @override
  Future<List<int>> loadAsset(String path) async {
    assetLoadCount++;
    loadedAssetPath = path;
    _throwIfNeeded();
    return assetBytes;
  }
}

Map<String, dynamic> settlementJson({
  String bookingNumber = 'TX209912310001',
  String status = 'SETTLEMENT_PENDING',
  String commissionStatus = 'DUE',
  bool blocksNewCalls = false,
  String? dueAt = '2026-07-30T23:59:00.000+07:00',
  String? receiptStatus,
  String? receiptUrl,
  String? rejectionReason,
  Map<String, dynamic>? paymentInstructions,
}) => {
  'bookingNumber': bookingNumber,
  'status': status,
  'pickupDate': '2026-07-27',
  'pickupTime': '09:30',
  'origin': 'BKK',
  'destination': 'Pattaya',
  'completedAt': '2026-07-27T12:30:00.000+07:00',
  'commissionAmount': 300,
  'commissionCurrency': 'THB',
  'customerPaymentAmount': 1200,
  'customerPaymentCurrency': 'THB',
  'customerTotalAmount': 1200,
  'customerTotalCurrency': 'THB',
  'companyCommissionAmount': 300,
  'companyCommissionCurrency': 'THB',
  'driverExpectedIncomeAmount': 900,
  'driverExpectedIncomeCurrency': 'THB',
  'currency': 'THB',
  'commissionStatus': commissionStatus,
  'blocksNewCalls': blocksNewCalls,
  'dueAt': dueAt,
  'receiptStatus': receiptStatus,
  'receiptSubmittedAt': null,
  'receiptUploadedAt': null,
  'rejectionReason': rejectionReason,
  'approvalMode': null,
  'approvalNote': null,
  'approvedByUserId': null,
  'approvalRecordedAt': null,
  'receiptMissingAtApproval': false,
  'receiptFileId': receiptUrl == null ? null : 99,
  'receiptUrl': receiptUrl,
  'paymentInstructions': paymentInstructions,
};

SettlementItem settlementItem({
  String bookingNumber = 'TX209912310001',
  String commissionStatus = 'DUE',
  bool blocksNewCalls = false,
  String? receiptUrl,
  String? rejectionReason,
  Map<String, dynamic>? paymentInstructions,
}) => SettlementItem.fromJson(
  settlementJson(
    bookingNumber: bookingNumber,
    commissionStatus: commissionStatus,
    blocksNewCalls: blocksNewCalls,
    receiptUrl: receiptUrl,
    rejectionReason: rejectionReason,
    paymentInstructions: paymentInstructions,
  ),
);

class FakeSettlementApi implements SettlementDataSource {
  List<SettlementItem> items = [settlementItem()];
  SettlementItem detail = settlementItem(
    paymentInstructions: const {
      'bankName': 'Kasikorn',
      'accountName': 'T-Ride Co.',
      'accountNumber': '123-4-56789-0',
      'promptPayNumber': '0999999999',
      'promptPayQrImageUrl': '/api/v1/files/promptpay.png',
    },
  );
  Object? listError;
  Object? detailError;
  Object? uploadError;
  Object? downloadError;
  int listCount = 0;
  int detailCount = 0;
  int uploadCount = 0;
  int downloadCount = 0;
  String? requestedBookingNumber;
  String? uploadedBookingNumber;
  SettlementUploadFile? uploadedFile;
  String? downloadedPath;
  List<int> downloadBytes = const [0x89, 0x50, 0x4e, 0x47];

  @override
  Future<List<SettlementItem>> listSettlements() async {
    listCount++;
    if (listError case final error?) throw error;
    return items;
  }

  @override
  Future<SettlementItem> getSettlement(String bookingNumber) async {
    detailCount++;
    requestedBookingNumber = bookingNumber;
    if (detailError case final error?) throw error;
    return detail;
  }

  @override
  Future<SettlementItem> uploadReceipt(
    String bookingNumber,
    SettlementUploadFile file,
  ) async {
    uploadCount++;
    uploadedBookingNumber = bookingNumber;
    uploadedFile = file;
    if (uploadError case final error?) throw error;
    detail = settlementItem(
      bookingNumber: bookingNumber,
      commissionStatus: 'RECEIPT_SUBMITTED',
      receiptUrl: '/api/v1/driver/settlements/$bookingNumber/receipt',
      paymentInstructions: const {
        'bankName': 'Kasikorn',
        'accountName': 'T-Ride Co.',
        'accountNumber': '123-4-56789-0',
      },
    );
    return detail;
  }

  @override
  Future<List<int>> downloadReceipt(String path) async {
    downloadCount++;
    downloadedPath = path;
    if (downloadError case final error?) throw error;
    return downloadBytes;
  }
}
