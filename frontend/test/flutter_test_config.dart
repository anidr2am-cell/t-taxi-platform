import 'dart:async';

import 'package:frontend/theme/app_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppFonts.disableRuntimeFetchingForTests();
  await testMain();
}
