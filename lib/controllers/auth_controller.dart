import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/postal_address.dart';
import '../repositories/auth_repository.dart';
import '../repositories/user_repository.dart';
import '../services/function_error.dart';
import '../services/notification_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required NotificationService notificationService,
  }) : _authRepository = authRepository,
       _userRepository = userRepository,
       _notificationService = notificationService {
    _authSubscription = _authRepository.authStateChanges().listen(
      _handleAuthChanged,
      onError: _handleError,
    );
  }

  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final NotificationService _notificationService;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<AppUser?>? _profileSubscription;

  User? firebaseUser;
  AppUser? profile;
  bool isLoading = true;
  bool isBusy = false;
  String? errorMessage;

  bool get isAuthenticated => firebaseUser != null && profile?.isActive == true;
  bool get isAuthenticatedAndActive => isAuthenticated;
  bool get isSuperAdmin => profile?.isSuperAdmin ?? false;
  bool get isAdmin => profile?.isAdmin ?? false;
  bool get isStaff => profile?.isStaff ?? false;
  bool get canAccessAdminPanel => profile?.canAccessAdminPanel ?? false;

  Future<void> signIn({required String email, required String password}) {
    return _run(() => _authRepository.signIn(email: email, password: password));
  }

  Future<void> registerClient({
    required String name,
    required String email,
    required String password,
    String? phone,
    required String cpf,
    required PostalAddress address,
  }) {
    return _run(
      () => _authRepository.registerClient(
        name: name,
        email: email,
        password: password,
        phone: phone,
        cpf: cpf,
        address: address,
      ),
    );
  }

  Future<void> registerBusiness({
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
  }) {
    return _run(
      () => _authRepository.registerBusiness(
        name: name,
        email: email,
        password: password,
        phone: phone,
        cpf: cpf,
        cnpj: cnpj,
        businessName: businessName,
        businessLegalName: businessLegalName,
        businessPhone: businessPhone,
        businessDescription: businessDescription,
        address: address,
      ),
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _run(() => _authRepository.sendPasswordReset(email));
  }

  /// Completa o perfil de um usuario legado (sem CPF/endereco): envia o
  /// payload canonico ao callable `completeOwnProfile` e aguarda a stream do
  /// perfil notificar `profileComplete: true`, que libera o gate.
  Future<void> completeOwnProfile({
    required String name,
    String? phone,
    required String cpf,
    required PostalAddress address,
  }) {
    return _run(
      () => _authRepository.completeOwnProfile(
        name: name,
        phone: phone,
        cpf: cpf,
        address: address,
      ),
    );
  }

  Future<void> updateProfile({required String name, String? phone}) {
    final currentProfile = profile;
    if (currentProfile == null) {
      return Future.error(StateError('Perfil nao carregado.'));
    }

    return _run(
      () => _userRepository.updateProfile(
        currentProfile.copyWith(
          name: name,
          phone: phone == null || phone.trim().isEmpty ? null : phone.trim(),
        ),
      ),
    );
  }

  Future<void> enableNotifications() async {
    final userId = firebaseUser?.uid;
    if (userId == null) {
      return;
    }
    await _run(() => _notificationService.configureForUser(userId));
  }

  Future<void> signOut() async {
    final userId = firebaseUser?.uid;
    if (userId != null) {
      try {
        await _notificationService.removeCurrentToken(userId);
      } catch (error) {
        debugPrint('Falha ao remover token FCM: $error');
      }
    }
    // Para o listener de rotação de token: o próximo login reinicia via
    // enableNotifications() com o novo usuário.
    _notificationService.dispose();
    await _authRepository.signOut();
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = _friendlyMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void _handleAuthChanged(User? user) {
    firebaseUser = user;
    profile = null;
    errorMessage = null;
    _profileSubscription?.cancel();

    if (user == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();
    _profileSubscription = _userRepository.profileStream(user.uid).listen((
      appUser,
    ) {
      profile = appUser;
      isLoading = false;
      notifyListeners();
    }, onError: _handleError);
  }

  void _handleError(Object error) {
    errorMessage = _friendlyMessage(error);
    isLoading = false;
    isBusy = false;
    notifyListeners();
  }

  String _friendlyMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' ||
        'invalid-login-credentials' => 'E-mail ou senha invalidos.',
        'email-already-in-use' => 'Este e-mail ja esta cadastrado.',
        'weak-password' => 'A senha precisa ser mais forte.',
        'invalid-email' => 'Informe um e-mail valido.',
        'configuration-not-found' =>
          'O Firebase Authentication nao esta configurado para este app. '
              'Confira o projeto Firebase, o google-services.json e habilite '
              'o provedor E-mail/senha no console.',
        _ => error.message ?? 'Nao foi possivel concluir a autenticacao.',
      };
    }

    // Callable errors (e.g. `already-exists` de CPF duplicado) e erros
    // genericos seguem o mapeamento compartilhado de `friendlyErrorMessage`.
    return friendlyErrorMessage(error);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
