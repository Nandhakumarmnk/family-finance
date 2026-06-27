/// A monthly spending limit for a single expense category. Stored row-wise in
/// the personal workbook's `Budgets` sheet (Drive) or the user's Firestore doc.
class Budget {
  final String category;
  double monthlyLimit;

  Budget({required this.category, required this.monthlyLimit});

  List<dynamic> toRow() => [category, monthlyLimit];

  static const List<String> header = ['category', 'monthlyLimit'];

  factory Budget.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Budget(
      category: at(0),
      monthlyLimit: double.tryParse(at(1)) ?? 0,
    );
  }
}

/// A category's budget vs its actual spend for a period — the shape the UI and
/// dashboard alert consume. Pure value object, computed in [AppState].
class BudgetStatus {
  final String category;
  final double limit;
  final double spent;

  BudgetStatus({
    required this.category,
    required this.limit,
    required this.spent,
  });

  double get ratio => limit <= 0 ? 0 : spent / limit;
  bool get isOver => limit > 0 && spent > limit;
  double get remaining => limit - spent;
}
