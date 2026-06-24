import 'dart:typed_data';

import '../models/activity.dart';
import '../models/emi.dart';
import '../models/expense.dart';
import '../models/family_ledger.dart';
import '../models/member.dart';
import '../models/salary.dart';
import '../models/target.dart';
import '../models/user_profile.dart';
import '../models/wallet_entry.dart';
import 'drive_service.dart';
import 'excel_codec.dart';

/// Reads and writes the two Excel workbooks (personal + shared family) that
/// back the whole app, using [DriveService] for transport and [ExcelCodec]
/// for (de)serialisation.
///
/// Workbook layout
/// ---------------
/// personal_<email>.xlsx
///   - Profile   (single row)
///   - Salary
///   - Expenses
///   - EMIs
///   - Targets
/// family_<familyId>.xlsx   (shared with family members on Drive)
///   - Members
///   - Wallet
class FinanceRepository {
  FinanceRepository(this._drive);

  final DriveService _drive;

  // Sheet names.
  static const _sProfile = 'Profile';
  static const _sSalary = 'Salary';
  static const _sExpenses = 'Expenses';
  static const _sEmis = 'EMIs';
  static const _sTargets = 'Targets';
  static const _sMembers = 'Members';
  static const _sWallet = 'Wallet';
  static const _sActivity = 'Activity';
  static const _sFamilyLedger = 'FamilyLedger';
  static const _sTombstones = 'Deleted';

  String _personalFileName(String email) =>
      'personal_${_sanitize(email)}.xlsx';
  String _familyFileName(String familyId) => 'family_$familyId.xlsx';

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  // ---------------------------------------------------------------------------
  // Personal workbook
  // ---------------------------------------------------------------------------

  /// Loads the personal workbook into a [PersonalData]. If the file does not
  /// exist yet it is created with [seedProfile].
  Future<PersonalData> loadPersonal(UserProfile seedProfile) async {
    final folderId = await _drive.ensureAppFolder();
    final name = _personalFileName(seedProfile.email);
    final fileId = await _drive.findFile(name, parentId: folderId);

    if (fileId == null) {
      final data = PersonalData(
        fileId: '',
        profile: seedProfile,
        salaries: [],
        expenses: [],
        emis: [],
        targets: [],
        activities: [],
      );
      data.fileId = await _savePersonal(data, folderId: folderId, name: name);
      return data;
    }

    final bytes = await _drive.downloadBytes(fileId);
    final wb = ExcelCodec.decode(bytes);

    final profileRows = ExcelCodec.dataRows(wb, _sProfile);
    final profile = profileRows.isEmpty
        ? seedProfile
        : UserProfile.fromRow(profileRows.first, photoUrl: seedProfile.photoUrl);
    // Always trust the live identity from Google for these fields.
    final merged = UserProfile(
      email: seedProfile.email,
      displayName:
          profile.displayName.isEmpty ? seedProfile.displayName : profile.displayName,
      photoUrl: seedProfile.photoUrl,
      familyId: profile.familyId,
      familyName: profile.familyName,
      currencyCode: profile.currencyCode,
      phone: profile.phone,
      occupation: profile.occupation,
    );

    return PersonalData(
      fileId: fileId,
      profile: merged,
      salaries: ExcelCodec.dataRows(wb, _sSalary).map(Salary.fromRow).toList(),
      expenses:
          ExcelCodec.dataRows(wb, _sExpenses).map(Expense.fromRow).toList(),
      emis: ExcelCodec.dataRows(wb, _sEmis).map(Emi.fromRow).toList(),
      targets: ExcelCodec.dataRows(wb, _sTargets).map(Target.fromRow).toList(),
      activities:
          ExcelCodec.dataRows(wb, _sActivity).map(Activity.fromRow).toList(),
    );
  }

  Future<void> savePersonal(PersonalData data) async {
    final folderId = await _drive.ensureAppFolder();
    final name = _personalFileName(data.profile.email);
    data.fileId = await _savePersonal(data, folderId: folderId, name: name);
  }

