import 'package:cloud_firestore/cloud_firestore.dart';

DateTime dateTimeFromFirestore(Object? value, {DateTime? fallback}) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
  }
  return fallback ?? DateTime.now();
}

/// Strict variant for REQUIRED fields (e.g. validUntil, startAt, endAt).
/// `dateTimeFromFirestore` silently falls back to `DateTime.now()`, which
/// corrupts business logic: a missing `validUntil` marks a usable package as
/// expired, a missing `startAt` misplaces an appointment on the schedule.
/// This variant throws instead of masking the schema/data bug.
DateTime dateTimeRequiredFromFirestore(
  Object? value, {
  String? field,
  DateTime? fallback,
}) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  if (fallback != null) {
    return fallback;
  }
  throw StateError(
    'Campo de data obrigatório ausente ou inválido${field == null ? '' : ': $field'}',
  );
}

double doubleFromFirestore(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  }
  return 0;
}

int intFromFirestore(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
