import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../state/app_state.dart';
import '../state/pin_controller.dart';

/// Shown on launch when a PIN is set and the app is locked. Unlocks the
/// already-restored session without re-doing Google sign-in.
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final BiometricService _bio = BiometricService();
  String _entry = '';
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh once a second so the cooldown countdown updates and the pad
    // re-enables itself the moment a lock-out expires.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Offer fingerprint / face unlock immediately if the user enabled it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptBiometric());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _promptBiometric() async {
    if (!mounted) return;
    final pin = context.read<PinController>();
    if (!pin.biometricEnabled || pin.isLockedOut) return;
    final ok = await _bio.authenticate();
    if (ok && mounted) context.read<PinController>().unlockViaBiometric();
  }

  void _onChanged(String value) {
    final pin = context.read<PinController>();
    if (pin.isLockedOut) return;
    setState(() {
      _entry = value;
      _error = null;
    });
    if (value.length == 4) {
      final ok = pin.unlock(value);
      if (!ok) {
        setState(() {
          _entry = '';
          _error = pin.isLockedOut
              ? null
              : 'Wrong PIN — ${pin.attemptsLeft} attempt'
                  '${pin.attemptsLeft == 1 ? '' : 's'} left';
        });
        HapticFeedback.mediumImpact();
      }
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset & start fresh?'),
        content: const Text(
          'This removes the PIN from this device and signs you out, so you can '
          'sign in again from scratch.\n\n'
          'Your finance data stays safe in Google Drive — nothing is deleted '
          'there.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final pin = context.read<PinController>();
    final app = context.read<AppState>();
    await app.signOut(); // back to the login screen
    await pin.clearAll(); // drop the PIN + any lock-out
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pin = context.watch<PinController>();
    final name = (s.profile?.displayName ?? '').split(' ').first;

    final lockedOut = pin.isLockedOut;
    final lockMessage = lockedOut
        ? 'Too many wrong attempts.\nTry again in ${_mmss(pin.lockRemaining)}.'
        : null;

    return Scaffold(
      body: SafeArea(
        child: _PinPad(
          title: name.isEmpty ? 'Enter your PIN' : 'Welcome back, $name',
          subtitle: lockedOut
              ? 'Locked for a moment'
              : 'Enter your 4-digit PIN to unlock',
          entry: _entry,
          error: _error,
          lockMessage: lockMessage,
          disabled: lockedOut,
          onChanged: _onChanged,
          footer: Column(
            children: [
              if (pin.biometricEnabled && !lockedOut)
                OutlinedButton.icon(
                  onPressed: _promptBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use fingerprint / face'),
                ),
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Forgot PIN? Reset & start fresh'),
              ),
              TextButton(
                onPressed: () => context.read<AppState>().signOut(),
                child: const Text('Use a different account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Cooldown countdown as "45s" or "1m 05s".
  String _mmss(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final sec = total % 60;
    return m > 0
        ? '${m}m ${sec.toString().padLeft(2, '0')}s'
        : '${sec}s';
  }
}

/// Set or change the app PIN (enter, then confirm).
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String _entry = '';
  String? _first;
  String? _error;

  void _onChanged(String value) async {
    setState(() {
      _entry = value;
      _error = null;
    });
    if (value.length != 4) return;

    if (_first == null) {
      setState(() {
        _first = value;
        _entry = '';
      });
    } else if (_first == value) {
      await context.read<PinController>().setPin(value);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'PINs did not match — start again';
        _first = null;
        _entry = '';
      });
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set app PIN')),
      body: SafeArea(
        child: _PinPad(
          title: _first == null ? 'Create a PIN' : 'Confirm your PIN',
          subtitle: _first == null
              ? 'Choose a 4-digit PIN'
              : 'Re-enter the same PIN',
          entry: _entry,
          error: _error,
          onChanged: _onChanged,
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  final String title;
  final String subtitle;
  final String entry;
  final String? error;
  final String? lockMessage;
  final bool disabled;
  final ValueChanged<String> onChanged;
  final Widget? footer;

  const _PinPad({
    required this.title,
    required this.subtitle,
    required this.entry,
    required this.error,
    required this.onChanged,
    this.lockMessage,
    this.disabled = false,
    this.footer,
  });

  void _tap(String digit) {
    if (entry.length < 4) onChanged(entry + digit);
  }

  void _back() {
    if (entry.isNotEmpty) onChanged(entry.substring(0, entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasError = error != null || lockMessage != null;

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: disabled
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(disabled ? Icons.lock_clock : Icons.lock_rounded,
                      color: disabled
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                      size: 30),
                ),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < entry.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? scheme.primary : Colors.transparent,
                        border: Border.all(
                            color: hasError
                                ? scheme.error
                                : scheme.primary.withOpacity(0.6),
                            width: 2),
                      ),
                    );
                  }),
                ),
                SizedBox(
                  height: 44,
                  child: hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(lockMessage ?? error!,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: scheme.error, fontSize: 12)),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                _Keypad(
                    onDigit: _tap, onBackspace: _back, enabled: !disabled),
                if (footer != null) ...[
                  const SizedBox(height: 12),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          final isBack = k == '<';
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: !enabled
                  ? null
                  : () => isBack ? onBackspace() : onDigit(k),
              child: Center(
                child: isBack
                    ? const Icon(Icons.backspace_outlined, size: 22)
                    : Text(k,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
