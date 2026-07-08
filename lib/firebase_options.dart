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
    if (kIsWeb) return _empty;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      default:
        return _empty;
    }
  }

  static const FirebaseOptions _empty = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
  );
}
