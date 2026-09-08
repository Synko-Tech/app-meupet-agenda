import 'firestore_converters.dart';

/// Resumo PUBLICO e seguro da conexão Mercado Pago da loja. Nunca contém
/// tokens; apenas o estado exibido no perfil do owner.
class MerchantConnectionSummary {
  const MerchantConnectionSummary({
    required this.status,
    this.collectorId,
    this.liveMode,
    this.connectedAt,
    this.expiresAt,
  });

  final MerchantConnectionStatus status;
  final String? collectorId;
  final bool? liveMode;
  final DateTime? connectedAt;
  final DateTime? expiresAt;

  bool get isConnected => status == MerchantConnectionStatus.connected;

  bool get needsRefresh {
    if (!isConnected || expiresAt == null) {
      return false;
    }
    // Renovacao preventiva: faltando menos de 7 dias, alerta o owner.
    return expiresAt!.isBefore(DateTime.now().add(const Duration(days: 7)));
  }

  factory MerchantConnectionSummary.fromMap(Map<String, dynamic> map) {
    return MerchantConnectionSummary(
      status: MerchantConnectionStatus.fromFirestore(map['status']),
      collectorId: map['collectorId']?.toString(),
      liveMode: map['liveMode'] as bool?,
      connectedAt: map['connectedAt'] == null
          ? null
          : dateTimeFromFirestore(map['connectedAt']),
      expiresAt: map['expiresAt'] == null
          ? null
          : dateTimeFromFirestore(map['expiresAt']),
    );
  }

  static const MerchantConnectionSummary disconnected =
      MerchantConnectionSummary(status: MerchantConnectionStatus.disconnected);
}

enum MerchantConnectionStatus {
  connected,
  disconnected;

  String get firestoreValue {
    switch (this) {
      case MerchantConnectionStatus.connected:
        return 'CONECTADO';
      case MerchantConnectionStatus.disconnected:
        return 'DESCONECTADO';
    }
  }

  String get label {
    switch (this) {
      case MerchantConnectionStatus.connected:
        return 'Conectado';
      case MerchantConnectionStatus.disconnected:
        return 'Desconectado';
    }
  }

  static MerchantConnectionStatus fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'CONECTADO' => MerchantConnectionStatus.connected,
      _ => MerchantConnectionStatus.disconnected,
    };
  }
}
