const blockedSchemes = {
  'javascript',
  'data',
  'file',
  'vbscript',
};

const allowedSchemes = {
  'https',
  'http',
  'line',
  'kakaotalk',
  'whatsapp',
};

bool isAllowedContactChannelUrl(Uri uri, {bool allowHttp = false}) {
  final scheme = uri.scheme.toLowerCase();
  if (blockedSchemes.contains(scheme)) return false;
  if (!allowedSchemes.contains(scheme)) return false;
  if (scheme == 'http' && !allowHttp) return false;
  return true;
}

Uri? parseAllowedContactChannelUrl(String raw, {bool allowHttp = false}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.isEmpty) return null;
  if (!isAllowedContactChannelUrl(uri, allowHttp: allowHttp)) return null;
  return uri;
}

bool allowHttpContactUrlsForEnvironment() {
  const env = String.fromEnvironment('CONTACT_ALLOW_HTTP_URLS', defaultValue: '');
  if (env == 'true' || env == '1') return true;
  return false;
}
