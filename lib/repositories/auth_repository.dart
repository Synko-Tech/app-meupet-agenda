import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/postal_address.dart';
import '../services/idempotency.dart';
import '../services/profile_validators.dart';
import 'private_profile_repository.dart';

class AuthRepository {
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    PrivateProfileRepository? privateProfileRepository,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _privateProfile = privateProfileRepository ?? PrivateProfileRepository();

  final FirebaseAuth _auth;
  final PrivateProfileRepository _privateProfile;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    UserRole role = UserRole.client,
    String? phone,
    required String cpf,
    required PostalAddress address,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'missing-user',
        message: 'Nao foi possivel criar o usuario.',
      );
    }

    await user.updateDisplayName(name.trim());
    try {
      await _privateProfile.completeOwnProfile(
        name: name.trim(),
        phone: phone,
        cpf: cpf,
        address: address,
      );
    } catch (error) {
      debugPrint('Falha ao completar perfil: $error');
      try {
        await user.delete();
      } catch (deleteError) {
        debugPrint(
          'Falha ao remover usuario apos erro no cadastro: $deleteError',
        );
      }
      rethrow;
    }
  }

  Future<void> registerClient({
    required String name,
    required String email,
    required String password,
    String? phone,
    required String cpf,
    required PostalAddress address,
  }) {
    return register(
      name: name,
      email: email,
      password: password,
      role: UserRole.client,
      phone: phone,
      cpf: cpf,
      address: address,
    );
  }

  /// Cadastra um novo estabelecimento (pet shop) e seu dono.
  ///
  /// Cria o usuario no Firebase Auth e, em seguida, chama o callable
  /// `registerBusiness` para gravar o perfil do responsavel, a loja, a
  /// membership `owner` e a projecao `businessMemberships` em uma unica
  /// transacao. Se o callable falhar (ex.: CNPJ/CPF duplicado), o usuario
  /// recem-criado e removido para nao deixar conta orfã.
  Future<CreatedBusinessAccount> registerBusiness({
    required String name,
    required String email,
    required String password,
    String? phone,
    required String cpf,
    required String cnpj,
    required String businessName,
    String? businessLegalName,
    String? businessPhone,
    String? businessDescription,
    required PostalAddress address,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'missing-user',
        message: 'Nao foi possivel criar o usuario.',
      );
    }

    await user.updateDisplayName(name.trim());
    try {
      final result = await _registerBusinessCallable.call({
        'name': name.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'cpf': digitsOnly(cpf),
        'cnpj': digitsOnly(cnpj),
        'businessName': businessName.trim(),
        if (businessLegalName != null &&
            businessLegalName.trim().isNotEmpty)
          'businessLegalName': businessLegalName.trim(),
        if (businessPhone != null && businessPhone.trim().isNotEmpty)
          'businessPhone': businessPhone.trim(),
        if (businessDescription != null &&
            businessDescription.trim().isNotEmpty)
          'businessDescription': businessDescription.trim(),
        'address': {
          'postalCode': digitsOnly(address.postalCode),
          'street': address.street,
          'number': address.number,
          if (address.complement != null &&
              address.complement!.trim().isNotEmpty)
            'complement': address.complement,
          'neighborhood': address.neighborhood,
          'city': address.city,
          'state': address.state,
          'country': address.country,
        },
        'idempotencyKey': newIdempotencyKey(),
      });
      final data = result.data;
      if (data is! Map) {
        throw StateError('Resposta invalida do servidor.');
      }
      final businessId = data['businessId'];
      if (businessId is! String || businessId.isEmpty) {
        throw StateError('Resposta invalida do servidor.');
      }
      return CreatedBusinessAccount(businessId: businessId);
    } catch (error) {
      debugPrint('Falha ao cadastrar empresa: $error');
      try {
        await user.delete();
      } catch (deleteError) {
        debugPrint(
          'Falha ao remover usuario apos erro no cadastro: $deleteError',
        );
      }
      rethrow;
    }
  }

  /// Completa o perfil privado de um usuario ja autenticado (fluxo de
  /// complementacao de cadastro): o callable valida o CPF, grava o endereco
  /// e marca `profileComplete: true` no documento do usuario.
  Future<void> completeOwnProfile({
    required String name,
    String? phone,
    required String cpf,
    required PostalAddress address,
  }) {
    return _privateProfile.completeOwnProfile(
      name: name,
      phone: phone,
      cpf: cpf,
      address: address,
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();

  static final HttpsCallable _registerBusinessCallable =
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).httpsCallable('registerBusiness');
}

/// Resultado do cadastro de uma empresa via callable `registerBusiness`.
class CreatedBusinessAccount {
  const CreatedBusinessAccount({required this.businessId});

  final String businessId;
}
