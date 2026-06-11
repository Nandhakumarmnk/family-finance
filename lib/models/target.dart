/// A monthly savings / spending target. One row per (year, month).
/// Used by the reports screen to compare planned vs actual.
class Target {
  final String id;
  final int year;
  final int month;

  /// How much the user wants to save this month.
  final double savingsTarget;

  /// Soft spending cap for the month.
  final double spendingLimit;

  final String notes;

  Target({
    required this.id,
    required this.year,
    required this.month,
    this.savingsTarget = 0,
    this.spendingLimit = 0,
    this.notes = '',
  });

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  List<dynamic> toRow() => [
        id,
        year,
        month,
        savingsTarget,
        spendingLimit,
        notes,
      ];

  static const List<String> header = [
    'id',
    'year',
    'month',
    'savingsTarget',
    'spendingLimit',
    'notes',
  ];

  factory Target.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Target(
      id: at(0),
      year: int.tryParse(at(1)) ?? 0,
      month: int.tryParse(at(2)) ?? 0,
      savingsTarget: double.tryParse(at(3)) ?? 0,
      spendingLimit: double.tryParse(at(4)) ?? 0,
      notes: at(5),
    );
  }
}
