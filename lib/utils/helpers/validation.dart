class Validation {
  static String? required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;
  static String? name(String? value) => value == null || value.trim().length < 2
      ? 'Enter at least two characters'
      : value.trim().length > 120
      ? 'Use 120 characters or fewer'
      : null;
  static String? email(String? value) =>
      value == null ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? 'Enter a valid email'
      : null;
  static String? password(String? value) => value == null || value.length < 8
      ? 'Use at least eight characters'
      : null;
  static int? priceMinor(String value) {
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) return null;
    final parts = value.trim().split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 1000000) return null;
    final minor =
        whole * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
    return minor <= 100000000 ? minor : null;
  }
}
