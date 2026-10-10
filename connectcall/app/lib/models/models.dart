DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

class Profile {
  const Profile({required this.uid, required this.displayName, this.photoUrl, this.email});

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? email;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        uid: j['uid'] as String,
        displayName: j['displayName'] as String,
        photoUrl: j['photoUrl'] as String?,
        email: j['email'] as String?,
      );
}

class RoomDetails {
  const RoomDetails({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.requireApproval,
    required this.isOwner,
  });

  final String id;
  final String name;
  final String ownerName;
  final bool requireApproval;
  final bool isOwner;

  factory RoomDetails.fromJson(Map<String, dynamic> j) => RoomDetails(
        id: j['id'] as String,
        name: j['name'] as String,
        ownerName: j['ownerName'] as String? ?? '',
        requireApproval: j['requireApproval'] as bool? ?? false,
        isOwner: j['role'] == 'owner',
      );
}

enum InviteStatus { valid, revoked, expired, usedUp }

InviteStatus _status(Object? s) => switch (s) {
      'revoked' => InviteStatus.revoked,
      'expired' => InviteStatus.expired,
      'used_up' => InviteStatus.usedUp,
      _ => InviteStatus.valid,
    };

class Invite {
  const Invite({
    required this.id,
    required this.expiresAt,
    required this.maxUses,
    required this.uses,
    required this.status,
  });

  final String id;
  final DateTime? expiresAt;
  final int maxUses;
  final int uses;
  final InviteStatus status;

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(
        id: j['id'] as String,
        expiresAt: _date(j['expiresAt']),
        maxUses: j['maxUses'] as int,
        uses: j['uses'] as int,
        status: j['status'] != null ? _status(j['status']) : InviteStatus.valid,
      );
}

class InvitePreview {
  const InvitePreview({
    required this.roomId,
    required this.roomName,
    required this.ownerName,
    required this.requireApproval,
    required this.expiresAt,
    required this.status,
    required this.alreadyMember,
  });

  final String roomId;
  final String roomName;
  final String ownerName;
  final bool requireApproval;
  final DateTime? expiresAt;
  final InviteStatus status;
  final bool alreadyMember;

  factory InvitePreview.fromJson(Map<String, dynamic> j) => InvitePreview(
        roomId: j['roomId'] as String,
        roomName: j['roomName'] as String,
        ownerName: j['ownerName'] as String? ?? '',
        requireApproval: j['requireApproval'] as bool? ?? false,
        expiresAt: _date(j['expiresAt']),
        status: _status(j['status']),
        alreadyMember: j['alreadyMember'] as bool? ?? false,
      );
}

/// Accepting an invitation either makes you a member or puts you in the waiting room.
enum AcceptResult { member, waiting }
