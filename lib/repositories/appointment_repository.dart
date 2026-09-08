import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../app/formatters.dart';
import '../models/appointment_model.dart';
import '../models/package_model.dart';
import '../models/service_model.dart';
import '../services/idempotency.dart';

class AppointmentRepository {
  AppointmentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _appointments(String businessId) =>
      _firestore.collection('businesses/$businessId/appointments');

  Stream<List<AppointmentModel>> customerAppointmentsStream(
    String businessId,
    String clientId,
  ) {
    return _appointments(businessId)
        .where('id_cliente', isEqualTo: clientId)
        .snapshots()
        .map(_mapAppointmentsByDateDesc);
  }

  Stream<List<AppointmentModel>> allAppointmentsStream(String businessId) {
    return _appointments(businessId).snapshots().map(_mapAppointmentsByDateDesc);
  }

  Stream<List<AppointmentModel>> todayAppointmentsStream(String businessId) {
    return appointmentsForDayStream(businessId, DateTime.now());
  }

  Stream<List<AppointmentModel>> appointmentsForDayStream(
    String businessId,
    DateTime date,
  ) {
    final dayKey = formatDayKey(date);
    return _appointments(businessId)
        .where('dayKey', isEqualTo: dayKey)
        .snapshots()
        .map(_mapAppointmentsByDateAsc);
  }

  /// Creates an appointment through the `createAppointment` callable. The
  /// caller's identity comes from the authenticated user — never from the
  /// client. Slot reservation, business-hours enforcement and package credit
  /// consumption are server-authoritative.
  Future<String> createAppointment({
    required String businessId,
    required ServiceModel service,
    required DateTime startAt,
    CustomerPackageModel? customerPackage,
  }) async {
    final result = await _createAppointmentCallable.call({
      'businessId': businessId,
      'serviceId': service.id,
      'startAt': isoForCall(startAt),
      'idempotencyKey': newIdempotencyKey(),
      if (customerPackage != null) 'customerPackageId': customerPackage.id,
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
    final appointmentId = data['appointmentId'];
    if (appointmentId is! String || appointmentId.isEmpty) {
      throw StateError('Resposta invalida do servidor.');
    }
    return appointmentId;
  }

  /// Cancels an appointment through the `cancelAppointment` callable
  /// (idempotent; slot locks and package credits are released server-side).
  Future<void> cancelAppointment(String businessId, AppointmentModel appointment) async {
    await _cancelAppointmentCallable.call({
      'businessId': businessId,
      'appointmentId': appointment.id,
      'idempotencyKey': newIdempotencyKey(),
    });
  }

  static final HttpsCallable _createAppointmentCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('createAppointment');

  static final HttpsCallable _cancelAppointmentCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('cancelAppointment');

  List<AppointmentModel> _mapAppointmentsByDateDesc(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final appointments = _mapAppointments(snapshot);
    appointments.sort((a, b) => b.startAt.compareTo(a.startAt));
    return appointments;
  }

  List<AppointmentModel> _mapAppointmentsByDateAsc(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final appointments = _mapAppointments(snapshot);
    appointments.sort((a, b) => a.startAt.compareTo(b.startAt));
    return appointments;
  }

  List<AppointmentModel> _mapAppointments(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map(
          (document) => AppointmentModel.fromMap(document.id, document.data()),
        )
        .toList();
  }
}
