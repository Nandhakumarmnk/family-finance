import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// PLACEHOLDER Firebase configuration.
///
/// Every field is empty on purpose, so the app stays on its current storage
/// and never tries to reach Firebase. To switch the app to the **free, global
/// Firestore backend**, regenerate this file with your own project's values:
///
/// ```sh
/// dart pub global activate flutterfire_cli
/// flutterfire configure        # pick your free Firebase project
/// ```
///
/// That overwrites this file with real keys; the app then auto-detects them
/// (see `_initFirebase` in main.dart) and stores all data in Firestore — which
/// works for every Google user worldwide with no verification.
///
/// File attachments (receipt photos, profile picture) ride along for free:
/// they're stored as base64 in Firestore, so there's no Cloud Storage bucket to
/// set up and no Blaze plan needed — the whole app stays on the free Spark plan.
///
/// (These values are NOT secrets; Firebase web/app keys ship in every client.
/// Access is protected by Firestore **security rules**, see firestore.rules.)
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return _web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      default:
        return _android;
    }
  }

  // Web app — Firebase console → Project settings → Your apps → Web.
  static const FirebaseOptions _web = FirebaseOptions(
    apiKey: 'AIzaSyCIbh_4ZEfdQaton2p2WsCVTB1FVO6G0Kk',
    appId: '1:380367970706:web:a6a676b388610cc3d8a14b',
    messagingSenderId: '380367970706',
    projectId: 'family-finance-4fab0',
    authDomain: 'family-finance-4fab0.firebaseapp.com',
    measurementId: 'G-S90LGNJZPQ',
  );

  // Android app. apiKey / messagingSenderId / projectId are project-wide (same
  // as web); only `appId` differs. It currently reuses the web appId as a
  // stopgap so Firestore works — replace it with the ANDROID app id
  // (1:380367970706:android:…) after you register the Android app in the
  // console (Project settings → Add app → Android).
  static const FirebaseOptions _android = FirebaseOptions(
    apiKey: 'AIzaSyCIbh_4ZEfdQaton2p2WsCVTB1FVO6G0Kk',
    appId: '1:380367970706:web:a6a676b388610cc3d8a14b',
    messagingSenderId: '380367970706',
    projectId: 'family-finance-4fab0',
  );
}
