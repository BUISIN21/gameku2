import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/firebase_setup.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'login_screen.dart' show validateDisplayName;

/// Profile (name, picture), app settings and sign-out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _photo = TextEditingController();
  final _server = TextEditingController();
  Profile? _profile;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _photo.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    _server.text = scope.settings.serverUrl;
    setState(() => _error = null);
    try {
      final p = await scope.api.me();
      if (!mounted) return;
      setState(() => _profile = p);
      _name.text = p.displayName;
      _photo.text = p.photoUrl ?? '';
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final scope = AppScope.of(context);
    setState(() => _saving = true);
    try {
      final photo = _photo.text.trim();
      final p = await scope.api.updateProfile(displayName: _name.text.trim(), photoUrl: photo.isEmpty ? null : photo);
      // Keep Firebase Auth in sync so the name shows up in new ID tokens too.
      await scope.auth.currentUser?.updateDisplayName(p.displayName);
      await scope.auth.currentUser?.updatePhotoURL(p.photoUrl);
      if (!mounted) return;
      setState(() => _profile = p);
      showMessage(context, 'Profile saved');
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveServer() {
    final url = _server.text.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      showMessage(context, 'Server address must start with http:// or https://');
      return;
    }
    AppScope.of(context).settings.serverUrl = url;
    showMessage(context, 'Server address saved');
  }

  Future<void> _signOut() async {
    final ok = await confirm(context, title: 'Sign out?', message: 'You will need your password to sign in again.', action: 'Sign out');
    if (!ok || !mounted) return;
    final auth = AppScope.of(context).auth;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final email = AppScope.of(context).auth.currentUser?.email;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: SafeArea(
        child: _error != null && p == null
            ? ErrorRetry(message: _error!, onRetry: _load)
            : p == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Form(
                        key: _form,
                        child: ListView(padding: const EdgeInsets.all(16), children: [
                          Center(child: UserAvatar(name: p.displayName, photoUrl: p.photoUrl, radius: 44)),
                          const SizedBox(height: 8),
                          if (email != null) Center(child: Text(email)),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _name,
                            maxLength: 40,
                            decoration: const InputDecoration(labelText: 'Display name'),
                            validator: validateDisplayName,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _photo,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Profile picture URL (optional)',
                              helperText: 'A link to an image starting with https://',
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return null;
                              final u = Uri.tryParse(s);
                              return u != null && u.isScheme('https') && u.host.isNotEmpty ? null : 'Must start with https://';
                            },
                          ),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _saving ? null : _save, child: const Text('Save profile')),
                          const Divider(height: 48),
                          Text('Advanced', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _server,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: 'Server address',
                              suffixIcon: IconButton(tooltip: 'Save', icon: const Icon(Icons.check), onPressed: _saveServer),
                            ),
                          ),
                          if (FirebaseSetup.usingEmulator)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Development build: using local Firebase emulators.'),
                            ),
                          const Divider(height: 48),
                          OutlinedButton.icon(
                            key: const Key('signOut'),
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout),
                            label: const Text('Sign out'),
                          ),
                        ]),
                      ),
                    ),
                  ),
      ),
    );
  }
}
