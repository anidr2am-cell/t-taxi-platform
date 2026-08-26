import '../models/line_oauth_state_storage.dart';
import 'line_oauth_state_storage_prefs.dart';

LineOAuthStateStorage createLineOAuthStateStorage() {
  return SharedPreferencesLineOAuthStateStorage();
}
