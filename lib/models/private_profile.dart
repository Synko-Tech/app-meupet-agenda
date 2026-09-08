import 'firestore_converters.dart';
import 'postal_address.dart';

/// Private per-user data kept out of `users/{uid}`: full CPF and structured
/// address. Only the owner and super admin can read it.
class PrivateProfile {
  const PrivateProfile({
    required this.userId,
    required this.cpfCanonical,
    required this.cpfLast2,
    required this.address,
    this.createdAt,
    this.updatedAt,
  });

  final String userId;

  /// Full CPF with the 11 digits only, never masked.
  final String cpfCanonical;

  /// Last two digits of the CPF, used to build the masked display value.
  final String cpfLast2;

  final PostalAddress address;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// CPF para exibicao: `***.***.***-NN` (apenas os 2 ultimos digitos
  /// visiveis). Deriva de [cpfLast2], com fallback nos digitos finais de
  /// [cpfCanonical] para documentos legados.
  String get cpfMasked {
    final tail = cpfLast2.isNotEmpty ? cpfLast2 : cpfCanonical;
    if (tail.length < 2) {
      return 'Nao informado';
    }
    return '***.***.***-${tail.substring(tail.length - 2)}';
  }

  factory PrivateProfile.fromMap(String userId, Map<String, dynamic> map) {
    return PrivateProfile(
      userId: userId,
      cpfCanonical:
          map['cpf']?.toString() ?? map['cpfCanonical']?.toString() ?? '',
      cpfLast2: map['cpfLast2']?.toString() ?? '',
      address: PostalAddress.fromMap(
        (map['address'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      createdAt: map['createdAt'] == null
          ? null
          : dateTimeFromFirestore(map['createdAt']),
      updatedAt: map['updatedAt'] == null
          ? null
          : dateTimeFromFirestore(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cpf': cpfCanonical,
      'cpfLast2': cpfLast2,
      'address': address.toMap(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
