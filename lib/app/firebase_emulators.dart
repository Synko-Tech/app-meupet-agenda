import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Whether the app should talk to the Firebase Local Emulator Suite instead
/// of production. Default follows the build mode: debug builds use the
/// emulators (so a debug install never touches production data), release
/// builds use production. Explicitly opt out/in with:
///
///   flutter run --dart-define=USE_FIREBASE_EMULATORS=false
const bool kUseFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: kDebugMode,
);

/// Host of the emulator suite from the device's perspective. `10.0.2.2` is
/// the Android emulator loopback to the host machine; use `localhost` on
/// desktop. Override with:
///
///   --dart-define=FIREBASE_EMULATOR_HOST=localhost
const String kFirebaseEmulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

/// Wires Auth, Firestore, Storage and the southamerica-east1 Functions
/// callables to the local emulator suite. Must run after
/// `Firebase.initializeApp` and before any repository is used.
///
/// Logs the active environment (`Firebase: emulators @ <host>` vs
/// `Firebase: production`) so it is always clear which backend the app
/// is talking to.
void configureFirebaseEmulators() {
  if (!kUseFirebaseEmulators) {
    debugPrint('Firebase: production');
    return;
  }
  FirebaseFirestore.instance.useFirestoreEmulator(kFirebaseEmulatorHost, 8080);
  FirebaseAuth.instance.useAuthEmulator(kFirebaseEmulatorHost, 9099);
  FirebaseStorage.instance.useStorageEmulator(kFirebaseEmulatorHost, 9199);
  FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  ).useFunctionsEmulator(kFirebaseEmulatorHost, 5001);
  debugPrint('Firebase: emulators @ $kFirebaseEmulatorHost');
}
