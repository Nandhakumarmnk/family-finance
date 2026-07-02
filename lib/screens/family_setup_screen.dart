import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/invite_service.dart';
import '../state/app_state.dart';
import '../widgets/feedback.dart';

/// One-time onboarding shown after sign-in when the user isn't in a family yet.
/// Lets them either create a new family (becoming the **family head**), request
/// to join an existing one with a code (the head approves), or skip and use the
/// app solo. While a join request is awaiting approval it shows a waiting state.
class FamilySetupScreen extends StatefulWidget {
  const FamilySetupScreen({super.key});

  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

enum _Mode { choose, create, join }

class _FamilySetupScreenState extends State<FamilySetupScreen> {
  _Mode _mode = _Mode.choose;
  final _familyName = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _familyName.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _familyName.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final s = context.read<AppState>();
    await s.createFamily(name);
    if (mounted) setState(() => _busy = false);
    // Creating a family flips routing, which can unmount this screen when it's
    // the post-login gate. Present the "invite now" sheet via the app's root
    // navigator context so it shows regardless.
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) {
      await showInviteSheet(
        ctx,
        familyName: name,
        familyCode: s.familyCode,
        inviterName: s.profile?.displayName ?? '',
      );
    }
    _finish();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    final s = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await s.joinFamily(code);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case JoinResult.joined:
        _finish();
        break;
      case JoinResult.requested:
        // The screen rebuilds into the waiting state (hasPendingJoin == true).
        messenger.showSnackBar(const SnackBar(
            content: Text('Request sent — waiting for the family head to '
                'approve you.')));
        setState(() {});
        break;
      case JoinResult.notFound:
        messenger.showSnackBar(const SnackBar(
            content: Text('No family found for that code. Check it and try '
                'again.')));
        break;
      case JoinResult.invalidCode:
        messenger.showSnackBar(
            const SnackBar(content: Text('Enter a family code.')));
        break;
      case JoinResult.declined:
      case JoinResult.error:
        messenger.showSnackBar(SnackBar(
            content: Text(s.error ?? 'Could not send the request. Try again.')));
        break;
    }
  }

  Future<void> _refresh(AppState s) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await s.refreshPendingJoin();
    if (!mounted) return;
    switch (r) {
      case JoinResult.joined:
        messenger.showSnackBar(
            const SnackBar(content: Text("You're in! 🎉")));
        _finish();
        break;
      case JoinResult.declined:
        messenger.showSnackBar(const SnackBar(
            content: Text('Your request was declined or removed.')));
        break;
      default:
        messenger.showSnackBar(const SnackBar(
            content: Text('Still waiting for the family head to approve…')));
    }
  }

  /// When this screen was pushed on top of the app (e.g. from a "no family"
  /// prompt) pop it; when it IS the root gate after login, routing swaps it out.
  void _finish() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Waiting for a head to approve a join request → show the waiting state.
    if (s.hasPendingJoin) return _pendingView(theme, scheme, s);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.family_restroom_rounded,
                      size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text('Set up your family',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Share one common wallet and see everyone\'s expenses '
                    'together — or skip and just track your own money.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  if (_mode == _Mode.choose) ..._chooser(theme, scheme),
                  if (_mode == _Mode.create) ..._createForm(theme),
                  if (_mode == _Mode.join) ..._joinForm(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendingView(ThemeData theme, ColorScheme scheme, AppState s) {
    final fam = s.pendingFamilyName.isEmpty ? 'the family' : s.pendingFamilyName;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text('Waiting for approval',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Your request to join $fam has been sent. The family head '
                    'needs to approve you before you can see the shared wallet '
                    'and expenses.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: s.busy ? null : () => _refresh(s),
                    icon: s.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Check again'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: s.busy ? null : () => s.cancelPendingJoin(),
                    child: const Text('Cancel request'),
                  ),
                  const Divider(height: 32),
                  TextButton(
                    onPressed: () {
                      s.dismissFamilySetup();
                      _finish();
                    },
                    child: const Text('Use solo for now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _chooser(ThemeData theme, ColorScheme scheme) => [
        _ChoiceCard(
          icon: Icons.shield_moon_outlined,
          title: 'I\'m the family head',
          subtitle: 'Create a new family and invite everyone else.',
          onTap: () => setState(() => _mode = _Mode.create),
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          icon: Icons.group_add_outlined,
          title: 'Join my family',
          subtitle: 'I have a family code — send a request to the head.',
          onTap: () => setState(() => _mode = _Mode.join),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            context.read<AppState>().dismissFamilySetup();
            _finish();
          },
          child: const Text('Skip — use solo for now'),
        ),
      ];

  List<Widget> _createForm(ThemeData theme) => [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _mode = _Mode.choose),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _familyName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Family name',
            hintText: 'e.g. The Sharmas',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onSubmitted: (_) => _create(),
        ),
        const SizedBox(height: 8),
        Text(
          'You\'ll get a family code to share. Anyone with the code can '
          'request to join — you approve who actually gets in.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: const Text('Create family'),
        ),
      ];

  List<Widget> _joinForm(ThemeData theme) => [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _mode = _Mode.choose),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Family code',
            hintText: 'e.g. FAM-7KQ4-9XPM',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask the family head for the code shown in their invite. They\'ll get '
          'a request to approve before you can see the family\'s data.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _join,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: const Text('Request to join'),
        ),
      ];
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
