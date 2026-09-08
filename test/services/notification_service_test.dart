import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

void main() {
  late _MockMessaging messaging;
  late _MockFirestore firestore;
  late NotificationService service;

  setUpAll(() {
    registerFallbackValue(SetOptions(merge: true));
    registerFallbackValue(<String>['token-fallback']);
  });

  setUp(() {
    messaging = _MockMessaging();
    firestore = _MockFirestore();
    service = NotificationService(messaging: messaging, firestore: firestore);
  });

  /// Matcher para o mapa de dados do set(): exige a chave fcmTokens e ignora
  /// o valor opaco (FieldValue não implementa ==, então não comparamos o
  /// conteúdo; a contagem de chamadas já prova o registro).
  Matcher setDataMatcher() {
    return isA<Map<String, dynamic>>().having(
      (m) => m.containsKey('fcmTokens'),
      'has fcmTokens',
      isTrue,
    );
  }

  test(
    'configureForUser registers the token and listens for refresh',
    () async {
      final tokenController = StreamController<String>();
      final usersRef = _MockCollectionReference<Map<String, dynamic>>();
      final userDoc = _MockDocumentReference<Map<String, dynamic>>();
      var setCalls = 0;

      when(() => messaging.requestPermission()).thenAnswer(
        (_) async => NotificationSettings(
          alert: AppleNotificationSetting.enabled,
          announcement: AppleNotificationSetting.enabled,
          authorizationStatus: AuthorizationStatus.authorized,
          badge: AppleNotificationSetting.enabled,
          carPlay: AppleNotificationSetting.enabled,
          lockScreen: AppleNotificationSetting.enabled,
          notificationCenter: AppleNotificationSetting.enabled,
          showPreviews: AppleShowPreviewSetting.always,
          timeSensitive: AppleNotificationSetting.enabled,
          criticalAlert: AppleNotificationSetting.enabled,
          sound: AppleNotificationSetting.enabled,
          providesAppNotificationSettings: AppleNotificationSetting.enabled,
        ),
      );
      when(() => messaging.getToken()).thenAnswer((_) async => 'token-1');
      when(
        () => messaging.onTokenRefresh,
      ).thenAnswer((_) => tokenController.stream);
      when(() => firestore.collection('users')).thenReturn(usersRef);
      when(() => usersRef.doc('user-1')).thenReturn(userDoc);
      when(() => userDoc.set(any(), any<SetOptions>())).thenAnswer((_) async {
        setCalls += 1;
      });

      await service.configureForUser('user-1');
      expect(setCalls, 1);

      // Rotação de token dispara um segundo registro no Firestore.
      tokenController.add('token-2');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(setCalls, 2);
      verify(
        () => userDoc.set(any(that: setDataMatcher()), any<SetOptions>()),
      ).called(2);

      service.dispose();
      await tokenController.close();
    },
  );

  test('removeCurrentToken removes the token from Firestore', () async {
    final usersRef = _MockCollectionReference<Map<String, dynamic>>();
    final userDoc = _MockDocumentReference<Map<String, dynamic>>();

    when(() => messaging.getToken()).thenAnswer((_) async => 'token-1');
    when(() => firestore.collection('users')).thenReturn(usersRef);
    when(() => usersRef.doc('user-1')).thenReturn(userDoc);
    when(() => userDoc.set(any(), any<SetOptions>())).thenAnswer((_) async {});

    await service.removeCurrentToken('user-1');

    verify(
      () => userDoc.set(any(that: setDataMatcher()), any<SetOptions>()),
    ).called(1);
  });
}

// mocktail aciona via noSuchMethod; sealed so afeta o analyzer.
// ignore: subtype_of_sealed_class
class _MockCollectionReference<T> extends Mock
    implements CollectionReference<T> {}

// ignore: subtype_of_sealed_class
class _MockDocumentReference<T> extends Mock implements DocumentReference<T> {}
