import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../services/auth_service.dart';
import '../sync/connectivity_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final conn = context.watch<ConnectivityService>();
    final deviceId = context.read<TaskRepository>().deviceId;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & account')),
      body: ListView(
        children: [
          const _Section('Account'),
          if (auth.user == null)
            const ListTile(
              leading: Icon(Icons.cloud_queue),
              title: Text('Not connected yet'),
              subtitle: Text('Your tasks are saved on this device. A sync account '
                  'is created automatically the first time you are online.'),
            )
          else if (auth.isAnonymous)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Guest account (this device)'),
              subtitle: const Text('Create an account to sync the same tasks '
                  'across several devices.'),
              trailing: FilledButton.tonal(
                onPressed: () => _showAuthDialog(context, register: true),
                child: const Text('Create'),
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(auth.email ?? 'Signed in'),
              subtitle: const Text('Sign in with this account on other devices '
                  'to see the same tasks.'),
            ),
          if (auth.user == null || auth.isAnonymous)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Sign in to an existing account'),
              subtitle: const Text('Tasks on this device are merged into it.'),
              onTap: () => _showAuthDialog(context, register: false),
            )
          else
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              subtitle: const Text('Tasks stay on this device.'),
              onTap: auth.signOut,
            ),
          const _Section('Connectivity'),
          SwitchListTile(
            secondary: const Icon(Icons.airplanemode_active),
            title: const Text('Work offline'),
            subtitle: const Text('Pause all syncing, as if there were no network. '
                'Handy for testing offline behaviour.'),
            value: conn.forcedOffline,
            onChanged: conn.setForcedOffline,
          ),
          ListTile(
            leading: Icon(conn.hasNetwork ? Icons.wifi : Icons.wifi_off),
            title: Text(conn.hasNetwork ? 'Network available' : 'No network'),
          ),
          const _Section('About'),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Device id'),
            subtitle: Text(deviceId),
          ),
        ],
      ),
    );
  }

  Future<void> _showAuthDialog(BuildContext context, {required bool register}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _AuthDialog(register: register, auth: context.read<AuthService>()),
    );
  }
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog({required this.register, required this.auth});
  final bool register;
  final AuthService auth;

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      if (widget.register) {
        await widget.auth.register(email, _password.text);
      } else {
        await widget.auth.signIn(email, _password.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = AuthService.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.register ? 'Create account' : 'Sign in'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.register ? 'Create' : 'Sign in'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
