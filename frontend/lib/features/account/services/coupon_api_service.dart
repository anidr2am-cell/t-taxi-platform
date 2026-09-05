import '../../../core/network/api_exception.dart';
import '../../auth/services/customer_api_errors.dart';
import '../../auth/services/customer_session.dart';

class CouponApiException implements Exception {
  const CouponApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CustomerCouponItem {
  const CustomerCouponItem({
    required this.id,
    required this.title,
    required this.discountAmount,
    required this.status,
    this.issuedAt,
    this.usedAt,
    this.bookingNumber,
  });

  final int id;
  final String title;
  final int discountAmount;
  final String status;
  final String? issuedAt;
  final String? usedAt;
  final String? bookingNumber;

  bool get isAvailable => status == 'AVAILABLE';

  factory CustomerCouponItem.fromJson(Map<String, dynamic> json) {
    return CustomerCouponItem(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      discountAmount: json['discountAmount'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      issuedAt: json['issuedAt'] as String?,
      usedAt: json['usedAt'] as String?,
      bookingNumber: json['bookingNumber'] as String?,
    );
  }
}

class CouponApiService {
  CouponApiService({CustomerSession? session})
      : _session = session ?? CustomerSession();

  final CustomerSession _session;

  Future<List<CustomerCouponItem>> listCoupons() async {
    final session = await _session.tokenStorage.loadSession();
    if (session == null) {
      throw const CouponApiException('Authentication required');
    }

    try {
      final decoded = await _session.apiClient.getJson(
        '/customer/coupons',
        bearerToken: session.accessToken,
      );
      final data = decoded['data'];
      if (data is! List) {
        throw const CouponApiException('Invalid coupon response');
      }
      return data
          .whereType<Map>()
          .map((item) => CustomerCouponItem.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
    } on ApiException catch (error) {
      throw CouponApiException(
        customerApiErrorMessage(error, fallback: 'Unable to load coupons'),
        statusCode: error.statusCode,
      );
    }
  }
}
