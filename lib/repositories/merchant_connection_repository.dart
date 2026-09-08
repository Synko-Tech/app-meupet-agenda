import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/merchant_connection_summary.dart';

/// Resultado de iniciar a conexão OAuth Mercado Pago de uma loja.
class MerchantOAuthStart {
  const MerchantOAuthStart({required this.authorizationUrl});

  final Uri authorizationUrl;
}

class MerchantConnectionRepository {
  MerchantConnectionRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Resumo publico da conexão, gravado pelo backend no doc da loja
  /// (`businesses/{businessId}.merchantSummary`). Nunca contém tokens.
  Stream<MerchantConnectionSummary> merchantSummaryStream(String businessId) {
    return _firestore.collection('businesses').doc(businessId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      final summary = data?['merchantSummary'];
      if (summary is! Map) {
        return MerchantConnectionSummary.disconnected;
      }
      return MerchantConnectionSummary.fromMap(
        Map<String, dynamic>.from(summary),
      );
    });
  }

  /// Gera a URL de autorização oficial (owner only, validado no backend).
  Future<MerchantOAuthStart> startConnection(String businessId) async {
    final result = await _startConnectionCallable.call({
      'businessId': businessId,
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
    final url = data['authorizationUrl'];
    if (url is! String || url.isEmpty) {
      throw StateError('Resposta invalida do servidor.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https')) {
      throw StateError('Link de autorizacao invalido.');
    }
    return MerchantOAuthStart(authorizationUrl: uri);
  }

  /// Renova o access token do seller (owner only). No-op quando ainda válido.
  Future<bool> refreshConnection(String businessId) async {
    final result = await _refreshConnectionCallable.call({
      'businessId': businessId,
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
    return data['refreshed'] == true;
  }

  /// Desconecta a conta recebedora (owner only).
  Future<void> disconnectConnection(String businessId) async {
    await _disconnectConnectionCallable.call({'businessId': businessId});
  }

  static final HttpsCallable _startConnectionCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('startMpConnection');

  static final HttpsCallable _refreshConnectionCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('refreshMpConnection');

  static final HttpsCallable _disconnectConnectionCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('disconnectMpConnection');
}
