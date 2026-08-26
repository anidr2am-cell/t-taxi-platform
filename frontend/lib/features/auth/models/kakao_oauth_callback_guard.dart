import 'dart:convert';

import 'social_login_return_context.dart';

enum KakaoOAuthCallbackOutcome { pending, success, failure }

class KakaoOAuthCallbackGuardRecord {
  const KakaoOAuthCallbackGuardRecord({
    required this.code,
    required this.outcome,
    this.returnContext,
  });

  final String code;
  final KakaoOAuthCallbackOutcome outcome;
  final SocialLoginReturnContext? returnContext;

  bool get isSuccess => outcome == KakaoOAuthCallbackOutcome.success;

  bool get isFailure => outcome == KakaoOAuthCallbackOutcome.failure;

  bool get isPending => outcome == KakaoOAuthCallbackOutcome.pending;
}

abstract class KakaoOAuthCallbackGuardStorage {
  static const processedCodeKey = 'kakao_processed_code';
  static const processedOutcomeKey = 'kakao_processed_outcome';
  static const processedReturnContextKey = 'kakao_processed_return_context';

  Future<KakaoOAuthCallbackGuardRecord?> load();

  Future<void> save(KakaoOAuthCallbackGuardRecord record);

  Future<void> clear();
}

KakaoOAuthCallbackGuardRecord? decodeKakaoOAuthCallbackGuardRecord(
  Map<String, String> values,
) {
  final code = values[KakaoOAuthCallbackGuardStorage.processedCodeKey]?.trim();
  if (code == null || code.isEmpty) {
    return null;
  }

  final outcomeRaw =
      values[KakaoOAuthCallbackGuardStorage.processedOutcomeKey]?.trim();
  KakaoOAuthCallbackOutcome? outcome;
  for (final candidate in KakaoOAuthCallbackOutcome.values) {
    if (candidate.name == outcomeRaw) {
      outcome = candidate;
      break;
    }
  }
  if (outcome == null) {
    return null;
  }

  SocialLoginReturnContext? returnContext;
  final returnContextRaw =
      values[KakaoOAuthCallbackGuardStorage.processedReturnContextKey];
  if (returnContextRaw != null && returnContextRaw.isNotEmpty) {
    try {
      returnContext = SocialLoginReturnContext.fromJson(
        Map<String, dynamic>.from(jsonDecode(returnContextRaw) as Map),
      );
    } catch (_) {
      returnContext = null;
    }
  }

  return KakaoOAuthCallbackGuardRecord(
    code: code,
    outcome: outcome,
    returnContext: returnContext,
  );
}

Map<String, String> encodeKakaoOAuthCallbackGuardRecord(
  KakaoOAuthCallbackGuardRecord record,
) {
  final values = <String, String>{
    KakaoOAuthCallbackGuardStorage.processedCodeKey: record.code,
    KakaoOAuthCallbackGuardStorage.processedOutcomeKey: record.outcome.name,
  };
  if (record.returnContext != null) {
    values[KakaoOAuthCallbackGuardStorage.processedReturnContextKey] =
        jsonEncode(record.returnContext!.toJson());
  }
  return values;
}
