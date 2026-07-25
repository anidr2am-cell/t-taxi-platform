class DriverVehicleItem {
  const DriverVehicleItem({
    required this.id,
    required this.vehicleTypeId,
    required this.vehicleTypeCode,
    required this.vehicleTypeName,
    required this.plateNumber,
    required this.isPrimary,
    required this.isActive,
    required this.approvalStatus,
    this.modelName,
    this.color,
    this.rejectionReason,
  });

  final int id;
  final int vehicleTypeId;
  final String vehicleTypeCode;
  final String vehicleTypeName;
  final String plateNumber;
  final String? modelName;
  final String? color;
  final bool isPrimary;
  final bool isActive;
  final String approvalStatus;
  final String? rejectionReason;

  factory DriverVehicleItem.fromJson(Map<String, dynamic> json) {
    return DriverVehicleItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      vehicleTypeId: (json['vehicleTypeId'] as num?)?.toInt() ?? 0,
      vehicleTypeCode: json['vehicleTypeCode'] as String? ?? '',
      vehicleTypeName: json['vehicleTypeName'] as String? ?? '',
      plateNumber: json['plateNumber'] as String? ?? '',
      modelName: json['modelName'] as String?,
      color: json['color'] as String?,
      isPrimary: json['isPrimary'] == true,
      isActive: json['isActive'] == true,
      approvalStatus: (json['approvalStatus'] as String? ?? 'APPROVED')
          .toUpperCase(),
      rejectionReason: json['rejectionReason'] as String?,
    );
  }
}
