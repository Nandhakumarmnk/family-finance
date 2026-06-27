import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Builds and sends "join my family" invitations.
///
/// We don't run an email server, so the invite is sent from the user's OWN
/// apps: it opens their email client, WhatsApp, or copies the message to the
/// clipboard — all via `url_launcher`, no extra dependency. The message carries
/// the **family code** the invitee types into "Join a family", plus a one-tap
/// app download link, so anyone can join from anywhere.
class InviteService {
  InviteService._();

  /// The human-readable invitation text shared with an invitee.
  static String buildMessage({
    required String familyName,
    required String familyCode,
    required String inviterName,
  }) {
    final fam = familyName.trim().isEmpty ? 'our family' : '"${familyName.trim()}"';
    final who = inviterName.trim().isEmpty ? 'Someone' : inviterName.trim();
    return '$who invited you to join $fam on ${AppConfig.appName} 💰\n\n'
        'It keeps our salary, expenses, EMIs and a shared family wallet in one '
        'place.\n\n'
        'How to join:\n'
        '1) Install the app: ${AppConfig.appDownloadUrl}\n'
        '2) Open it and sign in with Google\n'
        '3) Tap "Join a family" and enter this code:\n\n'
        '   FAMILY CODE: $familyCode\n\n'
        'That\'s it — you\'ll instantly share the family wallet and expenses.';
  }

  /// Opens the OS share options for [message], optionally pre-addressed to
  /// [toEmail] / [toPhone]. Returns false if nothing could be opened.
  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sendEmail(String message,
      {String? toEmail, String subject = 'Join our family on Family Finance'}) {
    final uri = Uri(
      scheme: 'mailto',
      path: (toEmail ?? '').trim(),
      query: 'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(message)}',
    );
    return _launch(uri);
  }

  static Future<bool> sendWhatsApp(String message, {String? toPhone}) {
    final phone = (toPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );
    return _launch(uri);
  }

  static Future<void> copy(String message) =>
      Clipboard.setData(ClipboardData(text: message));
}

/// Shows a bottom sheet letting the user send a family invite via their email
/// app, WhatsApp, or by copying the message. Safe to call without a recipient.
Future<void> showInviteSheet(
  BuildContext context, {
  required String familyName,
  required String familyCode,
  required String inviterName,
  String? toEmail,
  String? toPhone,
}) async {
  final message = InviteService.buildMessage(
    familyName: familyName,
    familyCode: familyCode,
    inviterName: inviterName,
  );
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invite to ${familyName.isEmpty ? 'your family' : familyName}',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Send the family code so they can join from any phone.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              // The code, prominent + copyable on its own.
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: familyCode));
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Family code copied')));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(familyCode,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ),
                      const Icon(Icons.copy_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _InviteAction(
                icon: Icons.email_outlined,
                label: 'Send by email',
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await InviteService.sendEmail(message, toEmail: toEmail);
                  if (!ok) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('No email app found — message copied'
                            ' instead')));
                    await InviteService.copy(message);
                  }
                },
              ),
              _InviteAction(
                icon: Icons.chat_outlined,
                label: 'Send on WhatsApp',
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await InviteService.sendWhatsApp(message, toPhone: toPhone);
                  if (!ok) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Couldn\'t open WhatsApp — message copied'
                            ' instead')));
                    await InviteService.copy(message);
                  }
                },
              ),
              _InviteAction(
                icon: Icons.copy_all_outlined,
                label: 'Copy invite message',
                onTap: () async {
                  Navigator.pop(ctx);
                  await InviteService.copy(message);
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Invite message copied')));
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InviteAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _InviteAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer, size: 20),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
