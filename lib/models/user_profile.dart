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

  /// A custom avatar uploaded to Cloud Storage. When set it overrides the
  /// Google account photo. Persisted (unlike [photoUrl], which comes fresh
  /// from Google each sign-in and isn't stored).
  String customPhotoUrl;

  // --- app settings (synced to the cloud so they follow the user) -----------
  /// Appearance mode as a [ThemeMode] name: '', 'system', 'light' or 'dark'.
  /// Empty means "not set yet" (the device's local choice wins until then).
  String themeMode;

  /// The colour-theme seed as an ARGB int (0 == not set yet).
  int themeSeed;

  /// Whether device notifications for payment reminders are enabled.
  bool notificationsEnabled;

  /// Hour of day (0–23) at which reminder notifications fire.
  int reminderHour;

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
    this.customPhotoUrl = '',
    this.themeMode = '',
    this.themeSeed = 0,
    this.notificationsEnabled = true,
    this.reminderHour = 9,
  });

  /// The avatar to actually show: a custom uploaded photo wins over Google's.
  String? get avatarUrl =>
      customPhotoUrl.isNotEmpty ? customPhotoUrl : photoUrl;

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
        customPhotoUrl,
        themeMode,
        themeSeed,
        notificationsEnabled ? 'yes' : 'no',
        reminderHour,
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
    'customPhotoUrl',
    'themeMode',
    'themeSeed',
    'notificationsEnabled',
    'reminderHour',
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
      customPhotoUrl: at(9),
      themeMode: at(10),
      themeSeed: int.tryParse(at(11)) ?? 0,
      // Absent (older rows) → default ON; only an explicit 'no' disables.
      notificationsEnabled: at(12).isEmpty ? true : at(12).toLowerCase() == 'yes',
      reminderHour: at(13).isEmpty ? 9 : (int.tryParse(at(13)) ?? 9),
    );
  }
}
