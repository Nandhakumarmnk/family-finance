import 'package:flutter/foundation.dart';

import '../models/emi.dart';
import '../models/expense.dart';
import '../models/member.dart';
import '../models/salary.dart';
import '../models/target.dart';
import '../models/user_profile.dart';
import '../models/wallet_entry.dart';
import '../services/auth_service.dart';
import '../services/drive_service.dart';
import '../services/finance_repository.dart';

enum AppStatus { initializing, signedOut, signedIn, error }

/// Single source of truth for the UI. Owns auth, the two workbooks, the
/// selected reporting period, and all mutating operations (which persist to
/// Drive after updating the in-memory model).
class AppState extends ChangeNotifier {
  final AuthService _auth = AuthService();

  FinanceRepository? _repo;
  PersonalData? _personal;
  FamilyData? _family;

  AppStatus status = AppStatus.initializing;
  bool busy = false;
  String? error;

  // Selected period for the reports/dashboard view.
  late int selectedYear;
  late int selectedMonth;

  AppState() {
    final now = DateTime.now();
    selectedYear = now.year;
    selectedMonth = now.month;
  }

  // --- getters ---------------------------------------------------------------
  UserProfile? get profile => _personal?.profile;
  PersonalData? get personal => _personal;
  FamilyData? get family => _family;
  bool get inFamily => (_personal?.profile.familyId ?? '').isNotEmpty;
  String get currency => _personal?.profile.currencyCode ?? 'INR';

  List<Salary> get salaries => _personal?.salaries ?? const [];
  List<Expense> get expenses => _personal?.expenses ?? const [];
  List<Emi> get emis => _personal?.emis ?? const [];
  List<Target> get targets => _personal?.targets ?? const [];
  List<Member> get members => _family?.members ?? const [];
  List<WalletEntry> get wallet => _family?.wallet ?? const [];
  double get walletBalance => _family?.walletBalance ?? 0;

