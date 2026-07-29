class FlightEndpointInfo {
  const FlightEndpointInfo({
    this.airportCode,
    this.airportName,
    this.scheduledAt,
    this.estimatedAt,
  });

  final String? airportCode;
  final String? airportName;
  final String? scheduledAt;
  final String? estimatedAt;

  factory FlightEndpointInfo.fromJson(Map<String, dynamic> json) {
    return FlightEndpointInfo(
      airportCode: json['airportCode'] as String?,
      airportName: json['airportName'] as String?,
      scheduledAt: json['scheduledAt'] as String?,
      estimatedAt: json['estimatedAt'] as String?,
    );
  }
}

class FlightSearchResult {
  const FlightSearchResult({
    required this.flightNumber,
    this.airlineName,
    required this.departure,
    required this.arrival,
    this.status,
    this.delayMinutes,
  });

  final String flightNumber;
  final String? airlineName;
  final FlightEndpointInfo departure;
  final FlightEndpointInfo arrival;
  final String? status;
  final int? delayMinutes;

  factory FlightSearchResult.fromJson(Map<String, dynamic> json) {
    return FlightSearchResult(
      flightNumber: json['flightNumber'] as String? ?? '',
      airlineName: json['airlineName'] as String?,
      departure: FlightEndpointInfo.fromJson(
        Map<String, dynamic>.from(json['departure'] as Map? ?? {}),
      ),
      arrival: FlightEndpointInfo.fromJson(
        Map<String, dynamic>.from(json['arrival'] as Map? ?? {}),
      ),
      status: json['status'] as String?,
      delayMinutes: (json['delayMinutes'] as num?)?.toInt(),
    );
  }

  String routeLabel() {
    final from = departure.airportCode ?? departure.airportName ?? '—';
    final to = arrival.airportCode ?? arrival.airportName ?? '—';
    return '$from → $to';
  }
}
