import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';

class HomeBannerItem {
  const HomeBannerItem({
    required this.id,
    required this.displayOrder,
    required this.imageUrl,
  });

  final int id;
  final int displayOrder;
  final String imageUrl;

  factory HomeBannerItem.fromJson(Map<String, dynamic> json) {
    return HomeBannerItem(
      id: json['id'] as int? ?? 0,
      displayOrder: json['displayOrder'] as int? ?? 0,
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }

  String resolveImageUrl() {
    final path = imageUrl.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }
}

class HomeBannerApiService {
  HomeBannerApiService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient(baseUrl: AppConfig.apiBaseUrl);

  final ApiClient _apiClient;

  Future<List<HomeBannerItem>> listActiveBanners() async {
    final decoded = await _apiClient.getJson('/public/home-banners');
    final data = decoded['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => HomeBannerItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}
