import 'package:flutter/material.dart';

import 'pages/driver_login_page.dart';
import 'driver_ux.dart';

void driverRedirectToLogin(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const DriverLoginPage()),
    (_) => false,
  );
}

void driverHandleApiError(BuildContext context, Object err) {
  if (driverIsAuthError(err)) {
    driverRedirectToLogin(context);
  }
}
