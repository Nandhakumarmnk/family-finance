/// A pending "request to join a family", filed by a prospective member and
/// awaiting the family head's approval. Stored one doc per requester in
/// `families/{familyId}/joinRequests/{sanitizedEmail}` so the head sees every
/// request and can Approve (→ becomes a member) or Decline it.
class JoinRequest {
  final String email;
  final String name;
  final String phone;

  /// When the request was filed (ISO-8601). Purely informational.
  final String requestedAt;

  JoinRequest({
    required this.email,
    this.name = '',
    this.phone = '',
    this.requestedAt = '',
  });

  List<dynamic> toRow() => [email, name, phone, requestedAt];

  static const List<String> header = ['email', 'name', 'phone', 'requestedAt'];

  factory JoinRequest.fromRow(List<dynamic> r) {
    String at(int i) => (i < r.length && r[i] != null) ? r[i].toString() : '';
    return JoinRequest(
      email: at(0),
      name: at(1),
      phone: at(2),
      requestedAt: at(3),
    );
  }
}
