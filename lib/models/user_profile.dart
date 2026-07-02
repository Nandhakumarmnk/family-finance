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

  /// A family the user has ASKED to join but the head hasn't approved yet.
  /// Empty once they're approved (moved into [familyId]) or the request is
  /// cancelled/declined. Kept separate from [familyId] so a pending user gets
  /// no access to the family's data until the head lets them in.
  String pendingFamilyId;
  String pendingFamilyName;

  UserProfile({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.familyId = '',
    this.familyName = '',
    this.currencyCode = 'INR',
    this.phone = '',
    this.occupation = '',
    this.pendingFamilyId = '',
    this.pendingFamilyName = '',
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
        pendingFamilyId,
        pendingFamilyName,
      ];

  // New fields are APPENDED so older 7-column rows/docs still load cleanly.
  static const List<String> profileHeader = [
    'email',
    'displayName',
    'familyId',
    'familyName',
    'currencyCode',
    'phone',
    'occupation',
    'pendingFamilyId',
    'pendingFamilyName',
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
      pendingFamilyId: at(7),
      pendingFamilyName: at(8),
    );
  }
}
