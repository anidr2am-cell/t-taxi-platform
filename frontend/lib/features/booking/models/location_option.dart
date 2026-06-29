import 'place_prediction.dart';

enum LocationKind { airport, place, golf, city }

class LocationOption {
  final String id;
  final String displayName;
  final LocationKind kind;
  final String? code;
  final String? placeId;
  final String? region;
  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;

  const LocationOption({
    required this.id,
    required this.displayName,
    required this.kind,
    this.code,
    this.placeId,
    this.region,
    this.name,
    this.address,
    this.latitude,
    this.longitude,
  });

  factory LocationOption.fromPlaceDetails(PlaceDetails details) {
    final label = details.name.isNotEmpty ? details.name : details.address;
    final internalCode = _knownInternalCodeForText(
      '${details.name} ${details.address}',
    );
    return LocationOption(
      id: 'place:${details.placeId}',
      displayName: label,
      kind: LocationKind.place,
      code: internalCode,
      placeId: details.placeId,
      name: details.name,
      address: details.address,
      latitude: details.latitude,
      longitude: details.longitude,
    );
  }

  static String? _knownInternalCodeForText(String value) {
    final text = value.toUpperCase();
    final compact = text.replaceAll(RegExp(r'[^A-Z0-9\u0E00-\u0E7F\uAC00-\uD7AF\u3040-\u30FF\u3400-\u9FFF]'), '');
    if (compact.contains('PATTAYA') ||
        compact.contains('파타야') ||
        compact.contains('เมืองพัทยา') ||
        compact.contains('พัทยา') ||
        compact.contains('芭堤雅') ||
        compact.contains('パタヤ') ||
        compact.contains('パッタヤ')) {
      return 'PATTAYA';
    }
    if (compact.contains('BANGKOK') ||
        compact.contains('방콕') ||
        compact.contains('กรุงเทพ') ||
        compact.contains('กรุงเทพมหานคร') ||
        compact.contains('曼谷') ||
        compact.contains('バンコク')) {
      return 'BANGKOK';
    }
    if (compact.contains('BKK') ||
        compact.contains('SUVARNABHUMI') ||
        compact.contains('สุวรรณภูมิ') ||
        compact.contains('スワンナプーム') ||
        compact.contains('素万那普')) {
      return 'BKK';
    }
    if (compact.contains('DMK') ||
        compact.contains('DONMUEANG') ||
        compact.contains('DONMUANG') ||
        compact.contains('ดอนเมือง') ||
        compact.contains('ドンムアン') ||
        compact.contains('廊曼')) {
      return 'DMK';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'kind': kind.name,
        'code': code,
        'placeId': placeId,
        'region': region,
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory LocationOption.fromJson(Map<String, dynamic> json) {
    return LocationOption(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      kind: LocationKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => LocationKind.place,
      ),
      code: json['code'] as String?,
      placeId: json['placeId'] as String?,
      region: json['region'] as String?,
      name: json['name'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
