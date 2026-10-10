/// What the backend returns when it lets a user into a room.
class JoinInfo {
  const JoinInfo({
    required this.serverUrl,
    required this.token,
    required this.roomCode,
    required this.identity,
  });

  final String serverUrl;
  final String token;
  final String roomCode;
  final String identity;

  factory JoinInfo.fromJson(Map<String, dynamic> json) => JoinInfo(
        serverUrl: json['serverUrl'] as String,
        token: json['token'] as String,
        roomCode: json['roomCode'] as String,
        identity: json['identity'] as String,
      );
}
