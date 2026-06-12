import 'package:flutter/material.dart';

/// Global navigator key so we can show feedback overlays from anywhere
/// (including state classes) without needing a BuildContext. Wired into
/// MaterialApp in main.dart.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Lightweight SweetAlert-style feedback: an animated centered card that
/// pops in, holds briefly, then fades out. No external packages.
class AppFeedback {
  AppFeedback._();

  static void success(String message) => _show(message, isError: false);
  static void error(String message) => _show(message, isError: true);

  static void _show(String message, {required bool isError}) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FeedbackOverlay(
        message: message,
        isError: isError,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _FeedbackOverlay extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDone;
  const _FeedbackOverlay({
    required this.message,
    required this.isError,
    required this.onDone,
  });

  @override
  State<_FeedbackOverlay> createState() => _FeedbackOverlayState();
}

class _FeedbackOverlayState extends State<_FeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void initState() {
    super.initState();
    _c.forward();
    _sequence();
  }

  Future<void> _sequence() async {
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.isError ? scheme.error : const Color(0xFF1E8E5A);
    final icon = widget.isError ? Icons.error_outline_rounded : Icons.check_rounded;

    final fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    final pop = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

    return IgnorePointer(
      child: FadeTransition(
        opacity: fade,
        child: Container(
          color: Colors.black.withOpacity(0.18),
          alignment: Alignment.center,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(pop),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 220,
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withOpacity(0.14),
                      ),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.4, end: 1.0).animate(pop),
                        child: Icon(icon, color: accent, size: 38),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
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
