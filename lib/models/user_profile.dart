/// Basic identity + household configuration for the signed-in user.
class UserProfile {
  final String email;
  String displayName;
  final String? photoUrl;

  /// Identifier of the family this user belongs to. Used to locate the
  /// shared family workbook on Google Drive. Empty == not in a family yet.
  String familyId;
  String familyName;

  /// ISO currency code used for display, e.g. "INR", "USD".
  String currencyCode;

  /// Phone / extra info captured on the "Add Details" screen.
  String phone;
  String occupation;

  UserProfile({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.familyId = '',
    this.familyName = '',
    this.currencyCode = 'INR',
    this.phone = '',
    this.occupation = '',
  });

  /// Row representation used when persisting to the `Profile` sheet.
  /// Order MUST match [profileHeader].
  List<dynamic> toRow() => [
        email,
        displayName,
        familyId,
        familyName,
        currencyCode,
        phone,
        occupation,
      ];

  static const List<String> profileHeader = [
    'email',
    'displayName',
    'familyId',
    'familyName',
    'currencyCode',
    'phone',
    'occupation',
  ];

  factory UserProfile.fromRow(List<dynamic> r, {String? photoUrl}) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return UserProfile(
      email: at(0),
      displayName: at(1),
      photoUrl: photoUrl,
      familyId: at(2),
      familyName: at(3),
      currencyCode: at(4).isEmpty ? 'INR' : at(4),
      phone: at(5),
      occupation: at(6),
    );
  }
}
