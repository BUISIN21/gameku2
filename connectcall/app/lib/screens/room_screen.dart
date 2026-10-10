import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_scope.dart';
import '../core/config.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/common.dart';
import 'meeting_screen.dart';

/// A room's page: start/join the call, see members and, for the owner,
/// manage invitations, the waiting room and participants.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  RoomDetails? _room;
  String? _error;
  List<Invite>? _invites;
  bool _invitesLoading = false;
  StreamSubscription<DocumentSnapshot>? _membershipWatch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _membershipWatch?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final scope = AppScope.of(context);
    try {
      final room = await scope.api.room(widget.roomId);
      if (!mounted) return;
      setState(() => _room = room);
      _watchOwnMembership();
      if (room.isOwner) unawaited(_loadInvites());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Leaves this page if the owner removes us while it is open.
  void _watchOwnMembership() {
    final scope = AppScope.of(context);
    final uid = scope.auth.currentUser?.uid;
    if (uid == null || _membershipWatch != null) return;
    _membershipWatch = scope.firestore.doc('rooms/${widget.roomId}/members/$uid').snapshots().listen((snap) {
      if (!snap.exists && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        showMessage(context, 'You are no longer a member of "${_room?.name ?? 'this room'}".');
      }
    }, onError: (_) {});
  }

  Future<void> _loadInvites() async {
    setState(() => _invitesLoading = true);
    try {
      final list = await AppScope.of(context).api.invites(widget.roomId);
      if (mounted) setState(() => _invites = list);
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _invitesLoading = false);
    }
  }

  void _joinCall() {
    final room = _room!;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MeetingScreen(roomId: room.id, roomName: room.name, isOwner: room.isOwner),
    ));
  }

  Future<void> _createInvite() async {
    final invite = await showDialog<Invite>(context: context, builder: (_) => _CreateInviteDialog(roomId: widget.roomId));
    if (invite == null || !mounted) return;
    await _loadInvites();
    if (mounted) await _showInviteLink(invite);
  }

  Future<void> _showInviteLink(Invite invite) async {
    final link = invitationLink(invite.id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invitation link'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(link, key: const Key('inviteLinkText')),
          const SizedBox(height: 12),
          Text(
            'Anyone with this link can ask to join until ${_formatDate(invite.expiresAt)} '
            '(up to ${invite.maxUses} ${invite.maxUses == 1 ? 'person' : 'people'}). '
            'Share it only with people you want in this room. You can cancel it any time.',
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              showMessage(this.context, 'Invitation link copied');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(Invite invite) async {
    final ok = await confirm(context,
        title: 'Cancel invitation?',
        message: 'The link stops working immediately. People who already joined stay in the room.',
        action: 'Cancel invitation',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await AppScope.of(context).api.revokeInvite(widget.roomId, invite.id);
      await _loadInvites();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  Future<void> _decide(String uid, String name, bool approve) async {
    try {
      await AppScope.of(context).api.decide(widget.roomId, uid, approve: approve);
      if (mounted) showMessage(context, approve ? '$name can now join' : 'Request from $name declined');
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  Future<void> _remove(String uid, String name) async {
    final ok = await confirm(context,
        title: 'Remove $name?',
        message: '$name loses access to this room and is disconnected from the call. '
            'Invitation links will no longer work for them.',
        action: 'Remove',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await AppScope.of(context).api.removeMember(widget.roomId, uid);
      if (mounted) showMessage(context, '$name was removed');
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  Future<void> _leave() async {
    final ok = await confirm(context,
        title: 'Leave this room?',
        message: 'You will need a new invitation to come back.',
        action: 'Leave room',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await _membershipWatch?.cancel();
      _membershipWatch = null;
      if (!mounted) return;
      await AppScope.of(context).api.leaveRoom(widget.roomId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, e);
      _watchOwnMembership();
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(title: Text(room?.name ?? 'Room')),
      body: SafeArea(
        child: _error != null
            ? ErrorRetry(message: _error!, onRetry: _load)
            : room == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _buildBody(context, room),
                    ),
                  ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RoomDetails room) {
    final scope = AppScope.of(context);
    final me = scope.auth.currentUser?.uid;
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(room.isOwner ? 'You own this room' : 'Owner: ${room.ownerName}', style: theme.textTheme.bodyMedium),
      if (room.requireApproval)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(children: [Icon(Icons.shield_outlined, size: 18), SizedBox(width: 6), Text('Waiting room is on')]),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('joinCall'),
        onPressed: _joinCall,
        icon: const Icon(Icons.videocam),
        label: const Text('Join call'),
      ),

      if (room.isOwner) ...[
        _sectionTitle(context, 'Waiting room'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: scope.firestore.collection('rooms/${room.id}/waiting').orderBy('requestedAt').snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            if (snap.hasError) return const Text('Could not load requests.');
            if (docs.isEmpty) {
              return Text(
                room.requireApproval ? 'No one is waiting.' : 'Off. People with an invitation join directly.',
                style: theme.textTheme.bodySmall,
              );
            }
            return Column(children: [
              for (final d in docs)
                Card(
                  child: ListTile(
                    leading: UserAvatar(name: d.get('displayName') as String? ?? '?'),
                    title: Text(d.get('displayName') as String? ?? 'Someone'),
                    subtitle: const Text('Wants to join'),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.close),
                        onPressed: () => _decide(d.id, d.get('displayName') as String? ?? 'Someone', false),
                      ),
                      IconButton.filled(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check),
                        onPressed: () => _decide(d.id, d.get('displayName') as String? ?? 'Someone', true),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
        _sectionTitle(
          context,
          'Invitations',
          trailing: TextButton.icon(
            key: const Key('createInvite'),
            onPressed: _createInvite,
            icon: const Icon(Icons.add_link),
            label: const Text('New link'),
          ),
        ),
        if (_invitesLoading && _invites == null)
          const LinearProgressIndicator()
        else if ((_invites ?? const []).isEmpty)
          Text('No invitations yet. Create a link to invite people.', style: theme.textTheme.bodySmall)
        else
          for (final inv in _invites!)
            Card(
              child: ListTile(
                leading: Icon(inv.status == InviteStatus.valid ? Icons.link : Icons.link_off),
                title: Text(_inviteTitle(inv)),
                subtitle: Text('Used ${inv.uses} of ${inv.maxUses}'),
                onTap: inv.status == InviteStatus.valid ? () => _showInviteLink(inv) : null,
                trailing: inv.status == InviteStatus.valid
                    ? IconButton(tooltip: 'Cancel invitation', icon: const Icon(Icons.block), onPressed: () => _revoke(inv))
                    : null,
              ),
            ),
      ],

      _sectionTitle(context, 'Members'),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: scope.firestore.collection('rooms/${room.id}/members').orderBy('joinedAt').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return const Text('Could not load members.');
          if (!snap.hasData) return const LinearProgressIndicator();
          return Column(children: [
            for (final d in snap.data!.docs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(name: d.get('displayName') as String? ?? '?'),
                title: Text('${d.get('displayName')}${d.id == me ? ' (you)' : ''}'),
                subtitle: Text(d.get('role') == 'owner' ? 'Owner' : 'Member'),
                trailing: room.isOwner && d.id != me
                    ? IconButton(
                        tooltip: 'Remove from room',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _remove(d.id, d.get('displayName') as String? ?? 'this person'),
                      )
                    : null,
              ),
          ]);
        },
      ),

      if (!room.isOwner) ...[
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _leave,
          icon: const Icon(Icons.logout),
          label: const Text('Leave room'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade600),
        ),
      ],
    ]);
  }

  Widget _sectionTitle(BuildContext context, String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );

  String _inviteTitle(Invite inv) => switch (inv.status) {
        InviteStatus.valid => 'Valid until ${_formatDate(inv.expiresAt)}',
        InviteStatus.revoked => 'Cancelled',
        InviteStatus.expired => 'Expired',
        InviteStatus.usedUp => 'Fully used',
      };
}

String _formatDate(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class _CreateInviteDialog extends StatefulWidget {
  const _CreateInviteDialog({required this.roomId});

  final String roomId;

  @override
  State<_CreateInviteDialog> createState() => _CreateInviteDialogState();
}

class _CreateInviteDialogState extends State<_CreateInviteDialog> {
  int _hours = 24;
  int _uses = 5;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite =
          await AppScope.of(context).api.createInvite(widget.roomId, expiresInHours: _hours, maxUses: _uses);
      if (mounted) Navigator.pop(context, invite);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New invitation link'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Link works for'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 hour')),
            ButtonSegment(value: 24, label: Text('1 day')),
            ButtonSegment(value: 168, label: Text('7 days')),
          ],
          selected: {_hours},
          onSelectionChanged: (s) => setState(() => _hours = s.first),
        ),
        const SizedBox(height: 16),
        const Text('Number of people'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 5, label: Text('5')),
            ButtonSegment(value: 25, label: Text('25')),
          ],
          selected: {_uses},
          onSelectionChanged: (s) => setState(() => _uses = s.first),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _busy ? null : _create,
          child: const Text('Create link'),
        ),
      ],
    );
  }
}
