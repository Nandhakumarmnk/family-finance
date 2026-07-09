// `Category` is also the name of a Flutter foundation annotation, so hide it to
// avoid an ambiguous-import clash with our own `Category` model below.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

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
import '../services/attachment_store.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/drive_service.dart';
import '../services/firestore_repository.dart';
import '../services/local_cache.dart';
import '../services/notification_service.dart';
import '../utils/format.dart';
import '../utils/image_data.dart';
import '../widgets/feedback.dart';
import '../services/finance_repository.dart';

enum AppStatus { initializing, signedOut, signedIn, error }

/// Outcome of attempting to join a family, so the UI can respond precisely.
enum JoinResult {
  joined, // fully in (legacy, or approved re-join)
  requested, // request filed — waiting for the head to approve
  declined, // request was removed / family gone
  notFound, // no family for that code
  invalidCode, // empty / malformed code
  error, // something went wrong
}

/// Single source of truth for the UI. Owns auth, the two workbooks, the
/// selected reporting period, and all mutating operations (which persist to
/// Drive after updating the in-memory model).
class AppState extends ChangeNotifier {
  final bool _firestoreEnabled;
  late final AuthService _auth;

  FinanceStore? _repo;
  AttachmentStore? _attachments;
  PersonalData? _personal;
  FamilyData? _family;

  AppStatus status = AppStatus.initializing;
  bool busy = false;
  String? error;

  /// Set once the user chooses to skip family setup (solo use). Persisted
  /// per-account so the onboarding screen doesn't nag on every launch.
  bool _familySetupDismissed = false;

  /// True while a fresh copy is being fetched in the background after the app
  /// opened instantly from the local cache. Lets the UI show a subtle "syncing"
  /// hint without blocking interaction.
  bool _refreshing = false;
  bool get refreshing => _refreshing;

  /// Bumped on every mutation. Used so a background refresh started from the
  /// cache never clobbers a change the user made while it was still loading.
  int _mutationCounter = 0;

  // Selected period for the reports/dashboard view.
  late int selectedYear;
  late int selectedMonth;

