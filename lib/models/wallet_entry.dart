/// An entry in the shared family "common wallet". Each family member can
/// contribute money in (top-up) or record money taken out (spend). The wallet
/// balance is the sum of ins minus outs. Stored in the shared family workbook.
class WalletEntry {
  final String id;
  final DateTime date;
  final String memberEmail; // who made the entry
  final String memberName;
  final WalletDirection direction;
  final double amount;
  final String purpose;

  WalletEntry({
    required this.id,
    required this.date,
    required this.memberEmail,
    required this.memberName,
    required this.direction,
    required this.amount,
    this.purpose = '',
  });

  /// Signed contribution to the balance: +amount for top-ups, -amount spends.
  double get signedAmount =>
      direction == WalletDirection.topUp ? amount : -amount;

  List<dynamic> toRow() => [
        id,
        date.toIso8601String(),
        memberEmail,
        memberName,
        direction.name,
        amount,
        purpose,
      ];

  static const List<String> header = [
    'id',
    'date',
    'memberEmail',
    'memberName',
    'direction',
    'amount',
    'purpose',
  ];

  factory WalletEntry.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return WalletEntry(
      id: at(0),
      date: DateTime.tryParse(at(1)) ?? DateTime(1970),
      memberEmail: at(2),
      memberName: at(3),
      direction: at(4) == 'spend' ? WalletDirection.spend : WalletDirection.topUp,
      amount: double.tryParse(at(5)) ?? 0,
      purpose: at(6),
    );
  }
}

enum WalletDirection { topUp, spend }
