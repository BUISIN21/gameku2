/// What the backend returns when it lets a member into a call.
class JoinInfo {
  const JoinInfo({
    required this.serverUrl,
    required this.token,
    required this.roomId,
    required this.identity,
    required this.isOwner,
  });

  final String serverUrl;
  final String token;
  final String roomId;
  final String identity;
  final bool isOwner;

  factory JoinInfo.fromJson(Map<String, dynamic> json) => JoinInfo(
        serverUrl: json['serverUrl'] as String,
        token: json['token'] as String,
        roomId: json['roomId'] as String,
        identity: json['identity'] as String,
        isOwner: json['role'] == 'owner',
      );
}
