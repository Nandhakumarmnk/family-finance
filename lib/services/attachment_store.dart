import 'package:cloud_firestore/cloud_firestore.dart';

/// Stores small image attachments (expense receipts) as base64 **inside
/// Firestore**, so the app needs no Cloud Storage bucket — which would force
/// the Blaze (paid) plan. Everything here stays on the free Spark plan.
///
/// Layout: one document per receipt at `users/{uid}/receipts/{expenseId}`,
/// holding the encoded bytes. Keeping one image per document means each doc
/// stays well under Firestore's 1 MiB per-document limit (the picked image is
/// downscaled before it ever reaches here — see `AppState.uploadReceipt`).
///
/// Only used on the Firestore (cloud) backend; the legacy Drive path never
/// touches this. The receipts subcollection is owner-private via
/// `firestore.rules`.
class AttachmentStore {
  AttachmentStore(this.uid);

  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _receiptDoc(String expenseId) =>
      _db.collection('users').doc(uid).collection('receipts').doc(expenseId);

  /// Store [base64] (already-encoded, already-downscaled) for [expenseId].
  Future<void> putReceipt(
    String expenseId,
    String base64, {
    String contentType = 'image/jpeg',
  }) =>
      _receiptDoc(expenseId).set({
        'data': base64,
        'contentType': contentType,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// The base64 payload for [expenseId], or null if there's no receipt.
  Future<String?> getReceipt(String expenseId) async {
    final snap = await _receiptDoc(expenseId).get();
    return snap.data()?['data'] as String?;
  }

  /// Best-effort delete; ignores "not found" so callers can fire-and-forget.
  Future<void> deleteReceipt(String expenseId) async {
    try {
      await _receiptDoc(expenseId).delete();
    } catch (_) {/* already gone, or never uploaded */}
  }
}
