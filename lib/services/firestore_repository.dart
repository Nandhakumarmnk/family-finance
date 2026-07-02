import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/emi.dart';
import '../models/expense.dart';
import '../models/family_ledger.dart';
import '../models/join_request.dart';
import '../models/member.dart';
import '../models/reminder.dart';
import '../models/salary.dart';
import '../models/target.dart';
import '../models/user_profile.dart';
import '../models/wallet_entry.dart';
import 'finance_repository.dart';

/// Cloud Firestore implementation of [FinanceStore] — the free, global backend.
///
/// Layout (mirrors the old workbooks, but as real cloud data):
///   users/{uid}                       one doc: profile + personal arrays
///   families/{familyId}               { familyName, ownerEmail, memberEmails }
///   families/{familyId}/members/{e}   one doc per member
///   families/{familyId}/wallet/{id}   one doc per wallet entry
///   families/{familyId}/ledger/{id}   one doc per shared income/expense
///
/// Each row is stored as a Map keyed by the model's own `header`, so we reuse
/// the existing `toRow()`/`fromRow()` serialisation with zero per-model work.
/// Family data lives in **subcollections** (one doc per entry) so two members
/// editing from different phones never overwrite each other — real deletes
/// replace the old Drive "tombstone" merge dance entirely.
class FirestoreRepository implements FinanceStore {
  FirestoreRepository({required this.uid});

  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _families =>
      _db.collection('families');

  // --- (de)serialisation helpers --------------------------------------------
  static Map<String, dynamic> _rowToMap(
      List<String> header, List<dynamic> row) {
    final m = <String, dynamic>{};
    for (var i = 0; i < header.length; i++) {
      m[header[i]] = i < row.length ? row[i] : null;
    }
    return m;
  }

  static List<dynamic> _mapToRow(
          List<String> header, Map<String, dynamic> map) =>
      header.map((h) => map[h]).toList();

  static String _key(String s) => s.replaceAll('/', '_').trim();

  // ---------------------------------------------------------------------------
  // Personal — a single document per user (single writer, so no merge needed).
  // ---------------------------------------------------------------------------
  @override
  Future<PersonalData> loadPersonal(UserProfile seedProfile) async {
    final ref = _users.doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      final data = PersonalData(
        fileId: uid,
        profile: seedProfile,
        salaries: [],
        expenses: [],
        emis: [],
        targets: [],
        activities: [],
        categories: Category.defaults(),
        reminders: [],
        budgets: [],
      );
      await _writePersonal(data);
      return data;
    }

