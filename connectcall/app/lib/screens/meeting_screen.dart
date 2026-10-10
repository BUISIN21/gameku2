import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../models/join_info.dart';
import '../services/api_client.dart';
import '../services/media_permissions.dart';
import '../widgets/control_bar.dart';
import '../widgets/device_settings_sheet.dart';
import '../widgets/participant_tile.dart';

enum _Phase { connecting, connected, failed, ended }

/// The live call: video tiles, controls, connection status and duration.
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key, required this.api, required this.roomCode, required this.displayName});

  final ApiClient api;
  final String roomCode;
  final String displayName;

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  _Phase _phase = _Phase.connecting;
  String _statusText = 'Joining…';
  String? _endedMessage;
  bool _reconnecting = false;
  bool _leaving = false;
  bool _micBusy = false;
  bool _camBusy = false;
  DateTime? _connectedAt;
  Timer? _ticker;
  final _isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _teardown();
    super.dispose();
  }

  Future<void> _teardown() async {
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;
    room?.removeListener(_onRoomChanged);
    await listener?.dispose();
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
  }

  Future<void> _connect() async {
    await _teardown();
    setState(() {
      _phase = _Phase.connecting;
      _statusText = 'Checking camera and microphone…';
      _endedMessage = null;
    });

    final perms = await MediaPermissions.request();
    if (!mounted) return;

    setState(() => _statusText = 'Asking the server for access…');
    final JoinInfo info;
    try {
      info = await widget.api.joinRoom(roomCode: widget.roomCode, displayName: widget.displayName);
    } on ApiException catch (e) {
      _fail(e.message);
      return;
    }
    if (!mounted) return;

    setState(() => _statusText = 'Connecting to the call…');
    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: CameraCaptureOptions(
          maxFrameRate: 30,
          params: VideoParametersPresets.h720_169,
        ),
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        ),
        defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
      ),
    );
    final listener = room.createListener();
    _room = room;
    _listener = listener;
    room.addListener(_onRoomChanged);
    listener
      ..on<RoomReconnectingEvent>((_) => setState(() => _reconnecting = true))
      ..on<RoomReconnectedEvent>((_) => setState(() => _reconnecting = false))
      ..on<RoomDisconnectedEvent>(_onDisconnected)
      ..on<ParticipantConnectedEvent>((e) => _toast('${_nameOf(e.participant)} joined'))
      ..on<ParticipantDisconnectedEvent>((e) => _toast('${_nameOf(e.participant)} left'))
      ..on<AudioPlaybackStatusChanged>((_) => setState(() {}));

    try {
      await room.connect(info.serverUrl, info.token);
    } catch (e) {
      if (_room == room) _fail('Could not connect to the call. ${_describe(e)}');
      return;
    }
    if (!mounted || _room != room) return;

    if (_isAndroid) {
      // Phones default to the earpiece; a video call should use the loudspeaker.
      unawaited(AudioManager.instance.setSpeakerOutputPreferred(true).catchError((_) {}));
    }

    setState(() {
      _phase = _Phase.connected;
      _connectedAt = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    final problems = <String>[];
    if (perms.microphone) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (e) {
        problems.add('Microphone unavailable: ${_describe(e)}');
      }
    } else {
      problems.add('Microphone permission was denied, so others cannot hear you.');
    }
    if (perms.camera) {
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (e) {
        problems.add('Camera unavailable: ${_describe(e)}');
      }
    } else {
      problems.add('Camera permission was denied, so others cannot see you.');
    }
    if (problems.isNotEmpty && mounted) _showPermissionProblems(problems, perms.permanentlyDenied);
  }

  void _fail(String message) {
    if (!mounted) return;
    _ticker?.cancel();
    setState(() {
      _phase = _Phase.failed;
      _statusText = message;
    });
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  void _onDisconnected(RoomDisconnectedEvent e) {
    if (_leaving || !mounted) return;
    _ticker?.cancel();
    final message = switch (e.reason) {
      DisconnectReason.participantRemoved => 'You were removed from the meeting.',
      DisconnectReason.roomDeleted => 'The meeting was ended.',
      DisconnectReason.duplicateIdentity => 'You joined this meeting from another device.',
      DisconnectReason.serverShutdown => 'The call server restarted. Try rejoining.',
      _ => 'The connection was lost and could not be restored.',
    };
    setState(() {
      _phase = _Phase.ended;
      _reconnecting = false;
      _endedMessage = message;
    });
  }

  String _describe(Object e) {
    final s = e.toString();
    if (s.contains('NotAllowedError') || s.contains('Permission')) return 'Permission was denied.';
    if (s.contains('NotFoundError') || s.contains('DevicesNotFound')) return 'No device was found.';
    if (s.contains('NotReadableError') || s.contains('Could not start')) {
      return 'The device is in use by another app.';
    }
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  String _nameOf(Participant p) => p.name.isNotEmpty ? p.name : 'Someone';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
  }

  void _showPermissionProblems(List<String> problems, bool permanentlyDenied) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera or microphone problem'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in problems) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• $p')),
          const SizedBox(height: 8),
          Text(kIsWeb
              ? 'Click the camera icon in the browser address bar, allow access, then use the buttons at the bottom of the call.'
              : 'You can stay in the call. Allow access in the app settings, then turn the device on with the buttons at the bottom.'),
        ]),
        actions: [
          if (_isAndroid && permanentlyDenied)
            TextButton(onPressed: MediaPermissions.openSettings, child: const Text('Open settings')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _toggleMic() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    setState(() => _micBusy = true);
    try {
      if (!lp.isMicrophoneEnabled() && _isAndroid) {
        final perms = await MediaPermissions.request();
        if (!perms.microphone) {
          _showPermissionProblems(['Microphone permission is denied.'], perms.permanentlyDenied);
          return;
        }
      }
      await lp.setMicrophoneEnabled(!lp.isMicrophoneEnabled());
    } catch (e) {
      _toast('Microphone: ${_describe(e)}');
    } finally {
      if (mounted) setState(() => _micBusy = false);
    }
  }

  Future<void> _toggleCamera() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    setState(() => _camBusy = true);
    try {
      if (!lp.isCameraEnabled() && _isAndroid) {
        final perms = await MediaPermissions.request();
        if (!perms.camera) {
          _showPermissionProblems(['Camera permission is denied.'], perms.permanentlyDenied);
          return;
        }
      }
      await lp.setCameraEnabled(!lp.isCameraEnabled());
    } catch (e) {
      _toast('Camera: ${_describe(e)}');
    } finally {
      if (mounted) setState(() => _camBusy = false);
    }
  }

  Future<void> _switchCamera() async {
    final track = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    final options = track.currentOptions;
    final current = options is CameraCaptureOptions ? options.cameraPosition : CameraPosition.front;
    try {
      await track.setCameraPosition(current.switched());
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Could not switch camera: ${_describe(e)}');
    }
  }

  Future<void> _confirmLeave() async {
    if (_phase != _Phase.connected) {
      await _leave();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave meeting?'),
        content: const Text('Others can keep talking. You can rejoin with the same code while it is valid.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true) await _leave();
  }

  Future<void> _leave() async {
    _leaving = true;
    _ticker?.cancel();
    await _teardown();
    if (mounted) Navigator.of(context).pop();
  }

  void _shareInvite() {
    final link = invitationLink(widget.roomCode);
    final text = link ?? widget.roomCode;
    Clipboard.setData(ClipboardData(text: text));
    _toast(link != null ? 'Invitation link copied' : 'Meeting code copied');
  }

  String get _duration {
    final start = _connectedAt;
    if (start == null) return '00:00';
    final d = DateTime.now().difference(start);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.meeting(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          body: SafeArea(
            child: switch (_phase) {
              _Phase.connecting => _StatusView(
                  icon: null,
                  message: _statusText,
                  actionLabel: 'Cancel',
                  onAction: _leave,
                ),
              _Phase.failed => _StatusView(
                  icon: Icons.error_outline,
                  message: _statusText,
                  actionLabel: 'Try again',
                  onAction: _connect,
                  secondaryLabel: 'Back',
                  onSecondary: _leave,
                ),
              _Phase.ended => _StatusView(
                  icon: Icons.call_end,
                  message: _endedMessage ?? 'Call ended.',
                  actionLabel: 'Rejoin',
                  onAction: _connect,
                  secondaryLabel: 'Back',
                  onSecondary: _leave,
                ),
              _Phase.connected => _buildCall(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCall(BuildContext context) {
    final room = _room!;
    final local = room.localParticipant;
    final remotes = room.remoteParticipants.values.toList()
      ..sort((a, b) => (a.joinedAt).compareTo(b.joinedAt));
    final micOn = local?.isMicrophoneEnabled() ?? false;
    final camOn = local?.isCameraEnabled() ?? false;

    return Column(children: [
      _TopBar(
        roomCode: widget.roomCode,
        duration: _duration,
        participantCount: remotes.length + 1,
        reconnecting: _reconnecting,
        onShare: _shareInvite,
      ),
      if (!room.canPlaybackAudio)
        MaterialBanner(
          content: const Text('Your browser blocked call audio.'),
          actions: [TextButton(onPressed: room.startAudio, child: const Text('Enable audio'))],
        ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _Stage(local: local, remotes: remotes, onShare: _shareInvite),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            ControlButton(
              key: const Key('toggleMic'),
              icon: micOn ? Icons.mic : Icons.mic_off,
              tooltip: micOn ? 'Mute microphone' : 'Unmute microphone',
              active: micOn,
              busy: _micBusy,
              onPressed: _toggleMic,
            ),
            ControlButton(
              key: const Key('toggleCamera'),
              icon: camOn ? Icons.videocam : Icons.videocam_off,
              tooltip: camOn ? 'Turn camera off' : 'Turn camera on',
              active: camOn,
              busy: _camBusy,
              onPressed: _toggleCamera,
            ),
            if (_isAndroid)
              ControlButton(
                icon: Icons.cameraswitch,
                tooltip: 'Switch front / rear camera',
                onPressed: camOn ? _switchCamera : null,
              ),
            if (!_isAndroid)
              ControlButton(
                icon: Icons.tune,
                tooltip: 'Choose microphone, camera and speaker',
                onPressed: () => DeviceSettingsSheet.show(context, room),
              ),
            ControlButton(
              key: const Key('leave'),
              icon: Icons.call_end,
              tooltip: 'Leave meeting',
              danger: true,
              onPressed: _confirmLeave,
            ),
          ],
        ),
      ),
    ]);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.roomCode,
    required this.duration,
    required this.participantCount,
    required this.reconnecting,
    required this.onShare,
  });

  final String roomCode;
  final String duration;
  final int participantCount;
  final bool reconnecting;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reconnecting ? Colors.amber : Colors.lightGreenAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              reconnecting ? 'Reconnecting…' : 'Connected · $duration',
              key: const Key('callStatus'),
              style: theme.textTheme.titleSmall,
            ),
            Text(
              '$roomCode · $participantCount in call',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        IconButton(tooltip: 'Copy invitation', onPressed: onShare, icon: const Icon(Icons.person_add_alt)),
      ]),
    );
  }
}

