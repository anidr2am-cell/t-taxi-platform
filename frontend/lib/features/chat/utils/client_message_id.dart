int _clientMessageSequence = 0;

/// Client-side chat idempotency key without [Random] (safe on Flutter Web).
String newClientMessageId(String prefix) {
  _clientMessageSequence += 1;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_clientMessageSequence';
}
