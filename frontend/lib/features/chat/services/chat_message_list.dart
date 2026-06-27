/// Helpers for chat message deduplication across REST and Socket.IO.
class ChatMessageList {
  static bool containsMessage(List<dynamic> messages, Map<String, dynamic> candidate) {
    final messageId = candidate['messageId'];
    final clientMessageId = candidate['clientMessageId'] as String?;
    for (final item in messages) {
      final map = item as Map<String, dynamic>;
      if (messageId != null && map['messageId'] == messageId) return true;
      if (clientMessageId != null &&
          clientMessageId.isNotEmpty &&
          map['clientMessageId'] == clientMessageId) {
        return true;
      }
    }
    return false;
  }

  static List<dynamic> upsert(List<dynamic> messages, Map<String, dynamic> candidate) {
    final messageId = candidate['messageId'];
    final clientMessageId = candidate['clientMessageId'] as String?;
    final next = <dynamic>[];
    var replaced = false;
    for (final item in messages) {
      final map = Map<String, dynamic>.from(item as Map);
      final idMatch = messageId != null && map['messageId'] == messageId;
      final clientMatch = clientMessageId != null &&
          clientMessageId.isNotEmpty &&
          map['clientMessageId'] == clientMessageId;
      if (idMatch || clientMatch) {
        next.add(candidate);
        replaced = true;
      } else {
        next.add(map);
      }
    }
    if (!replaced) next.add(candidate);
    return next;
  }

  static List<dynamic> mergeHistory(List<dynamic> existing, List<dynamic> fromRest) {
    final merged = <dynamic>[];
    for (final item in fromRest.reversed) {
      final map = Map<String, dynamic>.from(item as Map);
      if (!containsMessage(merged, map)) {
        merged.add(map);
      }
    }
    for (final item in existing) {
      final map = Map<String, dynamic>.from(item as Map);
      if (!containsMessage(merged, map)) {
        merged.add(map);
      }
    }
    merged.sort((a, b) {
      final am = a as Map<String, dynamic>;
      final bm = b as Map<String, dynamic>;
      final aid = am['messageId'] as int? ?? 0;
      final bid = bm['messageId'] as int? ?? 0;
      return aid.compareTo(bid);
    });
    return merged;
  }
}
