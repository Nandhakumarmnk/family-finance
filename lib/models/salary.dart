/// A single income / salary credit. Stored row-wise in the `Salary` sheet
/// so that month-wise and year-wise reports can be aggregated cheaply.
class Salary {
  final String id;
  final DateTime date;
  final String source; // e.g. "Primary job", "Freelance", "Rent income"
  final double amount;
  final String notes;

  Salary({
    required this.id,
    required this.date,
    required this.source,
    required this.amount,
    this.notes = '',
  });

  int get month => date.month;
  int get year => date.year;

  List<dynamic> toRow() => [
        id,
        date.toIso8601String(),
        year,
        month,
        source,
        amount,
        notes,
      ];

  static const List<String> header = [
    'id',
    'date',
    'year',
    'month',
    'source',
    'amount',
    'notes',
  ];

  factory Salary.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Salary(
      id: at(0),
      date: DateTime.tryParse(at(1)) ?? DateTime(1970),
      source: at(4),
      amount: double.tryParse(at(5)) ?? 0,
      notes: at(6),
    );
  }
}
