import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/config.dart';
import '../models/invite_link.dart';
import '../widgets/common.dart';
import 'invite_screen.dart';
import 'profile_screen.dart';
import 'room_screen.dart';

/// Signed-in home: your rooms, create a room, join with an invitation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user, this.pendingInvite});

  final User user;
  final String? pendingInvite;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The invitation from the page URL is opened once per app session.
  static bool _pendingInviteHandled = false;
  final _invite = TextEditingController();

  @override
  void initState() {
    super.initState();
    final pending = widget.pendingInvite;
    if (pending != null && !_pendingInviteHandled) {
      _pendingInviteHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInvite(pending));
    }
  }

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  void _openInvite(String inviteId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(inviteId: inviteId)));
  }

  void _openRoom(String roomId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId)));
  }

  void _joinWithInvite() {
    final id = InviteLink.parse(_invite.text);
    if (id == null) {
      showMessage(context, 'Paste the full invitation link you received.');
      return;
    }
    _invite.clear();
    _openInvite(id);
  }

  Future<void> _createRoom() async {
    final created = await showDialog<String>(context: context, builder: (_) => const _CreateRoomDialog());
    if (created != null && mounted) _openRoom(created);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final memberships = scope.firestore
        .collection('users/${widget.user.uid}/memberships')
        .orderBy('joinedAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Profile and settings',
            icon: UserAvatar(name: widget.user.displayName ?? '?', photoUrl: widget.user.photoURL, radius: 16),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newRoom'),
        onPressed: _createRoom,
        icon: const Icon(Icons.add),
        label: const Text('New room'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text('Join with an invitation', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('inviteLink'),
                      controller: _invite,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'Paste invitation link',
                        prefixIcon: Icon(Icons.link),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _joinWithInvite(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(80, 48)),
                    onPressed: _joinWithInvite,
                    child: const Text('Open'),
                  ),
                ]),
                const SizedBox(height: 28),
                Text('Your rooms', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: memberships,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const EmptyState(
                        icon: Icons.cloud_off,
                        title: 'Could not load your rooms',
                        message: 'Check your connection. The list updates automatically when you are back online.',
                      );
                    }
                    if (!snap.hasData) {
                      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const EmptyState(
                        icon: Icons.meeting_room_outlined,
                        title: 'No rooms yet',
                        message: 'Create a room and invite people, or open an invitation link you received.',
                      );
                    }
                    return Column(children: [
                      for (final d in docs)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.meeting_room_outlined),
                            title: Text(d.get('roomName') as String? ?? 'Room'),
                            subtitle: Text(d.get('role') == 'owner' ? 'You own this room' : 'Member'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openRoom(d.id),
                          ),
                        ),
                    ]);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog();

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _approval = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await AppScope.of(context).api.createRoom(name: _name.text.trim(), requireApproval: _approval);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New room'),
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            key: const Key('roomName'),
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Room name', hintText: 'Family call'),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return 'Enter a name';
              if (!RegExp(r"^[\p{L}\p{M}\p{N}\p{Zs}.,'!?&()_#:-]+$", unicode: true).hasMatch(s)) {
                return 'Unsupported characters';
              }
              return null;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _approval,
            onChanged: (v) => setState(() => _approval = v),
            title: const Text('Waiting room'),
            subtitle: const Text('You approve each person who uses an invitation'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _busy ? null : _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
