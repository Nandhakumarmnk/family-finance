/// A single spend. Stored in the `Expenses` sheet. Year/month columns are
/// denormalised onto each row to make month-wise / year-wise grouping trivial.
class Expense {
  final String id;
  final DateTime date;
  final String category; // Food, Rent, Travel, Utilities, EMI, Other...
  final double amount;
  final String paymentMode; // Cash, UPI, Card, Bank
  final String notes;

  /// When true this expense was paid from the shared family wallet rather
  /// than the individual's own money.
  final bool fromFamilyWallet;

  /// Download URL of a receipt/bill photo in Cloud Storage; '' if none.
  final String receiptUrl;

  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.paymentMode = 'UPI',
    this.notes = '',
    this.fromFamilyWallet = false,
    this.receiptUrl = '',
  });

  bool get hasReceipt => receiptUrl.isNotEmpty;

  int get month => date.month;
  int get year => date.year;

  List<dynamic> toRow() => [
        id,
        date.toIso8601String(),
        year,
        month,
        category,
        amount,
        paymentMode,
        fromFamilyWallet ? 'yes' : 'no',
        notes,
        receiptUrl,
      ];

  // `receiptUrl` is appended last so older 9-column rows still load.
  static const List<String> header = [
    'id',
    'date',
    'year',
    'month',
    'category',
    'amount',
    'paymentMode',
    'fromFamilyWallet',
    'notes',
    'receiptUrl',
  ];

  factory Expense.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Expense(
      id: at(0),
      date: DateTime.tryParse(at(1)) ?? DateTime(1970),
      category: at(4),
      amount: double.tryParse(at(5)) ?? 0,
      paymentMode: at(6).isEmpty ? 'UPI' : at(6),
      fromFamilyWallet: at(7).toLowerCase() == 'yes',
      notes: at(8),
      receiptUrl: at(9),
    );
  }

  static const List<String> categories = [
    'Food',
    'Groceries',
    'Rent',
    'Utilities',
    'Travel',
    'Health',
    'Education',
    'Shopping',
    'Entertainment',
    'EMI',
    'Insurance',
    'Other',
  ];
}
