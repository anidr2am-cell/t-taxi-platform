import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/models/auth_session.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/services/auth_token_storage.dart';
import 'package:frontend/features/driver/services/driver_token_storage.dart';
import 'package:frontend/features/auth/services/customer_session.dart';
import 'package:frontend/features/driver/services/driver_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DriverSession.resetSharedForTesting();
    CustomerSession.resetSharedForTesting();
  });

  test('driver and customer token keys stay isolated in SharedPreferences', () async {
    final driverStorage = DriverTokenStorage();
    await driverStorage.saveLoginSession(
      accessToken: 'driver-access',
      refreshToken: 'driver-refresh',
      expiresIn: 3600,
      displayName: 'Driver One',
    );

    final customerStorage = AuthTokenStorage();
    await customerStorage.saveSession(
      AuthSession(
        accessToken: 'customer-access',
        refreshToken: 'customer-refresh',
        user: AuthUser(
          id: 1,
          role: 'USER',
          isActive: true,
          name: 'Customer',
        ),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DriverTokenStorage.accessTokenKey), 'driver-access');
    expect(prefs.getString(DriverTokenStorage.refreshTokenKey), 'driver-refresh');
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'customer-access');
    expect(prefs.getString(AuthTokenStorage.refreshTokenKey), 'customer-refresh');

    await driverStorage.clear();
    expect(prefs.getString(DriverTokenStorage.accessTokenKey), isNull);
    expect(prefs.getString(AuthTokenStorage.accessTokenKey), 'customer-access');
    expect(prefs.getString(AuthTokenStorage.refreshTokenKey), 'customer-refresh');
  });
}