  AppState({bool firestoreEnabled = false})
      : _firestoreEnabled = firestoreEnabled {
    _auth = AuthService(useFirebase: firestoreEnabled);
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

  // --- app settings (persisted on the profile → synced to the cloud) --------
  /// Whether reminder notifications are enabled (defaults to on).
  bool get notificationsEnabled =>
      _personal?.profile.notificationsEnabled ?? true;

  /// Hour of day (0–23) reminder notifications fire at (defaults to 9am).
  int get reminderHour => _personal?.profile.reminderHour ?? 9;

  /// Stored appearance mode name ('' when the user hasn't chosen one yet).
  String get themeModeName => _personal?.profile.themeMode ?? '';

  /// Stored colour-theme seed as an ARGB int (0 when unset).
  int get themeSeedValue => _personal?.profile.themeSeed ?? 0;

  /// Persist the chosen appearance (theme mode + colour) to the profile so it
  /// follows the user across devices. Called by the theme bridge in main.dart.
  Future<void> updateAppearance({String? themeMode, int? themeSeed}) async {
    if (_personal == null) return;
    if (themeMode != null) _personal!.profile.themeMode = themeMode;
    if (themeSeed != null) _personal!.profile.themeSeed = themeSeed;
    await _persistPersonal();
  }

  /// Turn reminder notifications on/off; re-syncs the device schedule.
  Future<void> setNotificationsEnabled(bool value) async {
    if (_personal == null) return;
    _personal!.profile.notificationsEnabled = value;
    await _persistPersonal();
    _celebrate(value ? 'Notifications on' : 'Notifications off');
  }

  /// Set the hour (0–23) reminder notifications fire; re-syncs the schedule.
  Future<void> setReminderHour(int hour) async {
    if (_personal == null) return;
    _personal!.profile.reminderHour = hour.clamp(0, 23);
    await _persistPersonal();
    _celebrate('Reminder time updated');
  }

  /// Sentinel stored in `Expense.receiptUrl` when a receipt lives in Firestore
  /// (rather than as a legacy http URL). Only its non-emptiness matters to the
  /// model (`hasReceipt`); the image itself is fetched on demand by expense id.
  static const String _receiptMarker = 'fs:receipt';

  /// Guardrail: reject a receipt whose base64 would risk Firestore's 1 MiB
  /// per-document limit (leaves headroom for field names + metadata).
  static const int _maxReceiptBase64 = 900 * 1024;

  /// Whether file attachments (receipt photos, profile picture) are available —
  /// true on the Firestore backend once signed in. Attachments are stored as
  /// base64 in Firestore, so no Cloud Storage bucket (or Blaze plan) is needed.
  bool get canAttachFiles => _attachments != null;

  /// True when the app runs on the global Firestore backend (vs legacy Drive).
  /// Lets screens adapt copy that would otherwise promise Drive storage.
  bool get cloudBackend => _firestoreEnabled;

  /// True if the signed-in user is the family head (the Owner of the family).
  bool get isFamilyHead {
    final email = _personal?.profile.email ?? '';
    final me = members.where((m) => m.email == email);
    return me.isNotEmpty && me.first.role.toLowerCase() == 'owner';
  }

  /// A short label for the user's household role; '' when not in a family.
  String get roleLabel =>
      !inFamily ? '' : (isFamilyHead ? 'Family head' : 'Member');

  /// The family code (== Family ID) the head shares so others can join.
  String get familyCode => _personal?.profile.familyId ?? '';

  /// Whether to show the one-time "set up your family" onboarding screen.
  bool get needsFamilySetup =>
      status == AppStatus.signedIn && !inFamily && !_familySetupDismissed;

  List<Salary> get salaries => _personal?.salaries ?? const [];
  List<Expense> get expenses => _personal?.expenses ?? const [];
  List<Emi> get emis => _personal?.emis ?? const [];
  List<Target> get targets => _personal?.targets ?? const [];
  List<Member> get members => _family?.members ?? const [];
  List<WalletEntry> get wallet => _family?.wallet ?? const [];
  List<Activity> get activities => _personal?.activities ?? const [];
  double get walletBalance => _family?.walletBalance ?? 0;

  // --- payment reminders -----------------------------------------------------
  List<Reminder> get reminders => _personal?.reminders ?? const [];

  /// Active reminders, soonest-due first; paused ones sink to the bottom.
  List<Reminder> get remindersSorted {
    final list = [...reminders];
    list.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.dueDate.compareTo(b.dueDate);
    });
    return list;
  }

  /// Reminders past their due date (active only), most overdue first.
  List<Reminder> get overdueReminders =>
      (reminders.where((r) => r.status == ReminderStatus.overdue).toList())
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// Active reminders that need attention now — overdue or within the
  /// "due soon" window — soonest-due first. Drives the dashboard alert.
  List<Reminder> get dueReminders =>
      (reminders.where((r) => r.needsAttention).toList())
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// Count of reminders needing attention (badge value).
  int get dueReminderCount => reminders.where((r) => r.needsAttention).length;

  /// Total monthly-equivalent commitment across active reminders (rough: only
  /// counts monthly ones, used for an at-a-glance figure).
  double get reminderMonthlyOutgo => reminders
      .where((r) => r.active && r.recurrence == Recurrence.monthly)
      .fold(0.0, (a, r) => a + r.amount);

  /// Editable expense categories (the "category master").
  List<Category> get categories => _personal?.categories ?? const [];
  List<String> get categoryNames => categories.map((c) => c.name).toList();

  /// The icon key stored for [categoryName] ('category' if not found) — the UI
  /// resolves it to an icon via CategoryIcons.byKey.
  String iconKeyFor(String categoryName) {
    for (final c in categories) {
      if (c.name == categoryName) return c.iconKey;
    }
    return 'category';
  }

  /// Every family member's income/expenses, mirrored into the shared workbook.
  List<FamilyLedgerEntry> get familyLedger => _family?.ledger ?? const [];

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
    await NotificationService.cancelAll();
    _personal = null;
    _family = null;
    _repo = null;
    _attachments = null;
    _refreshing = false;
    status = AppStatus.signedOut;
    notifyListeners();
  }

  /// Full "reset & start fresh": move this account's workbooks (personal +
  /// shared family) to the Drive trash, then sign out. The Drive deletes are
  /// best-effort and per-file — a member who doesn't own the shared family file
  /// simply can't trash it, so their reset clears only their own personal data
  /// while the owner's reset clears the family file for the whole household.
  /// Callers also clear the local PIN afterwards.
  Future<void> resetAndWipe() async {
    final repo = _repo;
    final personalId = _personal?.fileId;
    final familyId = _family?.fileId;
    final email = _personal?.profile.email ?? '';
    final famCode = _personal?.profile.familyId ?? '';
    if (email.isNotEmpty) await LocalCache.clear(email, familyId: famCode);
    _setBusy(true);
    try {
      if (repo != null && personalId != null && personalId.isNotEmpty) {
        try {
          await repo.trashFile(personalId);
        } catch (_) {/* best-effort */}
      }
      if (repo != null && familyId != null && familyId.isNotEmpty) {
        try {
          await repo.trashFile(familyId);
        } catch (_) {/* not the owner, or already gone */}
      }
    } finally {
      _setBusy(false);
    }
    await signOut();
  }

  Future<void> _onSignedIn() async {
    final account = _auth.account!;
    if (_firestoreEnabled) {
      _repo = FirestoreRepository(uid: account.uid);
      _attachments = AttachmentStore(account.uid);
    } else {
      final client = await _auth.authenticatedClient();
      if (client == null) {
        throw StateError('Could not obtain an authenticated Google client.');
      }
      _repo = FinanceRepository(DriveService(client));
    }

    final prefs = await SharedPreferences.getInstance();
    _familySetupDismissed =
        prefs.getBool('family_setup_dismissed_${account.email}') ?? false;

    // FAST PATH: paint the last-known data from the on-device cache right away
    // so the app opens instantly instead of blocking on the network. The
    // authoritative copy is fetched just below and swapped in when it lands.
    final cached =
        await LocalCache.loadPersonal(account.email, photoUrl: account.photoUrl);
    if (cached != null) {
      _personal = cached;
      final famId = cached.profile.familyId;
      if (famId.isNotEmpty) _family = await LocalCache.loadFamily(famId);
      _refreshing = true;
      status = AppStatus.signedIn;
      notifyListeners();
    }

    // Fetch the authoritative copy. If the user edited the cached data while
    // this was loading, keep their edits (they're already saved) rather than
    // letting the slower fetch overwrite them.
    final startMutations = _mutationCounter;
    final seed = UserProfile(
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
    try {
      final fresh = await _repo!.loadPersonal(seed);
      if (_mutationCounter == startMutations) {
        _personal = fresh;
        if (inFamily) {
          await _loadFamily();
        } else if (hasPendingJoin) {
          // Approved while we were away? Finalize the join now; otherwise stay
          // pending. Best-effort — never blocks sign-in.
          try {
            await refreshPendingJoin();
          } catch (_) {/* transient */}
        }
      }
    } catch (e) {
      // Offline / backend unreachable: keep showing the cache if we have one,
      // otherwise this is a genuine failure.
      if (_personal == null) rethrow;
    } finally {
      _refreshing = false;
    }

    status = AppStatus.signedIn;
    notifyListeners();

    // Refresh the on-device cache with whatever we now hold.
    await _cacheAll();

    // The head surfaces any pending join requests (no-op for everyone else).
    await loadJoinRequests();

    // Schedule device notifications for upcoming reminders.
    _syncNotifications();

    // The daily-report email backend reads Google Drive, so it only applies to
    // the legacy Drive path. Fire-and-forget; no-op unless a backend is set.
    if (!_firestoreEnabled) {
      BackendService.linkForDailyReport(
        account.serverAuthCode,
        familyId: _personal?.profile.familyId ?? '',
        role: _householdRole(),
      );
    }
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
        relationship: 'Self',
        phone: p.phone,
      ),
    );
    // Adopt the shared family name (the workbook is the source of truth) so the
    // label is consistent for every member, including in "My Details".
    if (_family!.familyName.isNotEmpty) {
      p.familyName = _family!.familyName;
    }
  }

  // --- profile / details -----------------------------------------------------
  /// The avatar URL to display (custom uploaded photo, else the Google one).
  String? get avatarUrl => _personal?.profile.avatarUrl;

  /// Set a new custom avatar; returns true on success. Persisted so it wins
  /// over the Google account photo everywhere. The photo is downscaled and
  /// stored inline on the profile as a base64 data URI — it's small enough to
  /// sit in the single Firestore profile document and render instantly.
  Future<bool> updateProfilePhoto(Uint8List bytes) async {
    if (!canAttachFiles || _personal == null) return false;
    try {
      final jpeg = encodeBoundedJpeg(bytes, maxWidth: 384, quality: 75);
      _personal!.profile.customPhotoUrl = jpegDataUri(jpeg);
      await _persistPersonal();
      _celebrate('Photo updated');
      return true;
    } catch (_) {
      AppFeedback.error('Could not update the photo');
      return false;
    }
  }

  /// Remove the custom avatar (falls back to the Google photo / initial). The
  /// photo lives inline on the profile, so clearing the field is enough.
  Future<void> removeProfilePhoto() async {
    if (_personal == null) return;
    _personal!.profile.customPhotoUrl = '';
    await _persistPersonal();
  }

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

  // --- category master -------------------------------------------------------
  /// Add a category. Ignored (no duplicate) if the name already exists.
  Future<void> addCategory(String name, String iconKey) async {
    final n = name.trim();
    if (_personal == null || n.isEmpty) return;
    if (categories.any((c) => c.name.toLowerCase() == n.toLowerCase())) {
      AppFeedback.error('“$n” already exists');
      return;
    }
    _personal!.categories.add(Category(name: n, iconKey: iconKey));
    await _persistPersonal();
    _celebrate('Category added');
  }

  /// Rename / re-icon an existing category (matched by [originalName]).
  Future<void> updateCategory(
      String originalName, String name, String iconKey) async {
    if (_personal == null) return;
    final idx = _personal!.categories.indexWhere((c) => c.name == originalName);
    if (idx < 0) return;
    _personal!.categories[idx]
      ..name = name.trim().isEmpty ? originalName : name.trim()
      ..iconKey = iconKey;
    await _persistPersonal();
    _celebrate('Category updated');
  }

  Future<void> deleteCategory(String name) async {
    if (_personal == null) return;
    _personal!.categories.removeWhere((c) => c.name == name);
    await _persistPersonal();
  }

  /// Add [name] to the category master if it isn't there yet, with [iconKey].
  /// Silent + non-persisting — the caller decides when to save. Used when a
  /// reminder books an expense so its category stays consistent in the master.
  void _ensureCategory(String name, String iconKey) {
    if (_personal == null || name.trim().isEmpty) return;
    final exists =
        _personal!.categories.any((c) => c.name.toLowerCase() == name.toLowerCase());
    if (!exists) _personal!.categories.add(Category(name: name, iconKey: iconKey));
  }

  // --- budgets (per-category monthly limits) ---------------------------------
  List<Budget> get budgets => _personal?.budgets ?? const [];

  /// The monthly limit set for [category], or 0 if none.
  double budgetFor(String category) {
    for (final b in budgets) {
      if (b.category == category) return b.monthlyLimit;
    }
    return 0;
  }

  /// Set (or, when [limit] <= 0, clear) the monthly budget for [category].
  Future<void> setBudget(String category, double limit) async {
    if (_personal == null || category.trim().isEmpty) return;
    final list = _personal!.budgets;
    final idx = list.indexWhere((b) => b.category == category);
    if (limit <= 0) {
      if (idx >= 0) list.removeAt(idx);
    } else if (idx >= 0) {
      list[idx].monthlyLimit = limit;
    } else {
      list.add(Budget(category: category, monthlyLimit: limit));
    }
    await _persistPersonal();
    _celebrate(limit <= 0 ? 'Budget cleared' : 'Budget saved');
  }

  /// Budget-vs-spend for every budgeted category in the selected month,
  /// most-over-budget first.
  List<BudgetStatus> budgetStatuses() {
    final spend = categoryBreakdown(selectedYear, selectedMonth);
    return budgets
        .map((b) => BudgetStatus(
            category: b.category,
            limit: b.monthlyLimit,
            spent: spend[b.category] ?? 0))
        .toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
  }

  /// Budgeted categories whose spend in the selected month is over the limit.
  List<BudgetStatus> get overBudget =>
      budgetStatuses().where((s) => s.isOver).toList();

  // --- payment reminders -----------------------------------------------------
  Future<void> addReminder(Reminder r) async {
    if (_personal == null) return;
    _personal!.reminders.add(r);
    _logActivity('Added', 'Reminder', r.title, r.amount);
    await _persistPersonal();
    _celebrate('Reminder added');
  }

  Future<void> updateReminder(Reminder r) async {
    if (_personal == null) return;
    final idx = _personal!.reminders.indexWhere((e) => e.id == r.id);
    if (idx < 0) return;
    _personal!.reminders[idx] = r;
    _logActivity('Updated', 'Reminder', r.title, r.amount);
    await _persistPersonal();
    _celebrate('Reminder updated');
  }

  Future<void> deleteReminder(String id) async {
    if (_personal == null) return;
    final idx = _personal!.reminders.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final r = _personal!.reminders[idx];
      _personal!.reminders.removeAt(idx);
      _logActivity('Deleted', 'Reminder', r.title, r.amount);
    }
    await _persistPersonal();
  }

  /// Pause / resume a reminder (paused ones stop raising alerts).
  Future<void> setReminderActive(String id, bool active) async {
    if (_personal == null) return;
    final idx = _personal!.reminders.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _personal!.reminders[idx].active = active;
    await _persistPersonal();
    _celebrate(active ? 'Reminder resumed' : 'Reminder paused');
  }

  /// Mark a reminder paid. Rolls a recurring reminder forward to its next due
  /// date (and closes a one-time one), and — when [addExpense] is true and the
  /// amount is known — books a matching expense in the reminder's category,
  /// mirroring it to the family ledger just like a normal expense.
  Future<void> markReminderPaid(String id, {bool addExpense = true}) async {
    if (_personal == null) return;
    final idx = _personal!.reminders.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final r = _personal!.reminders[idx];
    final now = DateTime.now();

    var familyChanged = false;
    if (addExpense && r.amount > 0) {
      _ensureCategory(r.expenseCategory, r.iconKey);
      final expense = Expense(
        id: 'rem_${r.id}_${now.microsecondsSinceEpoch}',
        date: now,
        category: r.expenseCategory,
        amount: r.amount,
        paymentMode: 'UPI',
        notes: r.title,
      );
      _personal!.expenses.add(expense);
      familyChanged = _mirrorToFamily(
        id: expense.id,
        date: expense.date,
        type: 'expense',
        category: expense.category,
        amount: expense.amount,
        notes: expense.notes,
      );
    }

    r.lastPaidDate = now;
    if (r.recurrence == Recurrence.none) {
      r.active = false; // one-time reminder is done
    } else {
      r.dueDate = r.nextOccurrenceAfter(now);
    }
    _logActivity('Paid', 'Reminder', r.title, r.amount);

    if (familyChanged) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate(addExpense && r.amount > 0
        ? 'Marked paid · expense added'
        : 'Marked paid');
  }

  // --- salary ----------------------------------------------------------------
  Future<void> addSalary(Salary s) async {
    _personal!.salaries.add(s);
    _logActivity('Added', 'Income', s.source, s.amount);
    final shared = _mirrorToFamily(
        id: s.id, date: s.date, type: 'income', category: s.source, amount: s.amount, notes: s.notes);
    if (shared) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate('Income added');
  }

  /// Correct a wrongly-entered income entry (kept under the same id, so its
  /// shared-ledger mirror is replaced in place).
  Future<void> updateSalary(Salary s) async {
    final list = _personal!.salaries;
    final idx = list.indexWhere((e) => e.id == s.id);
    if (idx < 0) return;
    list[idx] = s;
    _logActivity('Updated', 'Income', s.source, s.amount);
    var familyChanged = false;
    if (_family != null && inFamily) {
      _family!.ledger.removeWhere((l) => l.id == s.id);
      familyChanged = _mirrorToFamily(
          id: s.id,
          date: s.date,
          type: 'income',
          category: s.source,
          amount: s.amount,
          notes: s.notes);
    }
    if (familyChanged) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate('Income updated');
  }

  Future<void> deleteSalary(String id) async {
    final list = _personal!.salaries;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final s = list[idx];
      list.removeAt(idx);
      _logActivity('Deleted', 'Income', s.source, s.amount);
    }
    if (_unmirrorFromFamily(id)) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate('Income deleted');
  }

  // --- expenses --------------------------------------------------------------
  /// Store a receipt image for [expenseId] and return a marker to save on the
  /// expense, or null if attachments aren't available or the save failed. The
  /// image is downscaled and kept as base64 in Firestore (no Cloud Storage).
  Future<String?> uploadReceipt(String expenseId, Uint8List bytes) async {
    final store = _attachments;
    if (store == null) return null;
    try {
      final jpeg = encodeBoundedJpeg(bytes);
      final b64 = base64Encode(jpeg);
      if (b64.length > _maxReceiptBase64) {
        AppFeedback.error('That image is too large — try a smaller photo');
        return null;
      }
      await store.putReceipt(expenseId, b64);
      return _receiptMarker;
    } catch (_) {
      AppFeedback.error('Could not save the receipt');
      return null;
    }
  }

  /// Fetch a stored receipt's image bytes for [expenseId], or null if there's
  /// no receipt (or it can't be loaded). Used by the full-screen viewer.
  Future<Uint8List?> loadReceipt(String expenseId) async {
    final store = _attachments;
    if (store == null) return null;
    try {
      final b64 = await store.getReceipt(expenseId);
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

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
    if (familyChanged) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate('Expense added');
  }

  /// Correct a wrongly-entered expense (same id). Keeps its shared-ledger mirror
  /// and any linked family-wallet spend in sync with the new values.
  Future<void> updateExpense(Expense e) async {
    final list = _personal!.expenses;
    final idx = list.indexWhere((x) => x.id == e.id);
    if (idx < 0) return;
    list[idx] = e;
    _logActivity('Updated', 'Expense',
        '${e.category}${e.notes.isEmpty ? '' : ' — ${e.notes}'}', e.amount);

    var familyChanged = false;
    if (_family != null && inFamily) {
      _family!.ledger.removeWhere((l) => l.id == e.id);
      familyChanged = _mirrorToFamily(
          id: e.id,
          date: e.date,
          type: 'expense',
          category: e.category,
          amount: e.amount,
          notes: e.notes);
    }
    // Keep the linked family-wallet spend consistent with the edited expense.
    if (_family != null) {
      final wId = 'w_${e.id}';
      final wIdx = _family!.wallet.indexWhere((w) => w.id == wId);
      if (e.fromFamilyWallet) {
        final entry = WalletEntry(
          id: wId,
          date: e.date,
          memberEmail: _personal!.profile.email,
          memberName: _personal!.profile.displayName,
          direction: WalletDirection.spend,
          amount: e.amount,
          purpose: '${e.category}: ${e.notes}',
        );
        if (wIdx >= 0) {
          _family!.wallet[wIdx] = entry;
        } else {
          _family!.wallet.add(entry);
        }
        familyChanged = true;
      } else if (wIdx >= 0) {
        _family!.wallet.removeAt(wIdx);
        _family!.tombstones.add(wId);
        familyChanged = true;
      }
    }
    if (familyChanged) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate('Expense updated');
  }

  Future<void> deleteExpense(String id) async {
    final list = _personal!.expenses;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final e = list[idx];
      list.removeAt(idx);
      _logActivity('Deleted', 'Expense', e.category, e.amount);
      // Clean up the receipt photo too (fire-and-forget).
      if (e.hasReceipt && _attachments != null) {
        _attachments!.deleteReceipt(e.id);
      }
      // Remove any linked family-wallet spend as well.
      if (e.fromFamilyWallet && _family != null) {
        final wId = 'w_$id';
        final before = _family!.wallet.length;
        _family!.wallet.removeWhere((w) => w.id == wId);
        if (_family!.wallet.length != before) {
          _family!.tombstones.add(wId);
        }
      }
    }
    var familyChanged = _unmirrorFromFamily(id);
    // If we removed a wallet spend above, persist the family too.
    if (_family != null && _family!.tombstones.contains('w_$id')) {
      familyChanged = true;
    }
    if (familyChanged) await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate('Expense deleted');
  }

  // --- EMIs ------------------------------------------------------------------
  Future<void> addEmi(Emi emi) async {
    _personal!.emis.add(emi);
    _logActivity('Added', 'EMI', emi.name, emi.monthlyAmount);
    await _persistPersonal();
    _celebrate('EMI added');
  }

  /// Correct a wrongly-entered EMI (matched by id).
  Future<void> updateEmi(Emi emi) async {
    final list = _personal!.emis;
    final idx = list.indexWhere((e) => e.id == emi.id);
    if (idx < 0) return;
    list[idx] = emi;
    _logActivity('Updated', 'EMI', emi.name, emi.monthlyAmount);
    await _persistPersonal();
    _celebrate('EMI updated');
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
    _celebrate('Payment recorded');
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
    _celebrate('Target saved');
  }

  Target? targetFor(int year, int month) {
    for (final t in targets) {
      if (t.year == year && t.month == month) return t;
    }
    return null;
  }

  /// Remove a savings goal for a given month (e.g. set by mistake).
  Future<void> deleteTarget(int year, int month) async {
    if (_personal == null) return;
    final before = _personal!.targets.length;
    _personal!.targets.removeWhere((e) => e.year == year && e.month == month);
    if (_personal!.targets.length == before) return;
    _logActivity('Deleted', 'Target', 'Goal for $month/$year');
    await _persistPersonal();
    _celebrate('Goal removed');
  }

  // --- family / multi-user ---------------------------------------------------

  /// A family the user has requested to join but the head hasn't approved yet.
  String get pendingFamilyId => _personal?.profile.pendingFamilyId ?? '';
  String get pendingFamilyName => _personal?.profile.pendingFamilyName ?? '';

  /// True while the user is waiting for a head to approve their join request.
  bool get hasPendingJoin => pendingFamilyId.isNotEmpty && !inFamily;

  /// Create a brand-new family with the signed-in user as the **head** (Owner).
  /// A random, hard-to-guess family code is generated and used as the shared
  /// Family ID; share it with relatives so they can request to join.
  Future<void> createFamily(String familyName) async {
    final p = _personal!.profile;
    p.familyId = generateFamilyCode();
    p.familyName = familyName.trim();
    p.pendingFamilyId = '';
    p.pendingFamilyName = '';
    // Load first so the shared family doc (with us stamped as owner) exists.
    await _loadFamily();
    await _persistPersonal();
    // One-time backfill: push our existing income/expenses into the shared
    // ledger so they show up in the family report immediately.
    if (_backfillFamilyLedger()) await _persistFamilyEntries();
    _familySetupDismissed = true; // setup is complete
    notifyListeners();
  }

  /// Ask to join an existing family by its shared code (from an invite).
  ///
  /// On the cloud backend this only FILES A REQUEST — the head must approve it
  /// before the user gets any access. On the legacy Drive backend, where access
  /// is controlled by file sharing, it joins immediately.
  Future<JoinResult> joinFamily(String familyCode) async {
    final code = familyCode.trim();
    if (code.isEmpty) return JoinResult.invalidCode;
    if (!_firestoreEnabled) return _legacyJoin(code);

    _setBusy(true);
    try {
      final meta = await _repo!.fetchFamilyMeta(code);
      if (meta == null) return JoinResult.notFound;

      final p = _personal!.profile;
      // Already approved (e.g. re-joining on a new device) → go straight in.
      if (meta.hasMember(p.email)) {
        await _finalizeJoin(meta);
        return JoinResult.joined;
      }
      // File a pending request and remember it so we can poll for approval.
      await _repo!.requestToJoin(code,
          email: p.email, name: p.displayName, phone: p.phone);
      p.pendingFamilyId = code;
      p.pendingFamilyName = meta.familyName;
      await _persistPersonal();
      notifyListeners();
      return JoinResult.requested;
    } catch (e) {
      error = _friendlyError(e);
      return JoinResult.error;
    } finally {
      _setBusy(false);
    }
  }

  /// Legacy Drive join: access is by file sharing, so join right away.
  Future<JoinResult> _legacyJoin(String code) async {
    final p = _personal!.profile;
    p.familyId = code;
    p.familyName = '';
    await _loadFamily();
    await _persistPersonal();
    if (_backfillFamilyLedger()) await _persistFamilyEntries();
    await _ensureSelfMember();
    _familySetupDismissed = true;
    notifyListeners();
    return JoinResult.joined;
  }

  /// Re-check a pending join. [JoinResult.joined] once the head approves,
  /// [JoinResult.declined] if the request is gone, else [JoinResult.requested].
  Future<JoinResult> refreshPendingJoin() async {
    if (!hasPendingJoin || !_firestoreEnabled) return JoinResult.requested;
    _setBusy(true);
    try {
      final code = pendingFamilyId;
      final p = _personal!.profile;
      final meta = await _repo!.fetchFamilyMeta(code);
      if (meta == null) {
        await _clearPending();
        return JoinResult.declined; // family deleted
      }
      if (meta.hasMember(p.email)) {
        await _finalizeJoin(meta);
        return JoinResult.joined;
      }
      final stillPending = await _repo!.joinRequestPending(code, p.email);
      if (!stillPending) {
        await _clearPending();
        return JoinResult.declined;
      }
      return JoinResult.requested;
    } catch (_) {
      return JoinResult.requested; // transient — keep waiting
    } finally {
      _setBusy(false);
    }
  }

  /// Cancel a pending join request.
  Future<void> cancelPendingJoin() async {
    if (!hasPendingJoin) return;
    final code = pendingFamilyId;
    final email = _personal!.profile.email;
    if (_firestoreEnabled) {
      try {
        await _repo!.declineJoinRequest(code, email);
      } catch (_) {/* best-effort */}
    }
    await _clearPending();
  }

  Future<void> _clearPending() async {
    final p = _personal!.profile;
    p.pendingFamilyId = '';
    p.pendingFamilyName = '';
    await _persistPersonal();
    notifyListeners();
  }

  /// Complete a join once approved: adopt the family and load its data.
  Future<void> _finalizeJoin(FamilyMeta meta) async {
    final p = _personal!.profile;
    p.familyId = meta.familyId;
    p.familyName = meta.familyName;
    p.pendingFamilyId = '';
    p.pendingFamilyName = '';
    await _loadFamily();
    await _persistPersonal();
    if (_backfillFamilyLedger()) await _persistFamilyEntries();
    _familySetupDismissed = true;
    notifyListeners();
  }

  /// Ensure the signed-in user appears in the family roster (legacy Drive join).
  Future<void> _ensureSelfMember() async {
    if (_family == null || _personal == null) return;
    final p = _personal!.profile;
    if (_family!.members.any((m) => m.email == p.email)) return;
    _family!.members.add(Member(
      email: p.email,
      name: p.displayName,
      role: 'Adult',
      relationship: 'Other',
      phone: p.phone,
    ));
    await _persistFamilyRoster();
  }

  // --- join requests (head only) --------------------------------------------
  List<JoinRequest> _joinRequests = const [];
  List<JoinRequest> get joinRequests => _joinRequests;
  int get pendingRequestCount => _joinRequests.length;

  /// Load pending join requests for the head to review. No-op unless the user
  /// is the family head on the cloud backend.
  Future<void> loadJoinRequests() async {
    if (!_firestoreEnabled || !isFamilyHead || !inFamily) {
      _joinRequests = const [];
      notifyListeners();
      return;
    }
    try {
      _joinRequests = await _repo!.loadJoinRequests(familyCode);
    } catch (_) {
      _joinRequests = const [];
    }
    notifyListeners();
  }

  /// Approve a requester into the roster with [role], then clear their request.
  /// Head-only (the security rules also enforce this).
  Future<void> approveJoinRequest(JoinRequest req,
      {String role = 'Adult', String relationship = 'Other'}) async {
    if (!isFamilyHead || _family == null) return;
    final member = Member(
      email: req.email,
      name: req.name.trim().isEmpty ? req.email.split('@').first : req.name.trim(),
      role: role,
      relationship: relationship,
      phone: req.phone,
    );
    final idx = _family!.members.indexWhere((m) => m.email == req.email);
    if (idx >= 0) {
      _family!.members[idx] = member;
    } else {
      _family!.members.add(member);
    }
    await _persistFamilyRoster();
    try {
      await _repo!.declineJoinRequest(familyCode, req.email); // clear request
    } catch (_) {/* best-effort */}
    _joinRequests = _joinRequests.where((r) => r.email != req.email).toList();
    _celebrate('${member.name} approved');
  }

  /// Decline a pending request without granting access. Head-only.
  Future<void> declineJoinRequestFor(JoinRequest req) async {
    if (!isFamilyHead) return;
    try {
      await _repo!.declineJoinRequest(familyCode, req.email);
    } catch (_) {/* best-effort */}
    _joinRequests = _joinRequests.where((r) => r.email != req.email).toList();
    notifyListeners();
  }

  /// Skip family setup and use the app solo (personal finance only). Remembered
  /// per-account so the onboarding screen doesn't reappear on every launch.
  Future<void> dismissFamilySetup() async {
    _familySetupDismissed = true;
    notifyListeners();
    final email = _personal?.profile.email;
    if (email == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('family_setup_dismissed_$email', true);
  }

  /// Rename the family without changing the Family ID (so the shared workbook
  /// and members stay the same). The new name is written to the shared workbook
  /// so every member sees it, and mirrored into this user's profile.
  Future<void> renameFamily(String newName) async {
    final name = newName.trim();
    if (name.isEmpty || _personal == null) return;
    if (!isFamilyHead) {
      AppFeedback.error('Only the family head can rename the family');
      return;
    }
    _personal!.profile.familyName = name;
    _family?.familyName = name; // so the dashboard / wallet headers update now
    if (_family != null) await _persistFamilyRoster(overwriteName: true);
    await _persistPersonal();
    _celebrate('Family name updated');
  }

  /// Add any personal income/expenses missing from the shared family ledger.
  /// Idempotent (keyed by entry id). Returns true if anything was added.
  bool _backfillFamilyLedger() {
    if (_family == null || _personal == null) return false;
    final existing = _family!.ledger.map((e) => e.id).toSet();
    var changed = false;
    for (final e in _personal!.expenses) {
      if (existing.contains(e.id)) continue;
      _family!.ledger.add(FamilyLedgerEntry(
        id: e.id,
        date: e.date,
        memberEmail: _personal!.profile.email,
        memberName: _personal!.profile.displayName,
        type: 'expense',
        category: e.category,
        amount: e.amount,
        notes: e.notes,
      ));
      changed = true;
    }
    for (final s in _personal!.salaries) {
      if (existing.contains(s.id)) continue;
      _family!.ledger.add(FamilyLedgerEntry(
        id: s.id,
        date: s.date,
        memberEmail: _personal!.profile.email,
        memberName: _personal!.profile.displayName,
        type: 'income',
        category: s.source,
        amount: s.amount,
        notes: s.notes,
      ));
      changed = true;
    }
    return changed;
  }

  /// Trigger an immediate report email to the signed-in user (and, for a
  /// parent, the family report). Returns true on success. No-op without a
  /// configured backend.
  Future<bool> sendReportEmailNow() async {
    if (!BackendService.isConfigured) return false;
    final token = await _auth.idToken();
    return BackendService.sendReportNow(token);
  }

  Future<void> addOrUpdateMember(Member m) async {
    if (!isFamilyHead) {
      AppFeedback.error('Only the family head can manage members');
      return;
    }
    final idx = _family!.members.indexWhere((e) => e.email == m.email);
    final isNew = idx < 0;
    if (idx >= 0) {
      _family!.members[idx] = m;
    } else {
      _family!.members.add(m);
    }
    await _persistFamilyRoster();
    _celebrate(isNew ? 'Member added' : 'Member updated');
  }

  Future<void> removeMember(String email) async {
    if (!isFamilyHead) {
      AppFeedback.error('Only the family head can manage members');
      return;
    }
    // The head can't remove themselves — that would orphan the family.
    if (email == _personal?.profile.email) {
      AppFeedback.error("You're the family head — you can't remove yourself");
      return;
    }
    _family!.members.removeWhere((e) => e.email == email);
    _family!.tombstones.add(email); // so the removal syncs to other members
    await _persistFamilyRoster();
  }

  // --- common wallet ---------------------------------------------------------
  Future<void> addWalletEntry(WalletEntry e) async {
    _family!.wallet.add(e);
    final kind = e.direction == WalletDirection.topUp ? 'Top-up' : 'Spend';
    _logActivity('Added', 'Wallet',
        '$kind${e.purpose.isEmpty ? '' : ' — ${e.purpose}'}', e.amount);
    await _persistFamilyEntries();
    await _persistPersonal();
    _celebrate(e.direction == WalletDirection.topUp
        ? 'Wallet topped up'
        : 'Wallet spend recorded');
  }

  Future<void> deleteWalletEntry(String id) async {
    final list = _family!.wallet;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final e = list[idx];
      list.removeAt(idx);
      _family!.tombstones.add(e.id); // so the deletion syncs to other members
      final kind = e.direction == WalletDirection.topUp ? 'Top-up' : 'Spend';
      _logActivity('Deleted', 'Wallet', kind, e.amount);
    }
    await _persistFamilyEntries();
    await _persistPersonal();
  }

  /// A link to open the personal workbook (.xlsx) in Google Drive / Sheets.
  Future<String?> personalFileLink() async {
    final id = _personal?.fileId;
    if (id == null || id.isEmpty || _repo == null) return null;
    return _repo!.fileWebLink(id);
  }

  /// Income/expense for an arbitrary date range (inclusive) — used by the
  /// PDF statement export.
  List<Expense> expensesBetween(DateTime start, DateTime end) => expenses
      .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  List<Salary> salariesBetween(DateTime start, DateTime end) => salaries
      .where((s) => !s.date.isBefore(start) && !s.date.isAfter(end))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

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

  // --- family (shared) analytics --------------------------------------------
  /// Family ledger entries (everyone's) for a given month, newest first.
  List<FamilyLedgerEntry> familyEntriesForMonth(int year, int month) =>
      familyLedger.where((e) => e.year == year && e.month == month).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  double familyExpenseForMonth(int year, int month) => familyLedger
      .where((e) => e.type == 'expense' && e.year == year && e.month == month)
      .fold(0.0, (a, e) => a + e.amount);

  double familyIncomeForMonth(int year, int month) => familyLedger
      .where((e) => e.type == 'income' && e.year == year && e.month == month)
      .fold(0.0, (a, e) => a + e.amount);

  /// Map of member name -> total spend for the given month (expenses only).
  Map<String, double> familySpendByMember(int year, int month) {
    final map = <String, double>{};
    for (final e in familyLedger.where(
        (e) => e.type == 'expense' && e.year == year && e.month == month)) {
      final who = e.memberName.isEmpty ? e.memberEmail : e.memberName;
      map[who] = (map[who] ?? 0) + e.amount;
    }
    return map;
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
    _family!.tombstones.add(id); // keep the deletion from re-syncing back
    return _family!.ledger.length != before;
  }

  /// Show a success popup after a mutation, or a soft error if the Drive save
  /// failed (the change is still kept locally).
  void _celebrate(String successMessage) {
    if (error == null) {
      AppFeedback.success(successMessage);
    } else {
      AppFeedback.error('Saved on device — Drive sync failed');
    }
  }

  // --- internals -------------------------------------------------------------
  /// Refresh the on-device cache with everything currently in memory.
  Future<void> _cacheAll() async {
    final p = _personal;
    if (p != null) await LocalCache.savePersonal(p);
    final f = _family;
    if (f != null) await LocalCache.saveFamily(f);
  }

  Future<void> _persistPersonal() async {
    _mutationCounter++;
    error = null;
    notifyListeners(); // optimistic UI update
    // Write the cache first so the change is instantly available on reopen and
    // survives even if the remote save below fails (e.g. offline).
    if (_personal != null) await LocalCache.savePersonal(_personal!);
    _setBusy(true);
    try {
      await _repo!.savePersonal(_personal!);
    } catch (e) {
      error = 'Could not save to Drive: $e';
    } finally {
      _setBusy(false);
    }
    _syncNotifications();
  }

  /// Re-schedule device notifications to match the current reminders and the
  /// user's notification preferences. Fire-and-forget; safe to call often.
  void _syncNotifications() {
    NotificationService.sync(
      reminders,
      currency: currency,
      enabled: notificationsEnabled,
      hour: reminderHour,
    );
  }

  /// Persist shared FINANCES (wallet + ledger). Any member may do this.
  Future<void> _persistFamilyEntries() async {
    _mutationCounter++;
    error = null;
    notifyListeners();
    if (_family != null) await LocalCache.saveFamily(_family!);
    _setBusy(true);
    try {
      await _repo!.saveFamily(_family!);
    } catch (e) {
      error = 'Could not save family workbook: $e';
    } finally {
      _setBusy(false);
    }
  }

  /// Persist the ROSTER (name + members + roles). Head-only server-side; the
  /// callers already gate on [isFamilyHead], so a failure here means the rules
  /// rejected a non-head — surfaced as a soft error.
  Future<void> _persistFamilyRoster({bool overwriteName = false}) async {
    _mutationCounter++;
    error = null;
    notifyListeners();
    if (_family != null) await LocalCache.saveFamily(_family!);
    _setBusy(true);
    try {
      await _repo!.saveFamilyRoster(_family!, overwriteName: overwriteName);
    } catch (e) {
      error = 'Could not save family members: $e';
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
  /// The raw error is appended so a screenshot of this card is enough to tell
  /// the config failures apart (unregistered SHA-1 vs consent screen vs
  /// disabled provider all look identical otherwise).
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('operation-not-allowed')) {
      return 'Google Sign-In is disabled for this Firebase project.\n\n'
          'Enable it: Firebase console → Authentication → Sign-in method → '
          'Google → Enable.\n\nDetails: $s';
    }
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
            'JavaScript origin, and its client ID must be embedded in the '
            'page.\n\nDetails: $s';
      }
      return 'Google Sign-In could not complete.\n\n'
          "Usually this build's signing SHA-1 is not registered: Firebase "
          'console → Project settings → Your apps → Android app '
          'com.nandhakumar.familyfinance → Add fingerprint. If sign-in works '
          'for you but not others, publish the OAuth consent screen to '
          'production (no verification needed for basic profile scopes).'
          '\n\nDetails: $s';
    }
    return s;
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
