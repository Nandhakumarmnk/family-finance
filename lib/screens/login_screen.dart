import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.seed,
              Color.lerp(AppTheme.seed, Colors.black, 0.45)!,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Brand mark
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded,
                          size: 42, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Family Finance',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Salary, expenses, EMIs and a shared family wallet — '
                      'all stored securely in your own Google Drive.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white.withOpacity(0.82)),
                    ),
                    const SizedBox(height: 32),

                    // Sign-in card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Column(
                          children: [
                            Text('Welcome',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(
                              'Sign in to continue',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            if (state.error != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: scheme.errorContainer.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: scheme.error.withOpacity(0.4)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline,
                                        size: 18, color: scheme.error),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        state.error!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: scheme.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            FilledButton.icon(
                              onPressed: state.busy ? null : () => state.signIn(),
                              icon: state.busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(state.busy
                                  ? 'Signing in…'
                                  : 'Sign in with Google'),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 14, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Only files this app creates (drive.file)',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your data stays in your Google Drive.',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white.withOpacity(0.6)),
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
