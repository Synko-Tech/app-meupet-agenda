import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/payment_model.dart';

class PaymentRepository {
  PaymentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _payments(String businessId) =>
      _firestore.collection('businesses/$businessId/payments');

  /// Client payments filtered by the inclusive start / exclusive end window
  /// over `createdAt`, newest first (server-side order).
  Stream<List<PaymentModel>> customerPaymentsStream(
    String businessId,
    String clientId, {
    DateTime? start,
    DateTime? endExclusive,
  }) {
    var query = _payments(businessId).where('id_cliente', isEqualTo: clientId);
    if (start != null && endExclusive != null) {
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThan: endExclusive);
    }
    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapPayments);
  }

  /// All payments (staff), filtered by the same `createdAt` window.
  Stream<List<PaymentModel>> allPaymentsStream(
    String businessId, {
    DateTime? start,
    DateTime? endExclusive,
  }) {
    Query<Map<String, dynamic>> query = _payments(businessId);
    if (start != null && endExclusive != null) {
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThan: endExclusive);
    }
    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapPayments);
  }

  List<PaymentModel> _mapPayments(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map((document) => PaymentModel.fromMap(document.id, document.data()))
        .toList();
  }
}