/// Lays out video tiles: speaker + self-view for 1:1 calls, a grid otherwise.
class _Stage extends StatelessWidget {
  const _Stage({required this.local, required this.remotes, required this.onShare});

  final LocalParticipant? local;
  final List<RemoteParticipant> remotes;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final me = local;
    if (remotes.isEmpty) {
      return Stack(children: [
        if (me != null) Positioned.fill(child: ParticipantTile(participant: me)),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: Center(
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Waiting for others to join…'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy invitation'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    }

    if (remotes.length == 1) {
      return LayoutBuilder(builder: (context, c) {
        final pipWidth = (c.maxWidth * 0.28).clamp(96.0, 220.0);
        return Stack(children: [
          Positioned.fill(child: ParticipantTile(participant: remotes.first)),
          if (me != null)
            Positioned(
              right: 12,
              bottom: 12,
              width: pipWidth,
              height: pipWidth * (c.maxWidth > c.maxHeight ? 9 / 16 : 4 / 3),
              child: ParticipantTile(participant: me, compact: true),
            ),
        ]);
      });
    }

    final all = <Participant>[?me, ...remotes];
    return LayoutBuilder(builder: (context, c) {
      final n = all.length;
      final landscape = c.maxWidth > c.maxHeight;
      var cols = 1;
      while (cols * (landscape ? cols : (cols + 1)) < n) {
        cols++;
      }
      if (!landscape && n <= 4) cols = n <= 2 ? 1 : 2;
      final rows = (n / cols).ceil();
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final h = (c.maxHeight - gap * (rows - 1)) / rows;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        alignment: WrapAlignment.center,
        children: [
          for (final p in all)
            SizedBox(width: w, height: h, child: ParticipantTile(key: ValueKey(p.sid), participant: p, compact: n > 4)),
        ],
      );
    });
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData? icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (icon == null)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 56, color: Colors.white70),
            const SizedBox(height: 24),
            Text(message, key: const Key('statusMessage'), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ]),
        ),
      ),
    );
  }
}
