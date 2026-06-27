import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/family_setup_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/pin_screen.dart';
import 'state/app_state.dart';
import 'state/pin_controller.dart';
import 'state/theme_controller.dart';
import 'theme.dart';
import 'widgets/feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firestoreEnabled = await _initFirebase();
  runApp(FamilyFinanceApp(firestoreEnabled: firestoreEnabled));
}

/// Initialise Firebase only when a real `firebase_options.dart` is present
/// (the shipped placeholder has empty keys). Returns true when the app should
/// use the global cloud (Firestore) backend; false keeps the legacy Drive path.
Future<bool> _initFirebase() async {
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (options.apiKey.isEmpty) return false;
    await Firebase.initializeApp(options: options);
    return true;
  } catch (_) {
    return false;
  }
}

class FamilyFinanceApp extends StatelessWidget {
  const FamilyFinanceApp({super.key, required this.firestoreEnabled});

  final bool firestoreEnabled;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AppState(firestoreEnabled: firestoreEnabled)..init()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => PinController()),
      ],
      child: Consumer<ThemeController>(
        builder: (_, theme, __) => MaterialApp(
          title: 'Family Finance',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavigatorKey,
          themeMode: theme.mode,
          theme: AppTheme.light(seed: theme.seed),
          darkTheme: AppTheme.dark(seed: theme.seed),
          home: const _Root(),
        ),
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
        final pin = context.watch<PinController>();
        if (!pin.loaded) return const _Splash();
        if (pin.isLocked) return const PinLockScreen();
        final needsSetup =
            context.select<AppState, bool>((s) => s.needsFamilySetup);
        if (needsSetup) return const FamilySetupScreen();
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