  // --- lifecycle -------------------------------------------------------------
  Future<void> init() async {
    status = AppStatus.initializing;
    notifyListeners();
    try {
      final account = await _auth.trySilentSignIn();
      if (account == null) {
        status = AppStatus.signedOut;
        notifyListeners();
        return;
      }
      await _onSignedIn();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> signIn() async {
    _setBusy(true);
    try {
      final account = await _auth.signIn();
      if (account == null) {
        status = AppStatus.signedOut;
        return;
      }
      await _onSignedIn();
    } catch (e) {
      _fail(e);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _personal = null;
    _family = null;
    _repo = null;
    status = AppStatus.signedOut;
    notifyListeners();
  }

  Future<void> _onSignedIn() async {
    final account = _auth.account!;
    final client = await _auth.authenticatedClient();
    if (client == null) {
      throw StateError('Could not obtain an authenticated Google client.');
    }
    _repo = FinanceRepository(DriveService(client));

    final seed = UserProfile(
      email: account.email,
      displayName: account.displayName ?? account.email,
      photoUrl: account.photoUrl,
    );
    _personal = await _repo!.loadPersonal(seed);

    if (inFamily) {
      await _loadFamily();
    }
    status = AppStatus.signedIn;
    notifyListeners();
  }

  Future<void> _loadFamily() async {
    final p = _personal!.profile;
    _family = await _repo!.loadFamily(
      p.familyId,
      p.familyName,
      creatorAsMember: Member(
        email: p.email,
        name: p.displayName,
        role: 'Owner',
        phone: p.phone,
      ),
    );
  }

  // --- profile / details -----------------------------------------------------
  Future<void> updateProfile({
    String? displayName,
    String? phone,
    String? occupation,
    String? currencyCode,
  }) async {
    final p = _personal!.profile;
    if (displayName != null) p.displayName = displayName;
    if (phone != null) p.phone = phone;
    if (occupation != null) p.occupation = occupation;
    if (currencyCode != null) p.currencyCode = currencyCode;
    await _persistPersonal();
  }

  // --- salary ----------------------------------------------------------------
  Future<void> addSalary(Salary s) async {
    _personal!.salaries.add(s);
    await _persistPersonal();
  }

  Future<void> deleteSalary(String id) async {
    _personal!.salaries.removeWhere((e) => e.id == id);
    await _persistPersonal();
  }

  // --- expenses --------------------------------------------------------------
  Future<void> addExpense(Expense e) async {
    _personal!.expenses.add(e);
    // An expense paid from the family wallet also records a wallet "spend".
    if (e.fromFamilyWallet && _family != null) {
      _family!.wallet.add(WalletEntry(
        id: 'w_${e.id}',
        date: e.date,
        memberEmail: _personal!.profile.email,
        memberName: _personal!.profile.displayName,
        direction: WalletDirection.spend,
        amount: e.amount,
        purpose: '${e.category}: ${e.notes}',
      ));
      await _persistFamily();
    }
    await _persistPersonal();
  }

  Future<void> deleteExpense(String id) async {
    _personal!.expenses.removeWhere((e) => e.id == id);
    await _persistPersonal();
  }

  // --- EMIs ------------------------------------------------------------------
  Future<void> addEmi(Emi emi) async {
    _personal!.emis.add(emi);
    await _persistPersonal();
  }

  Future<void> recordEmiPayment(String id) async {
    final emi = _personal!.emis.firstWhere((e) => e.id == id);
    if (emi.remainingMonths > 0) {
      emi.paidMonths += 1;
      // Recording an EMI payment also books an expense for that month.
      _personal!.expenses.add(Expense(
        id: 'emi_${emi.id}_${emi.paidMonths}',
        date: DateTime.now(),
        category: 'EMI',
        amount: emi.monthlyAmount,
        paymentMode: 'Bank',
        notes: '${emi.name} instalment ${emi.paidMonths}/${emi.totalMonths}',
      ));
    }
    await _persistPersonal();
  }

  Future<void> deleteEmi(String id) async {
    _personal!.emis.removeWhere((e) => e.id == id);
    await _persistPersonal();
  }

  // --- targets ---------------------------------------------------------------
  Future<void> setTarget(Target t) async {
    _personal!.targets.removeWhere((e) => e.year == t.year && e.month == t.month);
    _personal!.targets.add(t);
    await _persistPersonal();
  }

  Target? targetFor(int year, int month) {
    for (final t in targets) {
      if (t.year == year && t.month == month) return t;
    }
    return null;
  }

  // --- family / multi-user ---------------------------------------------------
  Future<void> createOrJoinFamily(String familyId, String familyName) async {
    final p = _personal!.profile;
    p.familyId = familyId.trim();
    p.familyName = familyName.trim();
    await _persistPersonal();
    await _loadFamily();
    notifyListeners();
  }

  Future<void> addOrUpdateMember(Member m) async {
    final idx = _family!.members.indexWhere((e) => e.email == m.email);
    if (idx >= 0) {
      _family!.members[idx] = m;
    } else {
      _family!.members.add(m);
    }
    await _persistFamily();
  }

  Future<void> removeMember(String email) async {
    _family!.members.removeWhere((e) => e.email == email);
    await _persistFamily();
  }

  Future<String?> inviteMember(String email) async {
    final link = await _repo!.shareFamily(_family!.fileId, email);
    // Pre-register the invited member so they show up immediately.
    if (!_family!.members.any((m) => m.email == email)) {
      _family!.members.add(Member(email: email, name: email.split('@').first));
      await _persistFamily();
    }
    return link;
  }

  // --- common wallet ---------------------------------------------------------
  Future<void> addWalletEntry(WalletEntry e) async {
    _family!.wallet.add(e);
    await _persistFamily();
  }

  Future<void> deleteWalletEntry(String id) async {
    _family!.wallet.removeWhere((e) => e.id == id);
    await _persistFamily();
  }

  // --- period selection ------------------------------------------------------
  void selectPeriod({int? year, int? month}) {
    if (year != null) selectedYear = year;
    if (month != null) selectedMonth = month;
    notifyListeners();
  }

  // ===========================================================================
  // Analytics — month-wise / year-wise aggregations used by reports & dashboard
  // ===========================================================================

  double incomeForMonth(int year, int month) => salaries
      .where((s) => s.year == year && s.month == month)
      .fold(0.0, (a, s) => a + s.amount);

  double expenseForMonth(int year, int month) => expenses
      .where((e) => e.year == year && e.month == month)
      .fold(0.0, (a, e) => a + e.amount);

  double incomeForYear(int year) =>
      salaries.where((s) => s.year == year).fold(0.0, (a, s) => a + s.amount);

  double expenseForYear(int year) =>
      expenses.where((e) => e.year == year).fold(0.0, (a, e) => a + e.amount);

  double savingsForMonth(int year, int month) =>
      incomeForMonth(year, month) - expenseForMonth(year, month);

  /// Map of category -> total spend for the given month.
  Map<String, double> categoryBreakdown(int year, int month) {
    final map = <String, double>{};
    for (final e in expenses.where((e) => e.year == year && e.month == month)) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  /// 12-element list of monthly expense totals for [year] (index 0 == Jan).
  List<double> monthlyExpenseSeries(int year) {
    final list = List<double>.filled(12, 0);
    for (final e in expenses.where((e) => e.year == year)) {
      list[e.month - 1] += e.amount;
    }
    return list;
  }

  List<double> monthlyIncomeSeries(int year) {
    final list = List<double>.filled(12, 0);
    for (final s in salaries.where((s) => s.year == year)) {
      list[s.month - 1] += s.amount;
    }
    return list;
  }

  /// Years that have any data, newest first (always includes the current year).
  List<int> get availableYears {
    final years = <int>{selectedYear, DateTime.now().year};
    for (final e in expenses) {
      years.add(e.year);
    }
    for (final s in salaries) {
      years.add(s.year);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  // EMI roll-ups.
  double get totalEmiMonthly =>
      emis.where((e) => !e.isClosed).fold(0.0, (a, e) => a + e.monthlyAmount);
  double get totalEmiRemaining =>
      emis.fold(0.0, (a, e) => a + e.amountRemaining);
  int get activeEmiCount => emis.where((e) => !e.isClosed).length;

  // --- internals -------------------------------------------------------------
  Future<void> _persistPersonal() async {
    notifyListeners(); // optimistic UI update
    _setBusy(true);
    try {
      await _repo!.savePersonal(_personal!);
    } catch (e) {
      error = 'Could not save to Drive: $e';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _persistFamily() async {
    notifyListeners();
    _setBusy(true);
    try {
      await _repo!.saveFamily(_family!);
    } catch (e) {
      error = 'Could not save family workbook: $e';
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool b) {
    busy = b;
    notifyListeners();
  }

  void _fail(Object e) {
    status = AppStatus.error;
    error = e.toString();
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
