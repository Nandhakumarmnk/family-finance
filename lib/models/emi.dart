import 'dart:math' as math;

/// A loan / EMI being repaid. The app tracks how many instalments are paid
/// and derives the remaining EMIs, remaining principal and payoff date.
class Emi {
  final String id;
  final String name; // "Home loan", "Car loan", "Phone EMI"
  final double monthlyAmount; // instalment per month
  final int totalMonths; // tenure
  int paidMonths; // instalments already paid
  final double annualInterestRate; // % per year, informational
  final DateTime startDate;
  final String notes;

  /// Optional: the actual outstanding/pending amount the user owes. When > 0
  /// this overrides the simple monthly × remaining estimate (useful when the
  /// payoff includes interest, or the user tracks the loan by balance rather
  /// than by an interest rate). 0 means "derive it from the instalments".
  final double outstandingAmount;

  Emi({
    required this.id,
    required this.name,
    required this.monthlyAmount,
    required this.totalMonths,
    this.paidMonths = 0,
    this.annualInterestRate = 0,
    this.outstandingAmount = 0,
    required this.startDate,
    this.notes = '',
  });

  /// Instalments still to be paid.
  int get remainingMonths => math.max(0, totalMonths - paidMonths);

  bool get isClosed => remainingMonths == 0;

  /// True when the remaining amount was entered directly rather than derived.
  bool get hasManualOutstanding => outstandingAmount > 0;

  double get totalPayable => monthlyAmount * totalMonths;
  double get amountPaid => monthlyAmount * paidMonths;

  /// What's still owed: the manually-entered outstanding amount if set,
  /// otherwise monthly × remaining instalments.
  double get amountRemaining =>
      hasManualOutstanding ? outstandingAmount : monthlyAmount * remainingMonths;

  double get progress => totalMonths == 0 ? 1 : paidMonths / totalMonths;

  /// Estimated date the loan finishes, based on start date + tenure.
  DateTime get payoffDate =>
      DateTime(startDate.year, startDate.month + totalMonths, startDate.day);

  /// Next due date based on instalments already paid.
  DateTime get nextDueDate =>
      DateTime(startDate.year, startDate.month + paidMonths, startDate.day);

  // `outstandingAmount` is appended last so older 8-column sheets still load.
  List<dynamic> toRow() => [
        id,
        name,
        monthlyAmount,
        totalMonths,
        paidMonths,
        annualInterestRate,
        startDate.toIso8601String(),
        notes,
        outstandingAmount,
      ];

  static const List<String> header = [
    'id',
    'name',
    'monthlyAmount',
    'totalMonths',
    'paidMonths',
    'annualInterestRate',
    'startDate',
    'notes',
    'outstandingAmount',
  ];

  factory Emi.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Emi(
      id: at(0),
      name: at(1),
      monthlyAmount: double.tryParse(at(2)) ?? 0,
      totalMonths: int.tryParse(at(3)) ?? 0,
      paidMonths: int.tryParse(at(4)) ?? 0,
      annualInterestRate: double.tryParse(at(5)) ?? 0,
      startDate: DateTime.tryParse(at(6)) ?? DateTime(1970),
      notes: at(7),
      outstandingAmount: double.tryParse(at(8)) ?? 0,
    );
  }
}
