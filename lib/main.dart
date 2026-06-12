import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/feedback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyFinanceApp());
}

class FamilyFinanceApp extends StatelessWidget {
  const FamilyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'Family Finance',
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const _Root(),
      ),
    );
  }
}

/// Switches between the splash, login and the main app based on auth status.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final status = context.select<AppState, AppStatus>((s) => s.status);
    switch (status) {
      case AppStatus.initializing:
        return const _Splash();
      case AppStatus.signedOut:
      case AppStatus.error:
        return const LoginScreen();
      case AppStatus.signedIn:
        return const HomeShell();
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_rounded, size: 64),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
