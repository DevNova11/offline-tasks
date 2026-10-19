import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../services/auth_service.dart';
import '../sync/connectivity_service.dart';
import 'theme.dart';
import 'widgets/ios.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final conn = context.watch<ConnectivityService>();
    final deviceId = context.read<TaskRepository>().deviceId;
    final secondary = AppText.secondary(context);

    final (String accountTitle, String accountSubtitle, IconData accountIcon) =
        auth.uid == null
            ? ('Not Connected Yet', 'An account is created the first time you are online.',
                CupertinoIcons.cloud)
            : auth.isAnonymous
                ? ('Guest', 'Synced from this device only', CupertinoIcons.person)
                : (auth.email ?? 'Signed In', 'Syncing across your devices',
                    CupertinoIcons.person_crop_circle_fill_badge_checkmark);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
        previousPageTitle: 'Tasks',
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            CupertinoListSection.insetGrouped(
              header: const SectionHeader('Account'),
              footer: Text(
                auth.isAnonymous
                    ? 'Create an account to use the same tasks on several devices. '
                        'Your current tasks move with you.'
                    : 'Sign in with this account on another device to see the same tasks.',
                style: secondary,
              ),
              children: [
                CupertinoListTile(
                  leadingSize: 44,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: resolve(context, CupertinoColors.systemGrey4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(accountIcon, color: CupertinoColors.white, size: 24),
                  ),
                  title: Text(accountTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(accountSubtitle),
                ),
                if (auth.uid != null && auth.isAnonymous)
                  CupertinoListTile(
                    title: Text('Create Account',
                        style: TextStyle(color: resolve(context, CupertinoColors.systemBlue))),
                    onTap: () => _showAuth(context, register: true),
                  ),
                if (auth.uid == null || auth.isAnonymous)
                  CupertinoListTile(
                    title: Text('Sign In to Existing Account',
                        style: TextStyle(color: resolve(context, CupertinoColors.systemBlue))),
                    onTap: () => _showAuth(context, register: false),
                  )
                else
                  CupertinoListTile(
                    title: Text('Sign Out',
                        style: TextStyle(color: resolve(context, CupertinoColors.systemRed))),
                    onTap: () => _confirmSignOut(context, auth),
                  ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const SectionHeader('Connectivity'),
              footer: Text(
                'Work Offline pauses all syncing as if there were no network, '
                'which is handy for testing offline behaviour.',
                style: secondary,
              ),
              children: [
                CupertinoListTile(
                  leading: _box(context, CupertinoIcons.airplane, CupertinoColors.systemOrange),
                  title: const Text('Work Offline'),
                  trailing: CupertinoSwitch(
                    value: conn.forcedOffline,
                    onChanged: conn.setForcedOffline,
                  ),
                ),
                CupertinoListTile(
                  leading: _box(context, CupertinoIcons.wifi, CupertinoColors.systemBlue),
                  title: const Text('Network'),
                  additionalInfo: Text(conn.hasNetwork ? 'Available' : 'None'),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const SectionHeader('About'),
              children: [
                CupertinoListTile(
                  leading: _box(context, CupertinoIcons.device_phone_portrait,
                      CupertinoColors.systemGrey),
                  title: const Text('Device ID'),
                  additionalInfo: Text(deviceId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(BuildContext context, IconData icon, Color color) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: resolve(context, color),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 17, color: CupertinoColors.white),
      );

  Future<void> _confirmSignOut(BuildContext context, AuthService auth) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('Your tasks stay on this device.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok == true) await auth.signOut();
  }

  Future<void> _showAuth(BuildContext context, {required bool register}) {
    return showCupertinoDialog<void>(
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
    return CupertinoAlertDialog(
      title: Text(widget.register ? 'Create Account' : 'Sign In'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            CupertinoTextField(
              controller: _email,
              placeholder: 'Email',
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _password,
              placeholder: 'Password',
              obscureText: true,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                      color: resolve(context, CupertinoColors.systemRed), fontSize: 13)),
            ],
            if (_busy) ...[
              const SizedBox(height: 10),
              const CupertinoActivityIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _busy ? null : _submit,
          child: Text(widget.register ? 'Create' : 'Sign In'),
        ),
      ],
    );
  }
}
