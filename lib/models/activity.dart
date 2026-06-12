/// An audit-log entry recording a single change to financial data (a payment
/// being added, edited or deleted). Stored row-wise in the `Activity` sheet of
/// the personal workbook so the in-app history and the daily report can both
/// read it. Newest entries are kept first.
class Activity {
  final String id;
  final DateTime timestamp;
  final String userEmail;
  final String action; // Added | Updated | Deleted
  final String type; // Salary | Expense | EMI | EMI payment | Wallet | Target
  final String description;
  final double amount;

  Activity({
    required this.id,
    required this.timestamp,
    required this.userEmail,
    required this.action,
    required this.type,
    required this.description,
    this.amount = 0,
  });

  int get year => timestamp.year;
  int get month => timestamp.month;
  int get day => timestamp.day;

  List<dynamic> toRow() => [
        id,
        timestamp.toIso8601String(),
        userEmail,
        action,
        type,
        amount,
        description,
      ];

  static const List<String> header = [
    'id',
    'timestamp',
    'userEmail',
    'action',
    'type',
    'amount',
    'description',
  ];

  factory Activity.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Activity(
      id: at(0),
      timestamp: DateTime.tryParse(at(1)) ?? DateTime(1970),
      userEmail: at(2),
      action: at(3),
      type: at(4),
      amount: double.tryParse(at(5)) ?? 0,
      description: at(6),
    );
  }
}
