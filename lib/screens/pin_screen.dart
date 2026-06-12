import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  String _entry = '';
  String? _error;

  void _onChanged(String value) {
    setState(() {
      _entry = value;
      _error = null;
    });
    if (value.length == 4) {
      final ok = context.read<PinController>().unlock(value);
      if (!ok) {
        setState(() {
          _error = 'Wrong PIN, try again';
          _entry = '';
        });
        HapticFeedback.mediumImpact();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final name = (s.profile?.displayName ?? '').split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: _PinPad(
          title: name.isEmpty ? 'Enter your PIN' : 'Welcome back, $name',
          subtitle: 'Enter your 4-digit PIN to unlock',
          entry: _entry,
          error: _error,
          onChanged: _onChanged,
          footer: TextButton(
            onPressed: () => context.read<AppState>().signOut(),
            child: const Text('Use a different account'),
          ),
        ),
      ),
    );
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
  final ValueChanged<String> onChanged;
  final Widget? footer;

  const _PinPad({
    required this.title,
    required this.subtitle,
    required this.entry,
    required this.error,
    required this.onChanged,
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

    return Center(
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
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.lock_rounded,
                    color: scheme.onPrimaryContainer, size: 30),
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle,
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
                          color: error != null
                              ? scheme.error
                              : scheme.primary.withOpacity(0.6),
                          width: 2),
                    ),
                  );
                }),
              ),
              SizedBox(
                height: 28,
                child: error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: TextStyle(color: scheme.error, fontSize: 12)),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              _Keypad(onDigit: _tap, onBackspace: _back),
              if (footer != null) ...[
                const SizedBox(height: 12),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  const _Keypad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return GridView.count(
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
            onTap: () => isBack ? onBackspace() : onDigit(k),
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
    );
  }
}
