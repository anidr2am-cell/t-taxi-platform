/// Maps errors to safe user-visible text without exposing exception types.
String userFacingError(
  Object err, {
  String? fallback,
}) {
  try {
    final dynamic typed = err;
    final message = typed.message;
    if (message is String) {
      final trimmed = message.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  } catch (_) {}

  final text = err.toString().trim();
  if (text.isEmpty ||
      text.startsWith('Instance of') ||
      text.contains('Stack trace') ||
      text.contains('failed host lookup') ||
      text.contains('SocketException') ||
      text.contains('Failed to fetch') ||
      text.contains('ClientException') ||
      text.contains('Connection refused') ||
      text.contains('NetworkError') ||
      text.contains('XMLHttpRequest')) {
    return fallback ?? 'ui_generic_error';
  }
  return text;
}
