class DriverApplicationUploadLimits {
  const DriverApplicationUploadLimits._();

  static const int bytesPerMb = 1024 * 1024;
  static const int perFileHardLimitBytes = 10 * bytesPerMb;
  static const int totalWarningBytes = 35 * bytesPerMb;
  static const int totalHardLimitBytes = 42 * bytesPerMb;

  static const int smallImageBytes = 2 * bytesPerMb;

  static const int vehicleMaxLongEdge = 1920;
  static const int vehicleJpegQuality = 82;

  static const int documentMaxLongEdge = 2560;
  static const int documentJpegQuality = 88;
}
