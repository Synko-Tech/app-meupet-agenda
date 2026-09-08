class BusinessHours {
  const BusinessHours._();

  static bool isInsideBookingHours({
    required String time,
    required String serviceName,
    required DateTime date,
  }) {
    final minutes = minutesFromTime(time);
    final isSaturday = date.weekday == DateTime.saturday;
    final isRestrictedService = isBathOrGrooming(serviceName);

    if (date.weekday == DateTime.sunday) {
      return false;
    }

    if (isRestrictedService) {
      if (isSaturday) {
        return minutes >= 8 * 60 && minutes <= 10 * 60;
      }
      return minutes >= 8 * 60 && minutes <= 16 * 60;
    }

    if (isSaturday) {
      return minutes >= 8 * 60 && minutes <= 12 * 60;
    }

    return minutes >= 8 * 60 && minutes < 18 * 60;
  }

  static bool shouldShowInSchedule(String time) {
    return minutesFromTime(time) < 18 * 60;
  }

  static bool isBathOrGrooming(String serviceName) {
    final normalized = normalize(serviceName);
    return normalized.contains('banho') || normalized.contains('tosa');
  }

  static int minutesFromTime(String time) {
    final parts = time.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return hour * 60 + minute;
  }

  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.trim().toLowerCase().runes) {
      buffer.write(switch (rune) {
        0x00E1 || 0x00E0 || 0x00E3 || 0x00E2 || 0x00E4 => 'a',
        0x00E9 || 0x00E8 || 0x00EA || 0x00EB => 'e',
        0x00ED || 0x00EC || 0x00EE || 0x00EF => 'i',
        0x00F3 || 0x00F2 || 0x00F5 || 0x00F4 || 0x00F6 => 'o',
        0x00FA || 0x00F9 || 0x00FB || 0x00FC => 'u',
        0x00E7 => 'c',
        _ => String.fromCharCode(rune),
      });
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  }
}
