import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/service_model.dart';

class ServiceRepository {
  ServiceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _services(String businessId) =>
      _firestore.collection('businesses/$businessId/services');

  Stream<List<ServiceModel>> activeServicesStream(String businessId) {
    return _services(businessId)
        .where('ativo', isEqualTo: true)
        .snapshots()
        .map(_mapServicesSortedByName);
  }

  Stream<List<ServiceModel>> allServicesStream(String businessId) {
    return _services(businessId).snapshots().map(_mapServicesSortedByName);
  }

  Future<String> saveService(String businessId, ServiceModel service) async {
    final data = {
      ...service.toMap(),
      'businessId': businessId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (service.id.isEmpty) {
      final reference = await _services(businessId).add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return reference.id;
    }

    await _services(businessId)
        .doc(service.id)
        .set(data, SetOptions(merge: true));
    return service.id;
  }

  Future<void> setActive(String businessId, String serviceId, bool isActive) {
    return _services(businessId).doc(serviceId).update({
      'ativo': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<ServiceModel> _mapServicesSortedByName(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final services = snapshot.docs
        .map((document) => ServiceModel.fromMap(document.id, document.data()))
        .toList();
    services.sort((a, b) => a.name.compareTo(b.name));
    return services;
  }
}
