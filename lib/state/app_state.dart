import 'package:flutter/foundation.dart';

import '../models/activity.dart';
import '../models/emi.dart';
import '../models/expense.dart';
import '../models/family_ledger.dart';
import '../models/member.dart';
import '../models/salary.dart';
import '../models/target.dart';
import '../models/user_profile.dart';
import '../models/wallet_entry.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
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
  List<Activity> get activities => _personal?.activities ?? const [];
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

    // Register with the daily-report backend now that we know the household
    // role (no-op unless a backend is configured). Fire-and-forget.
    BackendService.linkForDailyReport(
      account.serverAuthCode,
      familyId: _personal?.profile.familyId ?? '',
      role: _householdRole(),
    );
  }

  /// 'parent' if this user is the family owner, otherwise 'member'.
  String _householdRole() {
    final email = _personal?.profile.email ?? '';
    final me = members.where((m) => m.email == email);
    if (me.isNotEmpty && me.first.role.toLowerCase() == 'owner') return 'parent';
    return 'member';
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
    _logActivity('Added', 'Income', s.source, s.amount);
    final shared = _mirrorToFamily(
        id: s.id, date: s.date, type: 'income', category: s.source, amount: s.amount, notes: s.notes);
    if (shared) await _persistFamily();
    await _persistPersonal();
  }

  Future<void> deleteSalary(String id) async {
    final list = _personal!.salaries;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final s = list[idx];
      list.removeAt(idx);
      _logActivity('Deleted', 'Income', s.source, s.amount);
    }
    if (_unmirrorFromFamily(id)) await _persistFamily();
    await _persistPersonal();
  }

  // --- expenses --------------------------------------------------------------
  Future<void> addExpense(Expense e) async {
    _personal!.expenses.add(e);
    _logActivity('Added', 'Expense',
        '${e.category}${e.notes.isEmpty ? '' : ' — ${e.notes}'}', e.amount);
    var familyChanged = _mirrorToFamily(
        id: e.id, date: e.date, type: 'expense', category: e.category, amount: e.amount, notes: e.notes);
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
      familyChanged = true;
    }
    if (familyChanged) await _persistFamily();
    await _persistPersonal();
  }

  Future<void> deleteExpense(String id) async {
    final list = _personal!.expenses;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final e = list[idx];
      list.removeAt(idx);
      _logActivity('Deleted', 'Expense', e.category, e.amount);
    }
    if (_unmirrorFromFamily(id)) await _persistFamily();
    await _persistPersonal();
  }

  // --- EMIs ------------------------------------------------------------------
  Future<void> addEmi(Emi emi) async {
    _personal!.emis.add(emi);
    _logActivity('Added', 'EMI', emi.name, emi.monthlyAmount);
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
      _logActivity('Paid', 'EMI payment',
          '${emi.name} instalment ${emi.paidMonths}/${emi.totalMonths}',
          emi.monthlyAmount);
    }
    await _persistPersonal();
  }

  Future<void> deleteEmi(String id) async {
    final list = _personal!.emis;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final emi = list[idx];
      list.removeAt(idx);
      _logActivity('Deleted', 'EMI', emi.name, emi.monthlyAmount);
    }
    await _persistPersonal();
  }

  // --- targets ---------------------------------------------------------------
  Future<void> setTarget(Target t) async {
    _personal!.targets.removeWhere((e) => e.year == t.year && e.month == t.month);
    _personal!.targets.add(t);
    _logActivity('Updated', 'Target', 'Target for ${t.month}/${t.year}',
        t.savingsTarget);
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
    final kind = e.direction == WalletDirection.topUp ? 'Top-up' : 'Spend';
    _logActivity('Added', 'Wallet',
        '$kind${e.purpose.isEmpty ? '' : ' — ${e.purpose}'}', e.amount);
    await _persistFamily();
    await _persistPersonal();
  }

  Future<void> deleteWalletEntry(String id) async {
    final list = _family!.wallet;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final e = list[idx];
      list.removeAt(idx);
      final kind = e.direction == WalletDirection.topUp ? 'Top-up' : 'Spend';
      _logActivity('Deleted', 'Wallet', kind, e.amount);
    }
    await _persistFamily();
    await _persistPersonal();
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

  // --- activity log ----------------------------------------------------------
  /// Append an audit entry for a payment change. Newest first; capped so the
  /// workbook stays small. Caller persists afterwards.
  void _logActivity(String action, String type, String description,
      [double amount = 0]) {
    if (_personal == null) return;
    _personal!.activities.insert(
      0,
      Activity(
        id: 'a_${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        userEmail: _personal!.profile.email,
        action: action,
        type: type,
        description: description,
        amount: amount,
      ),
    );
    const maxEntries = 1000;
    if (_personal!.activities.length > maxEntries) {
      _personal!.activities.removeRange(maxEntries, _personal!.activities.length);
    }
  }

  // --- shared family ledger --------------------------------------------------
  /// Mirror a personal income/expense into the SHARED family workbook so the
  /// household (and the parent's daily report) sees everyone's activity.
  /// Returns true if the family workbook changed (caller persists it).
  bool _mirrorToFamily({
    required String id,
    required DateTime date,
    required String type,
    required String category,
    required double amount,
    required String notes,
  }) {
    if (_family == null || !inFamily) return false;
    _family!.ledger.add(FamilyLedgerEntry(
      id: id,
      date: date,
      memberEmail: _personal!.profile.email,
      memberName: _personal!.profile.displayName,
      type: type,
      category: category,
      amount: amount,
      notes: notes,
    ));
    return true;
  }

  /// Remove the shared copy of a personal entry. Returns true if removed.
  bool _unmirrorFromFamily(String id) {
    if (_family == null) return false;
    final before = _family!.ledger.length;
    _family!.ledger.removeWhere((e) => e.id == id);
    return _family!.ledger.length != before;
  }

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
    error = _friendlyError(e);
    notifyListeners();
  }

  /// Turn opaque platform errors into something a user can act on. The most
  /// common one on a fresh build is a Google Sign-In configuration problem,
  /// which surfaces as a null-check / DEVELOPER_ERROR (ApiException 10).
  String _friendlyError(Object e) {
    final s = e.toString();
    final isConfig = s.contains('Null check operator') ||
        s.contains('ApiException: 10') ||
        s.contains('sign_in_failed') ||
        s.contains('DEVELOPER_ERROR') ||
        s.contains('idpiframe') ||
        s.contains('popup') ||
        s.contains('origin');
    if (isConfig) {
      if (kIsWeb) {
        return 'Google Sign-In is not set up for the web app yet.\n\n'
            'A Web OAuth client must list this site as an authorized '
            'JavaScript origin, and its client ID must be embedded in the page.';
      }
      return 'Google Sign-In is not set up for this app build yet.\n\n'
          "This build's signing fingerprint (SHA-1) must be registered with "
          'an Android OAuth client in Google Cloud Console, for the package '
          'net.ramrajcotton.family_finance.';
    }
    return s;
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
