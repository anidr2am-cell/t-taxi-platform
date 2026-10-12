String formatBangkokDateTime(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final bangkok = parsed.toUtc().add(const Duration(hours: 7));
  String two(int number) => number.toString().padLeft(2, '0');
  return '${bangkok.year}-${two(bangkok.month)}-${two(bangkok.day)} '
      '${two(bangkok.hour)}:${two(bangkok.minute)}';
}
