import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/config.dart';
import '../services/auth_service.dart';

/// Sign in, create an account, or request a password-reset e-mail.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.hasInvite = false});

  final bool hasInvite;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = AppScope.of(context).auth;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await auth.register(email: _email.text, password: _password.text, displayName: _name.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
      // AuthGate switches to the home screen automatically.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Type your e-mail address above first, then tap "Forgot password?" again.');
      return;
    }
    try {
      await AppScope.of(context).auth.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('If an account exists for $email, a reset link has been sent.')),
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.video_call_rounded, size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(AppConfig.appName, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      widget.hasInvite
                          ? 'Sign in or create an account to accept your invitation.'
                          : (_register ? 'Create your account' : 'Sign in to continue'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                        validator: validateDisplayName,
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                      validator: (v) => (v ?? '').trim().contains(RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$'))
                          ? null
                          : 'Enter a valid e-mail address',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        helperText: _register ? 'At least 8 characters' : null,
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return 'Enter your password';
                        if (_register && v!.length < 8) return 'Use at least 8 characters';
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, key: const Key('authError'), style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    if (!_register)
                      TextButton(onPressed: _busy ? null : _forgotPassword, child: const Text('Forgot password?')),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(_register ? 'I already have an account' : 'New here? Create an account'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors the backend's display-name rules.
String? validateDisplayName(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your name';
  if (s.length > 40) return 'At most 40 characters';
  if (!RegExp(r"^[\p{L}\p{M}\p{N} .,'_-]+$", unicode: true).hasMatch(s)) {
    return "Letters, numbers, spaces and . , ' _ - only";
  }
  return null;
}
