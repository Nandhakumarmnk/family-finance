/// A user/member registered in a family. Managed from the Master page.
/// Stored in the `Members` sheet of the shared family workbook so every
/// family member sees the same roster (multi-user support).
class Member {
  final String email;
  String name;
  String role; // Owner, Adult, Child, Guest...
  String relationship; // Self, Spouse, Father, Mother, Son, Daughter...
  String phone;
  bool active;

  Member({
    required this.email,
    required this.name,
    this.role = 'Adult',
    this.relationship = 'Other',
    this.phone = '',
    this.active = true,
  });

  // `relationship` is appended last so older 5-column sheets still load.
  List<dynamic> toRow() =>
      [email, name, role, phone, active ? 'yes' : 'no', relationship];

  static const List<String> header = [
    'email',
    'name',
    'role',
    'phone',
    'active',
    'relationship',
  ];

  factory Member.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return Member(
      email: at(0),
      name: at(1),
      role: at(2).isEmpty ? 'Adult' : at(2),
      phone: at(3),
      active: at(4).toLowerCase() != 'no',
      relationship: at(5).isEmpty ? 'Other' : at(5),
    );
  }

  static const List<String> roles = ['Owner', 'Adult', 'Child', 'Guest'];

  static const List<String> relationships = [
    'Self',
    'Spouse',
    'Father',
    'Mother',
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Grandparent',
    'Grandchild',
    'Other',
  ];
}
