import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/emi.dart';
import '../models/expense.dart';
import '../models/family_ledger.dart';
import '../models/member.dart';
import '../models/reminder.dart';
import '../models/salary.dart';
import '../models/target.dart';
import '../models/user_profile.dart';
import '../models/wallet_entry.dart';
import 'finance_repository.dart';

/// A local, on-device snapshot of the user's finance data so the app can open
/// **instantly** to the last-known state instead of blocking on a slow network
/// load (Google Drive downloads / Firestore fetches). The fresh copy is fetched
/// in the background and swapped in when it arrives.
///
/// Everything is serialised through the models' own row representation
/// (`toRow()` / `fromRow()`), which is already made of JSON-safe primitives
/// (strings, numbers, `yes`/`no`), so no per-model cache code is needed. All
/// operations are best-effort: any failure just means "no cache", never a crash.
class LocalCache {
  LocalCache._();

  static const _kPersonal = 'ff_cache_personal_v1';
  static const _kFamily = 'ff_cache_family_v1';

  static String _pKey(String email) => '${_kPersonal}_$email';
  static String _fKey(String familyId) => '${_kFamily}_$familyId';

  // --- personal --------------------------------------------------------------
  static Future<void> savePersonal(PersonalData d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        'fileId': d.fileId,
        'profile': d.profile.toRow(),
        'salaries': d.salaries.map((e) => e.toRow()).toList(),
        'expenses': d.expenses.map((e) => e.toRow()).toList(),
        'emis': d.emis.map((e) => e.toRow()).toList(),
        'targets': d.targets.map((e) => e.toRow()).toList(),
        'activities': d.activities.map((e) => e.toRow()).toList(),
        'categories': d.categories.map((e) => e.toRow()).toList(),
        'reminders': d.reminders.map((e) => e.toRow()).toList(),
        'budgets': d.budgets.map((e) => e.toRow()).toList(),
      };
      await prefs.setString(_pKey(d.profile.email), jsonEncode(map));
    } catch (_) {/* best-effort cache */}
  }

  static Future<PersonalData?> loadPersonal(String email,
      {String? photoUrl}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pKey(email));
      if (raw == null) return null;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();

      List<T> listOf<T>(String key, T Function(List<dynamic>) fromRow) =>
          ((m[key] as List?) ?? const [])
              .map((e) => fromRow((e as List).cast<dynamic>()))
              .toList();

      final profileRow = (m['profile'] as List?)?.cast<dynamic>();
      final profile = profileRow == null
          ? UserProfile(email: email, displayName: email, photoUrl: photoUrl)
          : UserProfile.fromRow(profileRow, photoUrl: photoUrl);

      final cats = listOf('categories', Category.fromRow);
      return PersonalData(
        fileId: (m['fileId'] as String?) ?? '',
        profile: profile,
        salaries: listOf('salaries', Salary.fromRow),
        expenses: listOf('expenses', Expense.fromRow),
        emis: listOf('emis', Emi.fromRow),
        targets: listOf('targets', Target.fromRow),
        activities: listOf('activities', Activity.fromRow),
        categories: cats.isEmpty ? Category.defaults() : cats,
        reminders: listOf('reminders', Reminder.fromRow),
        budgets: listOf('budgets', Budget.fromRow),
      );
    } catch (_) {
      return null;
    }
  }

  // --- family ----------------------------------------------------------------
  static Future<void> saveFamily(FamilyData d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        'fileId': d.fileId,
        'familyId': d.familyId,
        'familyName': d.familyName,
        'members': d.members.map((e) => e.toRow()).toList(),
        'wallet': d.wallet.map((e) => e.toRow()).toList(),
        'ledger': d.ledger.map((e) => e.toRow()).toList(),
        'tombstones': d.tombstones.toList(),
      };
      await prefs.setString(_fKey(d.familyId), jsonEncode(map));
    } catch (_) {/* best-effort cache */}
  }

  static Future<FamilyData?> loadFamily(String familyId) async {
    if (familyId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_fKey(familyId));
      if (raw == null) return null;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();

      List<T> listOf<T>(String key, T Function(List<dynamic>) fromRow) =>
          ((m[key] as List?) ?? const [])
              .map((e) => fromRow((e as List).cast<dynamic>()))
              .toList();

      return FamilyData(
        fileId: (m['fileId'] as String?) ?? '',
        familyId: (m['familyId'] as String?) ?? familyId,
        familyName: (m['familyName'] as String?) ?? '',
        members: listOf('members', Member.fromRow),
        wallet: listOf('wallet', WalletEntry.fromRow),
        ledger: listOf('ledger', FamilyLedgerEntry.fromRow),
        tombstones:
            ((m['tombstones'] as List?) ?? const []).map((e) => '$e').toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  // --- clear -----------------------------------------------------------------
  /// Drop this user's cached snapshot (used by "reset & start fresh").
  static Future<void> clear(String email, {String familyId = ''}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pKey(email));
      if (familyId.isNotEmpty) await prefs.remove(_fKey(familyId));
    } catch (_) {/* best-effort */}
  }
}
