import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;

class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Current user bound to the active token-refresh listener, if any.
  String? _listeningUserId;

  Future<void> configureForUser(String userId) async {
    await _messaging.requestPermission();
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await _registerToken(userId, token);
    _listenForTokenRefresh(userId);
  }

  /// Keeps the Firestore `fcmTokens` array in sync when Firebase Messaging
  /// rotates the token. Without this, the old token stays registered and the
  /// user silently stops receiving push notifications after a rotation.
  void _listenForTokenRefresh(String userId) {
    if (_listeningUserId == userId && _tokenRefreshSubscription != null) {
      return;
    }
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (newToken) {
        _registerToken(userId, newToken);
      },
      onError: (Object error) {
        // Token refresh failures are non-fatal; the next rotation retries.
        assert(() {
          FlutterError.reportError(FlutterErrorDetails(exception: error));
          return true;
        }());
      },
    );
    _listeningUserId = userId;
  }

  Future<void> _registerToken(String userId, String token) async {
    await _firestore.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeCurrentToken(String userId) async {
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await _firestore.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Cancels the token-refresh listener (e.g. on logout or dispose).
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _listeningUserId = null;
  }
}
