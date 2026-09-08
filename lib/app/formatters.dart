String formatCurrency(double value) {
  return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
}

String formatDate(DateTime date) {
  return '${_two(date.day)}/${_two(date.month)}/${date.year}';
}

String formatShortDate(DateTime date) {
  return '${_two(date.day)}/${_two(date.month)}';
}

String formatTime(DateTime date) {
  return '${_two(date.hour)}:${_two(date.minute)}';
}

String formatDayKey(DateTime date) {
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String weekdayLabel(DateTime date) {
  const labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
  return labels[date.weekday - 1];
}

/// Encodes a booking time for the `createAppointment` callable.
///
/// Contract: the callable's `startAt` is parsed with `new Date(...)` and every
/// wall-clock computation (business hours, dayKey/timeKey, slot locks) is done
/// in America/Sao_Paulo via an explicit `Intl` conversion
/// (functions/src/appointments/slot-keys.ts). Sending the UTC instant (with
/// the `Z` suffix) is the only unambiguous encoding — the caller's local
/// DateTime must represent the Sao Paulo wall-clock the user picked, and this
/// converts it to the instant without offset ambiguity.
String isoForCall(DateTime date) {
  return date.toUtc().toIso8601String();
}

String _two(int value) => value.toString().padLeft(2, '0');
