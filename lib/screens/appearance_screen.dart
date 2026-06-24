import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../state/app_state.dart';
import '../state/pin_controller.dart';
import '../state/theme_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pin_screen.dart';

/// Appearance settings — light/dark/system mode, the colour theme, and the
/// app lock (PIN + optional biometric unlock).
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final BiometricService _bio = BiometricService();
  // Probed once; the FutureBuilder below reuses the cached result so toggling
  // the switch doesn't make the tile flicker.
  late final Future<bool> _bioAvailable = _bio.isAvailable();

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeController>();
    final pin = context.watch<PinController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance & security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader('App lock'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.pin_outlined),
                  title: const Text('PIN lock'),
                  subtitle: Text(pin.isSet
                      ? 'Unlock with a 4-digit PIN — no Google sign-in each time'
                      : 'Set a 4-digit PIN to unlock the app quickly'),
                  value: pin.isSet,
                  onChanged: (on) async {
                    if (on) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SetPinScreen()),
                      );
                    } else {
                      await pin.removePin();
                    }
                  },
                ),
                if (pin.isSet)
                  FutureBuilder<bool>(
                    future: _bioAvailable,
                    builder: (ctx, snap) {
                      if (snap.data != true) return const SizedBox.shrink();
                      return Column(
                        children: [
                          const Divider(height: 1),
                          SwitchListTile(
                            secondary: const Icon(Icons.fingerprint),
                            title: const Text('Fingerprint / Face unlock'),
                            subtitle: const Text(
                                'Unlock with biometrics instead of typing the PIN'),
                            value: pin.biometricEnabled,
                            onChanged: _toggleBiometric,
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader('Reset'),
          Card(
            child: ListTile(
              leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
              title: const Text('Reset & start fresh'),
              subtitle: const Text(
                  'Remove the PIN and sign out on this device. Your finance '
                  'data stays safe in Google Drive — nothing is deleted there.'),
              onTap: () => _reset(context),
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader('Mode'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _ModeTile(
                    icon: Icons.brightness_auto,
                    label: 'System default',
                    selected: tc.mode == ThemeMode.system,
                    onTap: () => tc.setMode(ThemeMode.system),
                  ),
                  _ModeTile(
                    icon: Icons.light_mode,
                    label: 'Light',
                    selected: tc.mode == ThemeMode.light,
                    onTap: () => tc.setMode(ThemeMode.light),
                  ),
                  _ModeTile(
                    icon: Icons.dark_mode,
                    label: 'Dark',
                    selected: tc.mode == ThemeMode.dark,
                    onTap: () => tc.setMode(ThemeMode.dark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader('Colour theme'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final p in AppTheme.palettes)
                    _Swatch(
                      name: p.name,
                      color: p.color,
                      selected: tc.seed.value == p.color.value,
                      onTap: () => tc.setSeed(p.color),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Live preview of the current scheme.
          const SectionHeader('Preview'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          Color.lerp(theme.colorScheme.primary, Colors.black, 0.4)!,
                        ],
                      ),
                    ),
                    child: Text('Family Finance',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton(onPressed: () {}, child: const Text('Filled')),
                    OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                    Chip(label: const Text('Chip')),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometric(bool on) async {
    final pin = context.read<PinController>();
    if (!on) {
      await pin.setBiometric(false);
      return;
    }
    // Verify a real fingerprint/face before enabling, so the switch can't be
    // turned on by someone who can't actually pass the biometric check.
    final ok = await _bio.authenticate(
        reason: 'Confirm to enable biometric unlock');
    if (ok) {
      await pin.setBiometric(true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify biometrics')),
      );
    }
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    final pin = context.read<PinController>();
    final app = context.read<AppState>();
    navigator.popUntil((route) => route.isFirst); // leave the settings page
    await app.signOut();
    await pin.clearAll();
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(label,
          style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      trailing: selected ? Icon(Icons.check_circle, color: scheme.primary) : null,
      onTap: onTap,
    );
  }
}

class _Swatch extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 24)
                : null,
          ),
          const SizedBox(height: 6),
          Text(name, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