  Future<String> _savePersonal(
    PersonalData data, {
    required String folderId,
    required String name,
  }) async {
    final sheets = <String, List<List<dynamic>>>{
      _sProfile: [UserProfile.profileHeader, data.profile.toRow()],
      _sSalary: [Salary.header, ...data.salaries.map((e) => e.toRow())],
      _sExpenses: [Expense.header, ...data.expenses.map((e) => e.toRow())],
      _sEmis: [Emi.header, ...data.emis.map((e) => e.toRow())],
      _sTargets: [Target.header, ...data.targets.map((e) => e.toRow())],
      _sActivity: [Activity.header, ...data.activities.map((e) => e.toRow())],
    };
    final bytes = ExcelCodec.encode(sheets);
    return _drive.upsertXlsx(name, bytes, parentId: folderId);
  }

  // ---------------------------------------------------------------------------
  // Shared family workbook
  // ---------------------------------------------------------------------------

  /// Load (or create) the shared family workbook for [familyId].
  ///
  /// The workbook is a single shared file: the household owner creates it and
  /// shares it with each member, so it usually lives in ANOTHER account's
  /// Drive. We therefore look for it across the whole Drive (not just our own
  /// app folder) and only create a fresh one when nobody in the family has set
  /// it up yet.
  Future<FamilyData> loadFamily(
    String familyId,
    String familyName, {
    required Member creatorAsMember,
  }) async {
    final name = _familyFileName(familyId);
    final fileId = await _drive.findSharedFile(name);

    if (fileId == null) {
      final folderId = await _drive.ensureAppFolder();
      final data = FamilyData(
        fileId: '',
        familyId: familyId,
        familyName: familyName,
        members: [creatorAsMember],
        wallet: [],
        ledger: [],
        tombstones: {},
      );
      data.fileId = await _drive.createXlsx(
        name,
        _encodeFamily(data),
        parentId: folderId,
      );
      return data;
    }

    final bytes = await _drive.downloadBytes(fileId);
    final wb = ExcelCodec.decode(bytes);
    return FamilyData(
      fileId: fileId,
      familyId: familyId,
      familyName: familyName,
      members: ExcelCodec.dataRows(wb, _sMembers).map(Member.fromRow).toList(),
      wallet:
          ExcelCodec.dataRows(wb, _sWallet).map(WalletEntry.fromRow).toList(),
      ledger: ExcelCodec.dataRows(wb, _sFamilyLedger)
          .map(FamilyLedgerEntry.fromRow)
          .toList(),
      tombstones: _readTombstones(wb),
    );
  }

  /// Persist the shared family workbook. Because several family members write
  /// to the SAME file from different devices, we first re-read the latest
  /// remote copy and merge it in — so one member's save never silently wipes
  /// entries another member added (the bug behind "common expenses don't show
  /// the other account's data"). Writes back to the same file id; never forks
  /// a private copy.
  Future<void> saveFamily(FamilyData data) async {
    if (data.fileId.isNotEmpty) {
      try {
        final remote = ExcelCodec.decode(await _drive.downloadBytes(data.fileId));
        _mergeRemoteIntoFamily(data, remote);
      } catch (_) {
        // Remote unreadable (offline / just deleted) — write what we have.
      }
      await _drive.updateXlsx(data.fileId, _encodeFamily(data));
      return;
    }
    // No id yet: locate the shared copy if one exists, otherwise create it.
    final name = _familyFileName(data.familyId);
    final existing = await _drive.findSharedFile(name);
    if (existing != null) {
      data.fileId = existing;
      await saveFamily(data); // now takes the merge-and-update path above
      return;
    }
    final folderId = await _drive.ensureAppFolder();
    data.fileId =
        await _drive.createXlsx(name, _encodeFamily(data), parentId: folderId);
  }

  Uint8List _encodeFamily(FamilyData data) {
    final sheets = <String, List<List<dynamic>>>{
      _sMembers: [Member.header, ...data.members.map((e) => e.toRow())],
      _sWallet: [WalletEntry.header, ...data.wallet.map((e) => e.toRow())],
      _sFamilyLedger: [
        FamilyLedgerEntry.header,
        ...data.ledger.map((e) => e.toRow())
      ],
      _sTombstones: [
        const ['id'],
        ...data.tombstones.map((id) => [id]),
      ],
    };
    return ExcelCodec.encode(sheets);
  }

