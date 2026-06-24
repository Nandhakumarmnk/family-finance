/// A user-editable expense category with a pickable icon. Stored in the
/// `Categories` sheet of the personal workbook. The icon is persisted as a
/// stable string key (resolved by `CategoryIcons`) because an `IconData`
/// can't be written into a spreadsheet cell.
class Category {
  String name;
  String iconKey;

  Category({required this.name, this.iconKey = 'category'});

  List<dynamic> toRow() => [name, iconKey];

  static const List<String> header = ['name', 'iconKey'];

  factory Category.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Category(
      name: at(0),
      iconKey: at(1).isEmpty ? 'category' : at(1),
    );
  }

  /// The seed set used when a workbook has no categories yet. Matches the icons
  /// the app shipped with before categories became editable.
  static List<Category> defaults() => [
        Category(name: 'Food', iconKey: 'restaurant'),
        Category(name: 'Groceries', iconKey: 'grocery'),
        Category(name: 'Rent', iconKey: 'home'),
        Category(name: 'Utilities', iconKey: 'bolt'),
        Category(name: 'Travel', iconKey: 'car'),
        Category(name: 'Health', iconKey: 'health'),
        Category(name: 'Education', iconKey: 'school'),
        Category(name: 'Shopping', iconKey: 'shopping'),
        Category(name: 'Entertainment', iconKey: 'movie'),
        Category(name: 'EMI', iconKey: 'bank'),
        Category(name: 'Insurance', iconKey: 'shield'),
        Category(name: 'Other', iconKey: 'category'),
      ];
}
