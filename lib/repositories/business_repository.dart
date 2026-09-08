import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/business_membership.dart';
import '../models/business_model.dart';
import '../services/idempotency.dart';

/// Resultado da criacao de uma loja via callable `createBusiness`.
class CreatedBusiness {
  const CreatedBusiness({required this.businessId});

  final String businessId;
}

class BusinessRepository {
  BusinessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _businesses =>
      _firestore.collection('businesses');

  /// Projecao das lojas em que o usuario tem membership
  /// (`users/{uid}/businessMemberships/{businessId}`). Sem acesso cruzado:
  /// o SDK le apenas o proprio caminho do usuario.
  Stream<List<BusinessMembership>> myMembershipsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('businessMemberships')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => BusinessMembership.fromMap(userId, doc.data()))
              .toList(),
        );
  }

  /// Dados publicos da loja (`businesses/{businessId}`).
  Stream<BusinessModel?> businessStream(String businessId) {
    return _businesses.doc(businessId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return BusinessModel.fromMap(snapshot.id, data);
    });
  }

  /// Lojas ativas para descoberta publica (clientes encontram pet shops).
  /// Apenas dados publicos da loja; nenhum dado de cliente e exposto.
  Stream<List<BusinessModel>> publicBusinessesStream() {
    return _businesses
        .where('status', isEqualTo: 'ATIVO')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => BusinessModel.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Cria uma loja via callable: o backend cria `businesses/{id}` e o
  /// membership `owner` na mesma transacao. Retorna o id da loja.
  Future<CreatedBusiness> createBusiness({
    required String name,
    String? description,
  }) async {
    final result = await _createBusinessCallable.call({
      'name': name,
      'idempotencyKey': newIdempotencyKey(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
    final businessId = data['businessId'];
    if (businessId is! String || businessId.isEmpty) {
      throw StateError('Resposta invalida do servidor.');
    }
    return CreatedBusiness(businessId: businessId);
  }

  /// Entra em um pet shop como cliente: o backend cria a membership
  /// `businesses/{id}/members/{uid}` (role `client`) e a projecao
  /// `businessMemberships` na mesma transacao. Idempotente: um usuario ja
  /// membro recebe sucesso sem alteracoes.
  Future<void> joinBusiness({required String businessId}) async {
    final result = await _joinBusinessCallable.call({
      'businessId': businessId,
      'idempotencyKey': newIdempotencyKey(),
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
  }

  static final HttpsCallable _createBusinessCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('createBusiness');

  static final HttpsCallable _joinBusinessCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('joinBusiness');
}
