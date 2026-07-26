import 'dispatch_api.dart';
import 'dispatch_models.dart';

abstract interface class DispatchReader {
  Future<DriverDispatchStatus> getStatus();
  Future<DriverDispatchStatus> goOnline();
  Future<DriverDispatchStatus> goOffline();
  Future<OpenCallList> getOpenCalls();
  Future<ClaimResult> claimOpenCall(String bookingNumber, int driverVehicleId);
  Future<UrgentCallLockResult> lockUrgentCall(String bookingNumber);
  Future<UrgentCallEtaResult> submitUrgentEta(
    String bookingNumber,
    int etaMinutes,
  );
}

class DispatchRepository implements DispatchReader {
  const DispatchRepository(this._api);

  final DispatchDataSource _api;

  @override
  Future<DriverDispatchStatus> getStatus() async =>
      DriverDispatchStatus.fromEnvelope(await _api.getStatus());

  @override
  Future<DriverDispatchStatus> goOnline() async =>
      DriverDispatchStatus.fromEnvelope(await _api.goOnline());

  @override
  Future<DriverDispatchStatus> goOffline() async =>
      DriverDispatchStatus.fromEnvelope(await _api.goOffline());

  @override
  Future<OpenCallList> getOpenCalls() async =>
      OpenCallList.fromEnvelope(await _api.getOpenCalls());

  @override
  Future<ClaimResult> claimOpenCall(
    String bookingNumber,
    int driverVehicleId,
  ) async => ClaimResult.fromEnvelope(
    await _api.claimOpenCall(bookingNumber, driverVehicleId),
  );

  @override
  Future<UrgentCallLockResult> lockUrgentCall(String bookingNumber) async =>
      UrgentCallLockResult.fromEnvelope(
        await _api.lockUrgentCall(bookingNumber),
      );

  @override
  Future<UrgentCallEtaResult> submitUrgentEta(
    String bookingNumber,
    int etaMinutes,
  ) async => UrgentCallEtaResult.fromEnvelope(
    await _api.submitUrgentEta(bookingNumber, etaMinutes),
  );
}
