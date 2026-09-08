import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Stream<AppUser?> profileStream(String userId) {
    return _users.doc(userId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      return AppUser.fromMap(snapshot.id, data);
    });
  }

  Future<AppUser?> getProfile(String userId) async {
    final snapshot = await _users.doc(userId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return null;
    }
    return AppUser.fromMap(snapshot.id, data);
  }

  Future<void> createProfile(AppUser user) {
    return _users.doc(user.id).set({
      ...user.toMap(),
      // Campo legado mantido para facilitar migracao de dados antigos do TCC.
      'tipo_usuario': user.role.firestoreValue,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProfile(AppUser user) {
    // Apenas os campos editaveis pelo proprio usuario — o restante (email,
    // role, ativo, profileComplete, schemaVersion) e gerenciado pelo backend
    // e a allowlist de update em firestore.rules bloqueia qualquer outro
    // campo. Enviar somente estes evita depender do comportamento do merge.
    return _users.doc(user.id).set({
      'nome': user.name,
      'telefone': user.phone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserRole({
    required String userId,
    required UserRole role,
  }) {
    return _users.doc(userId).update({
      'role': role.firestoreValue,
      'tipo_usuario': role.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AppUser>> allUsersStream() {
    return _users.orderBy('nome').snapshots().map(_mapUsers);
  }

  Stream<List<AppUser>> allClientsStream() {
    return _users
        .where('role', isEqualTo: UserRole.client.firestoreValue)
        .snapshots()
        .map(_mapUsersSortedByName);
  }

  Future<void> setUserActive({required String userId, required bool isActive}) {
    return _users.doc(userId).update({
      'ativo': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AppUser>> staffStream() {
    return _users
        .where(
          'role',
          whereIn: [
            UserRole.superAdmin.firestoreValue,
            UserRole.admin.firestoreValue,
            UserRole.collaborator.firestoreValue,
          ],
        )
        .where('ativo', isEqualTo: true)
        .snapshots()
        .map(_mapUsersSortedByName);
  }

  List<AppUser> _mapUsers(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs
        .map((document) => AppUser.fromMap(document.id, document.data()))
        .toList();
  }

  List<AppUser> _mapUsersSortedByName(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final users = _mapUsers(snapshot);
    users.sort((a, b) => a.name.compareTo(b.name));
    return users;
  }
}
