import '../../../core/network/api_exception.dart';
import '../../auth/services/customer_api_errors.dart';
import '../../auth/services/customer_session.dart';

class MileageApiException implements Exception {
  const MileageApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MileageBalanceResult {
  const MileageBalanceResult({required this.balance});

  final int balance;
}

class MileageTransactionItem {
  const MileageTransactionItem({
    required this.date,
    required this.amount,
    required this.type,
    required this.bookingNumber,
  });

  final String? date;
  final int amount;
  final String type;
  final String bookingNumber;

  factory MileageTransactionItem.fromJson(Map<String, dynamic> json) {
    return MileageTransactionItem(
      date: json['date'] as String?,
      amount: json['amount'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      bookingNumber: json['bookingNumber'] as String? ?? '',
    );
  }
}

class MileageTransactionsPageResult {
  const MileageTransactionsPageResult({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<MileageTransactionItem> items;
  final int page;
  final int limit;
  final int total;
}

class MileageApiService {
  MileageApiService({
    CustomerSession? session,
  }) : _session = session ?? CustomerSession();

  final CustomerSession _session;

  Future<MileageBalanceResult> getMileageBalance() async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const MileageApiException('Authentication required');
    }

    try {
      final decoded = await _session.apiClient.getJson(
        '/customer/mileage',
        bearerToken: session.accessToken,
      );
      final data = decoded['data'] as Map?;
      if (data == null) {
        throw const MileageApiException('Invalid mileage response');
      }
      return MileageBalanceResult(
        balance: data['balance'] as int? ?? 0,
      );
    } on ApiException catch (error) {
      throw MileageApiException(
        customerApiErrorMessage(error, fallback: 'Unable to load mileage balance'),
        statusCode: error.statusCode,
      );
    }
  }

  Future<MileageTransactionsPageResult> getTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const MileageApiException('Authentication required');
    }

    try {
      final decoded = await _session.apiClient.getJson(
        '/customer/mileage/transactions',
        bearerToken: session.accessToken,
        queryParameters: {
          'page': '$page',
          'limit': '$limit',
        },
      );
      final data = decoded['data'] as Map?;
      if (data == null) {
        throw const MileageApiException('Invalid mileage transactions response');
      }
      final rawItems = data['data'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                (item) => MileageTransactionItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : <MileageTransactionItem>[];

      return MileageTransactionsPageResult(
        items: items,
        page: data['page'] as int? ?? page,
        limit: data['limit'] as int? ?? limit,
        total: data['total'] as int? ?? items.length,
      );
    } on ApiException catch (error) {
      throw MileageApiException(
        customerApiErrorMessage(
          error,
          fallback: 'Unable to load mileage transactions',
        ),
        statusCode: error.statusCode,
      );
    }
  }
}
