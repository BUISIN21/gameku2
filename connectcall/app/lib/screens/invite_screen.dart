import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/common.dart';
import 'room_screen.dart';

/// Shows who invited you and to what, lets you accept, and, if the room has
/// a waiting room, waits (live) for the owner's decision.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.inviteId});

  final String inviteId;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  InvitePreview? _preview;
  String? _error;
  bool _accepting = false;
  bool _waiting = false;
  bool _denied = false;
  StreamSubscription<DocumentSnapshot>? _memberSub;
  StreamSubscription<DocumentSnapshot>? _waitingSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    _waitingSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await AppScope.of(context).api.previewInvite(widget.inviteId);
      if (!mounted) return;
      if (p.alreadyMember) {
        _openRoom(p.roomId);
        return;
      }
      setState(() => _preview = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _openRoom(String roomId) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId)));
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      final (roomId, result) = await AppScope.of(context).api.acceptInvite(widget.inviteId);
      if (!mounted) return;
      if (result == AcceptResult.member) {
        _openRoom(roomId);
      } else {
        _waitForApproval(roomId);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  /// Watches our own membership and request documents (allowed by the
  /// security rules) so approval or refusal shows up instantly.
  void _waitForApproval(String roomId) {
    final scope = AppScope.of(context);
    final uid = scope.auth.currentUser!.uid;
    setState(() => _waiting = true);
    var sawRequest = false;
    _memberSub = scope.firestore.doc('rooms/$roomId/members/$uid').snapshots().listen((snap) {
      if (snap.exists && mounted) {
        showMessage(context, 'You were let in!');
        _openRoom(roomId);
      }
    }, onError: (_) {});
    _waitingSub = scope.firestore.doc('rooms/$roomId/waiting/$uid').snapshots().listen((snap) {
      if (snap.exists) {
        sawRequest = true;
      } else if (sawRequest && mounted) {
        // Request removed: approved (the member listener handles that) or declined.
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _waiting) setState(() => _denied = true);
        });
      }
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _preview;
    Widget body;
    if (_error != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.link_off, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(_error!, key: const Key('inviteError'), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ]);
    } else if (p == null) {
      body = const CircularProgressIndicator();
    } else if (_denied) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.do_not_disturb_on_outlined, size: 56),
        const SizedBox(height: 16),
        Text('The owner of "${p.roomName}" did not let you in.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ]);
    } else if (_waiting) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text('Waiting for ${p.ownerName} to let you in…',
            key: const Key('waitingForApproval'), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('You can leave this screen; the room appears on your home screen once approved.',
            textAlign: TextAlign.center),
      ]);
    } else {
      final usable = p.status == InviteStatus.valid;
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.mail_outline, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('${p.ownerName} invited you to', textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(p.roomName, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (!usable)
          Text(
            switch (p.status) {
              InviteStatus.revoked => 'This invitation was cancelled by the owner.',
              InviteStatus.expired => 'This invitation has expired. Ask for a new link.',
              InviteStatus.usedUp => 'This invitation has already been used. Ask for a new link.',
              InviteStatus.valid => '',
            },
            key: const Key('inviteError'),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          )
        else ...[
          if (p.requireApproval) const Text('The owner approves each new person.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('acceptInvite'),
            onPressed: _accepting ? null : _accept,
            child: _accepting
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(p.requireApproval ? 'Ask to join' : 'Accept invitation'),
          ),
        ],
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Invitation')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: body),
          ),
        ),
      ),
    );
  }
}
