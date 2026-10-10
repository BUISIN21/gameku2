import 'package:flutter/material.dart';

import '../core/config.dart';
import '../models/room_code.dart';
import '../services/api_client.dart';
import '../services/settings_store.dart';
import 'meeting_screen.dart';

/// Phase 2 home: pick a name, then create a meeting or join one by code.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings, this.invitedRoom});

  final SettingsStore settings;
  final String? invitedRoom;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.settings.displayName);
  late final _code = TextEditingController(text: widget.invitedRoom ?? '');
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your name';
    if (s.length > 40) return 'At most 40 characters';
    if (!RegExp(r"^[\p{L}\p{M}\p{N} .,'_-]+$", unicode: true).hasMatch(s)) {
      return 'Letters, numbers, spaces and . , \' _ - only';
    }
    return null;
  }

  bool _validName() {
    final ok = _validateName(_name.text) == null;
    if (!ok) _formKey.currentState?.validate();
    return ok;
  }

  Future<void> _createMeeting() async {
    if (!_validName()) return;
    final name = _name.text.trim();
    widget.settings.displayName = name;
    setState(() => _creating = true);
    try {
      final api = ApiClient(widget.settings.serverUrl);
      final code = await api.createRoom(displayName: name, accessKey: widget.settings.accessKey);
      if (!mounted) return;
      await _openMeeting(code, name);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'invalid_access_key') {
        await _openServerSettings(message: e.message);
      } else {
        _showError(e.message);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinMeeting() async {
    if (!_validName()) return;
    final code = RoomCode.parse(_code.text);
    if (code == null) {
      _showError('Enter a meeting code like abcd-efgh-jkmn, or paste the invitation link.');
      return;
    }
    final name = _name.text.trim();
    widget.settings.displayName = name;
    await _openMeeting(code, name);
  }

  Future<void> _openMeeting(String code, String name) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MeetingScreen(
        api: ApiClient(widget.settings.serverUrl),
        roomCode: code,
        displayName: name,
      ),
    ));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openServerSettings({String? message}) async {
    final server = TextEditingController(text: widget.settings.serverUrl);
    final key = TextEditingController(text: widget.settings.accessKey);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server settings'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (message != null) ...[
              Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: server,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://api.example.com'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Access key (only needed to create meetings)',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final url = server.text.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
        _showError('Server address must start with http:// or https://');
      } else {
        widget.settings.serverUrl = url;
        widget.settings.accessKey = key.text;
      }
    }
    server.dispose();
    key.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openServerSettings(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.video_call_rounded, size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Video meetings with anyone',
                        textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _name,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('createMeeting'),
                      onPressed: _creating ? null : _createMeeting,
                      icon: _creating
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: const Text('New meeting'),
                    ),
                    const SizedBox(height: 28),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or join one', style: theme.textTheme.labelLarge),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('roomCode'),
                      controller: _code,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Meeting code or link',
                        hintText: 'abcd-efgh-jkmn',
                        prefixIcon: Icon(Icons.keyboard_outlined),
                      ),
                      onSubmitted: (_) => _joinMeeting(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('joinMeeting'),
                      onPressed: _creating ? null : _joinMeeting,
                      icon: const Icon(Icons.login),
                      label: const Text('Join'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
