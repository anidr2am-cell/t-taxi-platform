DateTime? parseBackendServiceDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final trimmed = raw.trim();
  final withoutMs = trimmed.replaceFirst(RegExp(r'\.\d+$'), '');
  final iso = withoutMs.contains('T')
      ? withoutMs
      : withoutMs.replaceFirst(' ', 'T');
  return DateTime.parse('${iso}Z').toLocal();
}

String formatCountdownMmSs(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
