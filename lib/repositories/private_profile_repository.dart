import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/postal_address.dart';
import '../models/private_profile.dart';
import '../services/profile_validators.dart';

/// Reads and completes the user's private profile (`userPrivate/{uid}`).
///
/// CPF and postal code are always normalized to their canonical digits-only
/// form before being sent to the `completeOwnProfile` callable; the backend
/// rejects masked or padded values.
class PrivateProfileRepository {
  PrivateProfileRepository({
    FirebaseFirestore? firestore,
    HttpsCallable? completeOwnProfileCallable,
    HttpsCallable? updateOwnAddressCallable,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _completeOwnProfileCallable =
           completeOwnProfileCallable ?? _defaultCompleteOwnProfileCallable,
       _updateOwnAddressCallable =
           updateOwnAddressCallable ?? _defaultUpdateOwnAddressCallable;

  final FirebaseFirestore _firestore;
  final HttpsCallable _completeOwnProfileCallable;
  final HttpsCallable _updateOwnAddressCallable;

  /// Production callable; injectable constructor parameter exists for tests.
  static final HttpsCallable _defaultCompleteOwnProfileCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('completeOwnProfile');

  /// Production callable; injectable constructor parameter exists for tests.
  static final HttpsCallable _defaultUpdateOwnAddressCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('updateOwnAddress');

  /// The owner's private document (`userPrivate/{userId}`), or null while it
  /// does not exist yet. Firestore rules only grant the owner their own doc.
  Stream<PrivateProfile?> privateProfileStream(String userId) {
    return _firestore.collection('userPrivate').doc(userId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return PrivateProfile.fromMap(userId, data);
    });
  }

  /// Sends the canonical (unmasked) registration payload to the
  /// `completeOwnProfile` callable: CPF as 11 digits and postal code as 8
  /// digits, address fields otherwise as-is.
  ///
  /// Exceptions from the callable (e.g. `already-exists`, `failed-precondition`)
  /// propagate as [FirebaseFunctionsException] so the controller layer maps
  /// them with `friendlyErrorMessage`, matching `BusinessRepository`.
  Future<void> completeOwnProfile({
    required String name,
    String? phone,
    required String cpf,
    required PostalAddress address,
  }) async {
    final result = await _completeOwnProfileCallable.call({
      'name': name,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'cpf': digitsOnly(cpf),
      'address': {
        'postalCode': digitsOnly(address.postalCode),
        'street': address.street,
        'number': address.number,
        if (address.complement != null && address.complement!.trim().isNotEmpty)
          'complement': address.complement,
        'neighborhood': address.neighborhood,
        'city': address.city,
        'state': address.state,
        'country': address.country,
      },
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
  }

  /// Updates ONLY the owner's address through the `updateOwnAddress`
  /// callable: postal code as 8 digits, address fields otherwise as-is.
  /// CPF never leaves the backend document; the callable never writes
  /// `users/{uid}`.
  ///
  /// Exceptions from the callable propagate as
  /// [FirebaseFunctionsException] so the screen layer maps them with
  /// `friendlyErrorMessage`.
  Future<void> updateOwnAddress({required PostalAddress address}) async {
    final result = await _updateOwnAddressCallable.call({
      'address': {
        'postalCode': digitsOnly(address.postalCode),
        'street': address.street,
        'number': address.number,
        if (address.complement != null && address.complement!.trim().isNotEmpty)
          'complement': address.complement,
        'neighborhood': address.neighborhood,
        'city': address.city,
        'state': address.state,
        'country': address.country,
      },
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Resposta invalida do servidor.');
    }
  }
}
