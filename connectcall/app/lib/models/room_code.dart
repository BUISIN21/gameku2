/// Room codes look like `abcd-efgh-jkmn`. Mirrors the backend's validation so
/// typos are caught before a network round-trip.
class RoomCode {
  RoomCode._();

  static final _pattern = RegExp(r'^[a-hjkmnp-z2-9]{4}-[a-hjkmnp-z2-9]{4}-[a-hjkmnp-z2-9]{4}$');

  /// Accepts a bare code or an invitation link containing `?room=<code>`.
  /// Returns the normalised code, or null if the input is not valid.
  static String? parse(String input) {
    var raw = input.trim();
    final uri = Uri.tryParse(raw);
    final fromLink = uri?.queryParameters['room'];
    if (fromLink != null && fromLink.isNotEmpty) raw = fromLink;
    final compact = raw.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    if (compact.length != 12) return null;
    final code = '${compact.substring(0, 4)}-${compact.substring(4, 8)}-${compact.substring(8)}';
    return _pattern.hasMatch(code) ? code : null;
  }
}
