import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Thin wrapper over Cloud Storage for Firebase. Every file lives under
/// `users/{uid}/…` so it's private to the signed-in user (enforced by
/// `storage.rules`). Used for receipt photos, exported PDF reports, and
/// profile pictures.
///
/// Only instantiated in the Firestore (cloud) backend; the legacy Drive path
/// never touches this.
class StorageService {
  StorageService(this.uid);

  final String uid;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Reference _ref(String path) => _storage.ref('users/$uid/$path');

  /// Upload [bytes] to `users/{uid}/[path]` and return its download URL.
  Future<String> uploadBytes(
    String path,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final ref = _ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Best-effort delete; ignores "not found" so callers can fire-and-forget.
  Future<void> deletePath(String path) async {
    try {
      await _ref(path).delete();
    } catch (_) {/* already gone, or never uploaded */}
  }

  // --- typed helpers ---------------------------------------------------------
  /// Receipt photo for an expense → users/{uid}/receipts/{expenseId}.jpg
  Future<String> uploadReceipt(String expenseId, Uint8List bytes) =>
      uploadBytes('receipts/$expenseId.jpg', bytes, contentType: 'image/jpeg');

  Future<void> deleteReceipt(String expenseId) =>
      deletePath('receipts/$expenseId.jpg');

  /// A generated PDF report/statement → users/{uid}/reports/{fileName}
  Future<String> uploadReport(String fileName, Uint8List bytes) =>
      uploadBytes('reports/$fileName', bytes, contentType: 'application/pdf');

  /// Custom profile picture → users/{uid}/profile.jpg
  Future<String> uploadProfilePhoto(Uint8List bytes) =>
      uploadBytes('profile.jpg', bytes, contentType: 'image/jpeg');

  Future<void> deleteProfilePhoto() => deletePath('profile.jpg');
}