    final d = snap.data()!;
    final profileMap =
        (d['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    final stored = profileMap.isEmpty
        ? seedProfile
        : UserProfile.fromRow(
            _mapToRow(UserProfile.profileHeader, profileMap),
            photoUrl: seedProfile.photoUrl);
    // Always trust the live Google identity for email + photo.
    final profile = UserProfile(
      email: seedProfile.email,
      displayName: stored.displayName.isEmpty
          ? seedProfile.displayName
          : stored.displayName,
      photoUrl: seedProfile.photoUrl,
      familyId: stored.familyId,
      familyName: stored.familyName,
      currencyCode: stored.currencyCode,
      phone: stored.phone,
      occupation: stored.occupation,
      pendingFamilyId: stored.pendingFamilyId,
      pendingFamilyName: stored.pendingFamilyName,
      customPhotoUrl: stored.customPhotoUrl,
    );

    List<T> listOf<T>(
        String key, List<String> header, T Function(List<dynamic>) fromRow) {
      final raw = (d[key] as List?) ?? const [];
      return raw
          .map((e) =>
              fromRow(_mapToRow(header, (e as Map).cast<String, dynamic>())))
          .toList();
    }

    final cats = listOf<Category>('categories', Category.header, Category.fromRow);
    return PersonalData(
      fileId: uid,
      profile: profile,
      salaries: listOf('salaries', Salary.header, Salary.fromRow),
      expenses: listOf('expenses', Expense.header, Expense.fromRow),
      emis: listOf('emis', Emi.header, Emi.fromRow),
      targets: listOf('targets', Target.header, Target.fromRow),
      activities: listOf('activities', Activity.header, Activity.fromRow),
      categories: cats.isEmpty ? Category.defaults() : cats,
      reminders: listOf('reminders', Reminder.header, Reminder.fromRow),
      budgets: listOf('budgets', Budget.header, Budget.fromRow),
    );
  }

  @override
  Future<void> savePersonal(PersonalData data) => _writePersonal(data);

  Future<void> _writePersonal(PersonalData data) async {
    List<Map<String, dynamic>> rows<T>(
            List<T> items, List<String> header, List<dynamic> Function(T) row) =>
        items.map((e) => _rowToMap(header, row(e))).toList();

    await _users.doc(uid).set({
      'profile': _rowToMap(UserProfile.profileHeader, data.profile.toRow()),
      'salaries': rows(data.salaries, Salary.header, (e) => e.toRow()),
      'expenses': rows(data.expenses, Expense.header, (e) => e.toRow()),
      'emis': rows(data.emis, Emi.header, (e) => e.toRow()),
      'targets': rows(data.targets, Target.header, (e) => e.toRow()),
      'activities': rows(data.activities, Activity.header, (e) => e.toRow()),
      'categories': rows(data.categories, Category.header, (e) => e.toRow()),
      'reminders': rows(data.reminders, Reminder.header, (e) => e.toRow()),
      'budgets': rows(data.budgets, Budget.header, (e) => e.toRow()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Family — a doc + subcollections shared by every member.
  // ---------------------------------------------------------------------------
  @override
  Future<FamilyData> loadFamily(
    String familyId,
    String familyName, {
    required Member creatorAsMember,
  }) async {
    final famRef = _families.doc(familyId);
    final snap = await famRef.get();

    if (!snap.exists) {
      final data = FamilyData(
        fileId: familyId,
        familyId: familyId,
        familyName: familyName,
        members: [creatorAsMember],
        wallet: [],
        ledger: [],
        tombstones: {},
      );
      await _createFamily(data, creatorAsMember.email);
      return data;
    }

    final d = snap.data()!;
    final storedName = (d['familyName'] as String?) ?? '';
    // NOTE: we no longer silently add the caller to `memberEmails` here — that
    // was the hole that let anyone with a code join (or take over) a family.
    // A prospective member now files a join request and the head approves it;
    // loadFamily is only reached once the caller is already an approved member.
    final members =
        await _readSub(famRef.collection('members'), Member.header, Member.fromRow);
    final wallet = await _readSub(
        famRef.collection('wallet'), WalletEntry.header, WalletEntry.fromRow);
    final ledger = await _readSub(famRef.collection('ledger'),
        FamilyLedgerEntry.header, FamilyLedgerEntry.fromRow);

    return FamilyData(
      fileId: familyId,
      familyId: familyId,
      familyName: storedName.isEmpty ? familyName : storedName,
      members: members,
      wallet: wallet,
      ledger: ledger,
      tombstones: {},
    );
  }

  Future<List<T>> _readSub<T>(
    CollectionReference<Map<String, dynamic>> col,
    List<String> header,
    T Function(List<dynamic>) fromRow,
  ) async {
    final q = await col.get();
    return q.docs.map((doc) => fromRow(_mapToRow(header, doc.data()))).toList();
  }

  /// Shared FINANCES only (wallet + ledger). Any approved member may call this;
  /// it never touches the family doc, membership, or roles — so a member adding
  /// an expense can't rewrite who's in the family or promote themselves.
  @override
  Future<void> saveFamily(FamilyData data, {bool overwriteName = false}) async {
    final famRef = _families.doc(data.familyId);
    final ops = <void Function(WriteBatch)>[];
    await _collectReconcile(
        ops,
        famRef.collection('wallet'),
        {for (final w in data.wallet) w.id: _rowToMap(WalletEntry.header, w.toRow())});
    await _collectReconcile(
        ops,
        famRef.collection('ledger'),
        {for (final l in data.ledger) l.id: _rowToMap(FamilyLedgerEntry.header, l.toRow())});
    await _commitChunked(ops);
  }

  /// The ROSTER: family name + memberEmails + the members/roles subcollection.
  /// The rules only permit the head to do this, so it's the single choke point
  /// for who belongs to the family and what role they hold.
  @override
  Future<void> saveFamilyRoster(FamilyData data,
      {bool overwriteName = false}) async {
    final famRef = _families.doc(data.familyId);
    await famRef.set({
      'familyName': data.familyName,
      'memberEmails': data.members.map((m) => m.email).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final ops = <void Function(WriteBatch)>[];
    await _collectReconcile(
        ops,
        famRef.collection('members'),
        {for (final m in data.members) _key(m.email): _rowToMap(Member.header, m.toRow())});
    await _commitChunked(ops);
  }

  /// First-time creation of a family, by its head. Writes the family doc
  /// (stamping `ownerEmail` — which the rules pin for good) plus the initial
  /// members / wallet / ledger.
  Future<void> _createFamily(FamilyData data, String ownerEmail) async {
    final famRef = _families.doc(data.familyId);
    await famRef.set({
      'familyName': data.familyName,
      'ownerEmail': ownerEmail,
      'memberEmails': data.members.map((m) => m.email).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final ops = <void Function(WriteBatch)>[];
    await _collectReconcile(
        ops,
        famRef.collection('members'),
        {for (final m in data.members) _key(m.email): _rowToMap(Member.header, m.toRow())});
    await _collectReconcile(
        ops,
        famRef.collection('wallet'),
        {for (final w in data.wallet) w.id: _rowToMap(WalletEntry.header, w.toRow())});
    await _collectReconcile(
        ops,
        famRef.collection('ledger'),
        {for (final l in data.ledger) l.id: _rowToMap(FamilyLedgerEntry.header, l.toRow())});
    await _commitChunked(ops);
  }

  // --- head-approval join flow ----------------------------------------------
  @override
  Future<FamilyMeta?> fetchFamilyMeta(String familyId) async {
    final snap = await _families.doc(familyId).get();
    if (!snap.exists) return null;
    final d = snap.data()!;
    return FamilyMeta(
      familyId: familyId,
      familyName: (d['familyName'] as String?) ?? '',
      ownerEmail: (d['ownerEmail'] as String?) ?? '',
      memberEmails:
          ((d['memberEmails'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }

  @override
  Future<void> requestToJoin(String familyId,
      {required String email,
      required String name,
      required String phone}) async {
    await _families
        .doc(familyId)
        .collection('joinRequests')
        .doc(_key(email))
        .set({
      'email': email,
      'name': name,
      'phone': phone,
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<bool> joinRequestPending(String familyId, String email) async {
    final snap = await _families
        .doc(familyId)
        .collection('joinRequests')
        .doc(_key(email))
        .get();
    return snap.exists;
  }

  @override
  Future<List<JoinRequest>> loadJoinRequests(String familyId) async {
    final q =
        await _families.doc(familyId).collection('joinRequests').get();
    return q.docs.map((doc) {
      final d = doc.data();
      return JoinRequest(
        email: (d['email'] as String?) ?? '',
        name: (d['name'] as String?) ?? '',
        phone: (d['phone'] as String?) ?? '',
      );
    }).toList();
  }

  @override
  Future<void> declineJoinRequest(String familyId, String email) async {
    await _families
        .doc(familyId)
        .collection('joinRequests')
        .doc(_key(email))
        .delete();
  }

  /// Add set-ops for every desired doc and delete-ops for docs no longer
  /// present, so the subcollection ends up matching [desired] exactly.
  Future<void> _collectReconcile(
    List<void Function(WriteBatch)> ops,
    CollectionReference<Map<String, dynamic>> col,
    Map<String, Map<String, dynamic>> desired,
  ) async {
    final existing = await col.get();
    desired.forEach((id, m) => ops.add((b) => b.set(col.doc(id), m)));
    for (final doc in existing.docs) {
      if (!desired.containsKey(doc.id)) {
        ops.add((b) => b.delete(col.doc(doc.id)));
      }
    }
  }

  /// Commit batched writes in chunks below Firestore's 500-op-per-batch limit.
  Future<void> _commitChunked(List<void Function(WriteBatch)> ops) async {
    const chunk = 450;
    for (var i = 0; i < ops.length; i += chunk) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(chunk)) {
        op(batch);
      }
      await batch.commit();
    }
  }

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------
  /// "Reset & start fresh": delete this user's doc, or (best-effort) the family
  /// doc if [fileId] is a family id and the rules permit it.
  @override
  Future<void> trashFile(String fileId) async {
    try {
      await _users.doc(fileId).delete();
    } catch (_) {/* not a user id, or already gone */}
    try {
      await _families.doc(fileId).delete();
    } catch (_) {/* not the owner, or not a family id */}
  }

  /// No external "open in Sheets" link in the cloud backend.
  @override
  Future<String?> fileWebLink(String fileId) async => null;
}
