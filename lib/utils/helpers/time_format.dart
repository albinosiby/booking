/// UI midnight is 24:00; persisted clock values remain canonical HH:mm.
class TimeFormat {
  static String display(String value) => value == '00:00' ? '24:00' : value;

  static String? normalize(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 24 || minute > 59 || (hour == 24 && minute != 0)) {
      return null;
    }
    return '${(hour % 24).toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
