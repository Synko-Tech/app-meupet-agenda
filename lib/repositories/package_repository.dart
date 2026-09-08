import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/package_model.dart';
import '../services/idempotency.dart';

/// Result of starting a Mercado Pago Checkout Pro flow.
class MercadoPagoCheckout {
  const MercadoPagoCheckout({
    required this.paymentId,
    required this.preferenceId,
    required this.initPoint,
  });

  final String paymentId;
  final String preferenceId;
  final Uri initPoint;
}

class PackageRepository {
  PackageRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _packages(String businessId) =>
      _firestore.collection('businesses/$businessId/packages');

  CollectionReference<Map<String, dynamic>> _customerPackages(String businessId) =>
      _firestore.collection('businesses/$businessId/customerPackages');

  Stream<List<BusinessPackageModel>> activePackagesStream(String businessId) {
    return _packages(businessId)
        .where('ativo', isEqualTo: true)
        .snapshots()
        .map(_mapBusinessPackagesSortedByName);
  }

  Stream<List<BusinessPackageModel>> allPackagesStream(String businessId) {
    return _packages(businessId)
        .snapshots()
        .map(_mapBusinessPackagesSortedByName);
  }

  Stream<List<CustomerPackageModel>> customerPackagesStream(
    String businessId,
    String clientId,
  ) {
    return _customerPackages(businessId)
        .where('id_cliente', isEqualTo: clientId)
        .snapshots()
        .map(_mapCustomerPackagesByValidity);
  }

  Stream<List<CustomerPackageModel>> activeCustomerPackagesForServiceStream({
    required String businessId,
    required String clientId,
    required String serviceId,
  }) {
    return customerPackagesStream(businessId, clientId).map(
      (packages) => packages
          .where((package) => package.serviceId == serviceId && package.canUse)
          .toList(),
    );
  }

  Future<String> savePackage(String businessId, BusinessPackageModel package) async {
    final data = {
      ...package.toMap(),
      'businessId': businessId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (package.id.isEmpty) {
      final reference = await _packages(businessId).add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return reference.id;
    }

    await _packages(businessId)
        .doc(package.id)
        .set(data, SetOptions(merge: true));
    return package.id;
  }

  /// Purchases a catalog package through the `purchasePackage` callable.
  /// Creates a PENDENTE payment only — the customerPackage is created
  /// server-side on activation, never here.
  Future<String> purchasePackage({
    required String businessId,
    required String packageId,
    String? method,
  }) async {
    final result = await _purchasePackageCallable.call({
      'businessId': businessId,
      'packageId': packageId,
      'idempotencyKey': newIdempotencyKey(),
      if (method != null && method.isNotEmpty) 'method': method,
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
    final paymentId = data['paymentId'];
    if (paymentId is! String || paymentId.isEmpty) {
      throw StateError('Resposta invalida do servidor.');
    }
    return paymentId;
  }

  static final HttpsCallable _purchasePackageCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('purchasePackage');

  /// Starts a Mercado Pago Checkout Pro flow for one catalog package via the
  /// `createMercadoPagoCheckout` callable. The payment is born PENDENTE; only
  /// the Mercado Pago webhook can change its status afterwards.
  Future<MercadoPagoCheckout> createMercadoPagoCheckout({
    required String businessId,
    required String packageId,
  }) async {
    final result = await _createCheckoutCallable.call({
      'businessId': businessId,
      'packageId': packageId,
      'idempotencyKey': newIdempotencyKey(),
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
    final paymentId = data['paymentId'];
    final preferenceId = data['preferenceId'];
    final initPoint = data['initPoint'];
    if (paymentId is! String ||
        paymentId.isEmpty ||
        preferenceId is! String ||
        preferenceId.isEmpty ||
        initPoint is! String ||
        initPoint.isEmpty) {
      throw StateError('Resposta invalida do servidor.');
    }
    final uri = Uri.tryParse(initPoint);
    if (uri == null || !uri.isScheme('https')) {
      throw StateError('Link de pagamento invalido.');
    }
    return MercadoPagoCheckout(
      paymentId: paymentId,
      preferenceId: preferenceId,
      initPoint: uri,
    );
  }

  static final HttpsCallable _createCheckoutCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('createMercadoPagoCheckout');

  List<BusinessPackageModel> _mapBusinessPackagesSortedByName(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final packages = snapshot.docs
        .map(
          (document) =>
              BusinessPackageModel.fromMap(document.id, document.data()),
        )
        .toList();
    packages.sort((a, b) => a.name.compareTo(b.name));
    return packages;
  }

  List<CustomerPackageModel> _mapCustomerPackagesByValidity(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final packages = snapshot.docs
        .map(
          (document) =>
              CustomerPackageModel.fromMap(document.id, document.data()),
        )
        .toList();
    packages.sort((a, b) => b.validUntil.compareTo(a.validUntil));
    return packages;
  }
}
