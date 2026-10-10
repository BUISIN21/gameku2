/// Invitation links look like `https://<web-app>/?invite=<22-char id>`.
/// Users may paste the whole link or just the id.
class InviteLink {
  InviteLink._();

  static final _id = RegExp(r'^[A-Za-z0-9_-]{22}$');

  /// Returns the invitation id, or null if [input] is not a valid link/id.
  static String? parse(String input) {
    var raw = input.trim();
    final uri = Uri.tryParse(raw);
    final fromLink = uri?.queryParameters['invite'];
    if (fromLink != null && fromLink.isNotEmpty) raw = fromLink;
    return _id.hasMatch(raw) ? raw : null;
  }
}
