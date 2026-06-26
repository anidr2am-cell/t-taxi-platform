class VehicleRecommendation {
  final String? recommendedVehicle;
  final List<String> selectableVehicles;
  final bool multipleVehicles;
  final String message;

  const VehicleRecommendation({
    required this.recommendedVehicle,
    required this.selectableVehicles,
    required this.multipleVehicles,
    required this.message,
  });

  factory VehicleRecommendation.fromJson(Map<String, dynamic> json) {
    return VehicleRecommendation(
      recommendedVehicle: json['recommendedVehicle'] as String?,
      selectableVehicles: (json['selectableVehicles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      multipleVehicles: json['multipleVehicles'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}
