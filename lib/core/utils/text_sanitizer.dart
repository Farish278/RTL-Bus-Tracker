String sanitizeUiText(String value) {
  var text = value;
  const replacements = <String, String>{
    'â€¢': '•',
    'Ã¢â‚¬Â¢': '•',
    'Â°': '°',
    'Ã‚Â°': '°',
    '&bull;': '•',
    '&deg;': '°',
  };
  replacements.forEach((bad, good) {
    text = text.replaceAll(bad, good);
  });
  return text.trim();
}

String? sanitizeNullableUiText(String? value) {
  if (value == null) return null;
  final normalized = sanitizeUiText(value);
  return normalized.isEmpty ? null : normalized;
}
