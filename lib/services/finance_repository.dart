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
  Future<FamilyData> loadFamily(
    String familyId,
    String familyName, {
    required Member creatorAsMember,
  }) async {
    final folderId = await _drive.ensureAppFolder();
    final name = _familyFileName(familyId);
    final fileId = await _drive.findFile(name, parentId: folderId);

    if (fileId == null) {
      final data = FamilyData(
        fileId: '',
        familyId: familyId,
        familyName: familyName,
        members: [creatorAsMember],
        wallet: [],
        ledger: [],
      );
      data.fileId = await _saveFamily(data, folderId: folderId, name: name);
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
    );
  }

  Future<void> saveFamily(FamilyData data) async {
    final folderId = await _drive.ensureAppFolder();
    final name = _familyFileName(data.familyId);
    data.fileId = await _saveFamily(data, folderId: folderId, name: name);
  }

  Future<String> _saveFamily(
    FamilyData data, {
    required String folderId,
    required String name,
  }) async {
    final sheets = <String, List<List<dynamic>>>{
      _sMembers: [Member.header, ...data.members.map((e) => e.toRow())],
      _sWallet: [WalletEntry.header, ...data.wallet.map((e) => e.toRow())],
      _sFamilyLedger: [
        FamilyLedgerEntry.header,
        ...data.ledger.map((e) => e.toRow())
      ],
    };
    final bytes = ExcelCodec.encode(sheets);
    return _drive.upsertXlsx(name, bytes, parentId: folderId);
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

  FamilyData({
    required this.fileId,
    required this.familyId,
    required this.familyName,
    required this.members,
    required this.wallet,
    required this.ledger,
  });

  double get walletBalance =>
      wallet.fold(0.0, (sum, e) => sum + e.signedAmount);
}
