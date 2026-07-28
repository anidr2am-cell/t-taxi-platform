import 'app/app_bootstrap.dart';
import 'config/app_environment.dart';

Future<void> main() async {
  await runDriverApp(AppEnvironment.dev);
}
