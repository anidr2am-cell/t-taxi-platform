class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final description = json['description'] as String? ?? '';
    final structured = json['structured_formatting'] as Map<String, dynamic>?;
    final main = json['mainText'] as String?
        ?? json['main_text'] as String?
        ?? structured?['main_text'] as String?
        ?? _splitDescription(description).main;
    final secondary = json['secondaryText'] as String?
        ?? json['secondary_text'] as String?
        ?? structured?['secondary_text'] as String?
        ?? _splitDescription(description).secondary;

    return PlacePrediction(
      placeId: json['placeId'] as String? ?? json['place_id'] as String? ?? '',
      mainText: main,
      secondaryText: secondary,
    );
  }

  static ({String main, String secondary}) _splitDescription(String description) {
    final parts = description.split(',');
    if (parts.isEmpty) return (main: description, secondary: '');
    if (parts.length == 1) return (main: parts.first.trim(), secondary: '');
    return (
      main: parts.first.trim(),
      secondary: parts.sublist(1).join(',').trim(),
    );
  }
}

class PlaceDetails {
  final String placeId;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;

  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>?;
    final source = result ?? json;

    return PlaceDetails(
      placeId: source['placeId'] as String? ?? source['place_id'] as String? ?? '',
      name: source['name'] as String? ?? '',
      address: source['formattedAddress'] as String?
          ?? source['formatted_address'] as String?
          ?? source['address'] as String?
          ?? '',
      latitude: _toDouble(source['lat'] ?? source['latitude']),
      longitude: _toDouble(source['lng'] ?? source['longitude']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
