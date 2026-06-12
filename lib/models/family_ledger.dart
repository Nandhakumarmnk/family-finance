/// A copy of a member's income/expense mirrored into the SHARED family
/// workbook, so the household (and the parent's daily report) can see everyone's
/// activity in one place. Personal workbooks stay private; this is the opt-in
/// shared view that exists only while a user is part of a family.
///
/// The `id` matches the originating personal Salary/Expense id, so edits and
/// deletes in the personal workbook can keep this shared copy in sync.
class FamilyLedgerEntry {
  final String id;
  final DateTime date;
  final String memberEmail;
  final String memberName;
  final String type; // 'income' | 'expense'
  final String category; // expense category, or income source
  final double amount;
  final String notes;

  FamilyLedgerEntry({
    required this.id,
    required this.date,
    required this.memberEmail,
    required this.memberName,
    required this.type,
    required this.category,
    required this.amount,
    this.notes = '',
  });

  int get year => date.year;
  int get month => date.month;

  List<dynamic> toRow() => [
        id,
        date.toIso8601String(),
        year,
        month,
        memberEmail,
        memberName,
        type,
        category,
        amount,
        notes,
      ];

  static const List<String> header = [
    'id',
    'date',
    'year',
    'month',
    'memberEmail',
    'memberName',
    'type',
    'category',
    'amount',
    'notes',
  ];

  factory FamilyLedgerEntry.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return FamilyLedgerEntry(
      id: at(0),
      date: DateTime.tryParse(at(1)) ?? DateTime(1970),
      memberEmail: at(4),
      memberName: at(5),
      type: at(6).isEmpty ? 'expense' : at(6),
      category: at(7),
      amount: double.tryParse(at(8)) ?? 0,
      notes: at(9),
    );
  }
}
