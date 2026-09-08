import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/firebase_emulators.dart';

void main() {
  group('resolucao de ambiente', () {
    test('sem override explicito, debug usa os emuladores por padrao', () {
      // `flutter test` roda em modo debug. O default da constante deve
      // seguir o modo de build: debug => emuladores, release => producao.
      expect(kUseFirebaseEmulators, isTrue);
      expect(kUseFirebaseEmulators, kDebugMode);
    });

    test('host padrao e o loopback do emulador Android', () {
      expect(kFirebaseEmulatorHost, '10.0.2.2');
    });
  });
}