  Set<String> _readTombstones(Map<String, List<List<dynamic>>> wb) =>
      ExcelCodec.dataRows(wb, _sTombstones)
          .where((r) => r.isNotEmpty)
          .map((r) => '${r.first}'.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

  /// Merge the remote workbook [wb] into the in-memory [data]:
  ///   * tombstones (deletes) are unioned — a delete by anyone wins;
  ///   * members / wallet / ledger are unioned by key, with our local copy
  ///     winning field conflicts, and anything tombstoned removed.
  /// This keeps every member's additions while still letting deletes
  /// propagate across accounts.
  void _mergeRemoteIntoFamily(
      FamilyData data, Map<String, List<List<dynamic>>> wb) {
    data.tombstones.addAll(_readTombstones(wb));
    final dead = data.tombstones;

    final remoteMembers =
        ExcelCodec.dataRows(wb, _sMembers).map(Member.fromRow).toList();
    final remoteWallet =
        ExcelCodec.dataRows(wb, _sWallet).map(WalletEntry.fromRow).toList();
    final remoteLedger = ExcelCodec.dataRows(wb, _sFamilyLedger)
        .map(FamilyLedgerEntry.fromRow)
        .toList();

    _unionInto<Member>(data.members, remoteMembers, (m) => m.email, dead);
    _unionInto<WalletEntry>(data.wallet, remoteWallet, (e) => e.id, dead);
    _unionInto<FamilyLedgerEntry>(
        data.ledger, remoteLedger, (e) => e.id, dead);
  }

  /// Add any [remote] items whose key isn't already present in [local]
  /// (local wins on conflict), then drop everything whose key is tombstoned.
  static void _unionInto<T>(
    List<T> local,
    List<T> remote,
    String Function(T) keyOf,
    Set<String> dead,
  ) {
    final have = local.map(keyOf).toSet();
    for (final r in remote) {
      final k = keyOf(r);
      if (have.add(k)) local.add(r);
    }
    local.removeWhere((e) => dead.contains(keyOf(e)));
  }

  /// Invite another user to the family workbook (Drive permission + email).
  Future<String?> shareFamily(String fileId, String email) async {
    await _drive.shareWith(fileId, email);
    return _drive.webLink(fileId);
  }

  /// Export arbitrary bytes (e.g. a generated report) — exposed for reuse.
  Future<String> exportReport(String name, Uint8List bytes) async {
    final folderId = await _drive.ensureAppFolder();
    return _drive.upsertXlsx(name, bytes, parentId: folderId);
  }

  /// A web link to open a stored file (e.g. the personal workbook in Sheets).
  Future<String?> fileWebLink(String fileId) => _drive.webLink(fileId);
}

/// In-memory contents of the personal workbook.
class PersonalData {
  String fileId;
  UserProfile profile;
  final List<Salary> salaries;
  final List<Expense> expenses;
  final List<Emi> emis;
  final List<Target> targets;
  final List<Activity> activities;

  PersonalData({
    required this.fileId,
    required this.profile,
    required this.salaries,
    required this.expenses,
    required this.emis,
    required this.targets,
    required this.activities,
  });
}

/// In-memory contents of the shared family workbook.
class FamilyData {
  String fileId;
  final String familyId;
  final String familyName;
  final List<Member> members;
  final List<WalletEntry> wallet;
  final List<FamilyLedgerEntry> ledger;

  /// Keys (entry ids / member emails) that have been deleted. Persisted so a
  /// delete on one device isn't resurrected when another device merges its
  /// older copy back in.
  final Set<String> tombstones;

  FamilyData({
    required this.fileId,
    required this.familyId,
    required this.familyName,
    required this.members,
    required this.wallet,
    required this.ledger,
    Set<String>? tombstones,
  }) : tombstones = tombstones ?? <String>{};

  double get walletBalance =>
      wallet.fold(0.0, (sum, e) => sum + e.signedAmount);
}
