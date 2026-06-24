/// A recurring (or one-off) payment reminder — EMIs, loan/credit repayments,
/// groceries, bills, recharges and other "mandatory needs". Stored in the
/// `Reminders` sheet of the personal workbook.
///
/// Like [Category], the model stays free of Flutter types: the kind, recurrence
/// and icon are persisted as stable string keys (a spreadsheet cell can't hold
/// an enum or an `IconData`). The UI resolves the icon via `CategoryIcons`.
library;

/// How often a reminder repeats once it's marked paid.
enum Recurrence { none, weekly, monthly, quarterly, yearly }

/// The "standard" payment kinds the app understands. Each maps to a label, an
/// icon key and the expense category an auto-booked payment lands in.
enum ReminderKind { emi, repayment, grocery, bill, recharge, mandatory, other }

/// How urgent a reminder is right now (derived from its due date).
enum ReminderStatus { overdue, dueToday, dueSoon, upcoming, paused }

/// Reminders within this many days are flagged "due soon".
const int kDueSoonWindowDays = 7;

class Reminder {
  final String id;
  String title;
  String kindKey; // ReminderKind name
  double amount;
  DateTime dueDate;
  String recurrenceKey; // Recurrence name
  String notes;
  bool active;

  /// When the user last marked this paid (null until first payment).
  DateTime? lastPaidDate;

  Reminder({
    required this.id,
    required this.title,
    ReminderKind kind = ReminderKind.other,
    this.amount = 0,
    required this.dueDate,
    Recurrence recurrence = Recurrence.monthly,
    this.notes = '',
    this.active = true,
    this.lastPaidDate,
  })  : kindKey = kind.name,
        recurrenceKey = recurrence.name;

  // --- enum views ------------------------------------------------------------
  ReminderKind get kind => ReminderKind.values.firstWhere(
        (k) => k.name == kindKey,
        orElse: () => ReminderKind.other,
      );
  set kind(ReminderKind k) => kindKey = k.name;

  Recurrence get recurrence => Recurrence.values.firstWhere(
        (r) => r.name == recurrenceKey,
        orElse: () => Recurrence.monthly,
      );
  set recurrence(Recurrence r) => recurrenceKey = r.name;

  // --- presentation helpers (resolved from the kind) -------------------------
  String get label => kindMeta[kind]!.label;
  String get iconKey => kindMeta[kind]!.iconKey;

  /// The expense category an auto-booked payment for this reminder lands in.
  String get expenseCategory => kindMeta[kind]!.category;

  String get recurrenceLabel => switch (recurrence) {
        Recurrence.none => 'One-time',
        Recurrence.weekly => 'Weekly',
        Recurrence.monthly => 'Monthly',
        Recurrence.quarterly => 'Every 3 months',
        Recurrence.yearly => 'Yearly',
      };

  // --- schedule maths --------------------------------------------------------
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole days from today until the due date (negative when overdue).
  int get daysUntilDue =>
      _dateOnly(dueDate).difference(_dateOnly(DateTime.now())).inDays;

  ReminderStatus get status {
    if (!active) return ReminderStatus.paused;
    final d = daysUntilDue;
    if (d < 0) return ReminderStatus.overdue;
    if (d == 0) return ReminderStatus.dueToday;
    if (d <= kDueSoonWindowDays) return ReminderStatus.dueSoon;
    return ReminderStatus.upcoming;
  }

  /// True when this reminder needs attention now (overdue or within the window).
  bool get needsAttention =>
      active && daysUntilDue <= kDueSoonWindowDays;

  /// One step of the recurrence applied to [from].
  DateTime _advance(DateTime from) => switch (recurrence) {
        Recurrence.none => from,
        Recurrence.weekly => from.add(const Duration(days: 7)),
        Recurrence.monthly => DateTime(from.year, from.month + 1, from.day),
        Recurrence.quarterly => DateTime(from.year, from.month + 3, from.day),
        Recurrence.yearly => DateTime(from.year + 1, from.month, from.day),
      };

  /// The next due date strictly after [from], stepping by the recurrence. Used
  /// when marking paid so an overdue reminder rolls forward to a future date
  /// rather than landing in the past again.
  DateTime nextOccurrenceAfter(DateTime from) {
    if (recurrence == Recurrence.none) return dueDate;
    var next = dueDate;
    // Guard the loop so a misconfigured recurrence can never spin forever.
    var guard = 0;
    while (!next.isAfter(from) && guard < 600) {
      next = _advance(next);
      guard++;
    }
    return next;
  }

  // --- persistence (append new columns last for backward compatibility) ------
  List<dynamic> toRow() => [
        id,
        title,
        kindKey,
        amount,
        dueDate.toIso8601String(),
        recurrenceKey,
        active ? 'yes' : 'no',
        lastPaidDate?.toIso8601String() ?? '',
        notes,
      ];

  static const List<String> header = [
    'id',
    'title',
    'kind',
    'amount',
    'dueDate',
    'recurrence',
    'active',
    'lastPaidDate',
    'notes',
  ];

  factory Reminder.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    final last = at(7);
    return Reminder(
      id: at(0),
      title: at(1),
      kind: ReminderKind.values.firstWhere(
        (k) => k.name == at(2),
        orElse: () => ReminderKind.other,
      ),
      amount: double.tryParse(at(3)) ?? 0,
      dueDate: DateTime.tryParse(at(4)) ?? DateTime.now(),
      recurrence: Recurrence.values.firstWhere(
        (rc) => rc.name == at(5),
        orElse: () => Recurrence.monthly,
      ),
      active: at(6).isEmpty ? true : at(6).toLowerCase() == 'yes',
      lastPaidDate: last.isEmpty ? null : DateTime.tryParse(last),
      notes: at(8),
    );
  }
}

/// Static metadata for each reminder kind: its display label, the icon key
/// (resolved by `CategoryIcons`) and the expense category an auto-booked
/// payment is filed under. This is the "standard set" of payment kinds the app
/// ships with — EMIs, repayments, groceries, bills, recharges and mandatory
/// needs — plus a catch-all "Other".
class KindMeta {
  final String label;
  final String iconKey;
  final String category;
  const KindMeta(this.label, this.iconKey, this.category);
}

const Map<ReminderKind, KindMeta> kindMeta = {
  ReminderKind.emi: KindMeta('EMI / Loan', 'bank', 'EMI'),
  ReminderKind.repayment: KindMeta('Repayment', 'card', 'Repayment'),
  ReminderKind.grocery: KindMeta('Groceries', 'grocery', 'Groceries'),
  ReminderKind.bill: KindMeta('Bill', 'receipt', 'Bills'),
  ReminderKind.recharge: KindMeta('Recharge', 'phone', 'Recharge'),
  ReminderKind.mandatory: KindMeta('Mandatory need', 'shield', 'Mandatory'),
  ReminderKind.other: KindMeta('Other', 'category', 'Other'),
};
