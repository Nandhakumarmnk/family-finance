import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/invite_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/image_data.dart';
import '../widgets/common.dart';
import 'family_setup_screen.dart';

/// "Add Details" — edit the signed-in user's profile and link/create a family.
class AddDetailsScreen extends StatefulWidget {
  const AddDetailsScreen({super.key});

  @override
  State<AddDetailsScreen> createState() => _AddDetailsScreenState();
}

class _AddDetailsScreenState extends State<AddDetailsScreen> {
  final _form = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _occupation;
  late TextEditingController _familyName;
  late String _currency;

  Future<void> _pickPhoto() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    await context.read<AppState>().updateProfilePhoto(bytes);
  }

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().profile!;
    _name = TextEditingController(text: p.displayName);
    _phone = TextEditingController(text: p.phone);
    _occupation = TextEditingController(text: p.occupation);
    _familyName = TextEditingController(text: p.familyName);
    _currency = p.currencyCode;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _occupation.dispose();
    _familyName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppState>();
    await s.updateProfile(
      displayName: _name.text.trim(),
      phone: _phone.text.trim(),
      occupation: _occupation.text.trim(),
      currencyCode: _currency,
    );
    final fname = _familyName.text.trim();
    if (s.inFamily &&
        fname.isNotEmpty &&
        fname != (s.family?.familyName ?? s.profile!.familyName)) {
      // Rename the family in place (the shared code stays the same).
      await s.renameFamily(fname);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Details saved')));
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile!;
    return Scaffold(
      appBar: AppBar(title: const Text('My Details')),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: Form(
          key: _form,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: imageProviderFor(p.avatarUrl),
                    child: (p.avatarUrl == null || p.avatarUrl!.isEmpty)
                        ? Text(p.displayName.isEmpty ? '?' : p.displayName[0])
                        : null,
                  ),
                  if (s.canAttachFiles)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Material(
                        color: Theme.of(context).colorScheme.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _pickPhoto,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.camera_alt,
                                size: 16,
                                color: Theme.of(context).colorScheme.onPrimary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (s.canAttachFiles && p.customPhotoUrl.isNotEmpty)
              Center(
                child: TextButton(
                  onPressed: () => s.removeProfilePhoto(),
                  child: const Text('Remove photo'),
                ),
              ),
            const SizedBox(height: 8),
            Center(child: Text(p.email)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _occupation,
              decoration: const InputDecoration(labelText: 'Occupation'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: Fmt.currencyCodes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v ?? 'INR'),
            ),
            const SizedBox(height: 28),
            Text('Family', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (s.inFamily) ...[
              Row(
                children: [
                  if (s.roleLabel.isNotEmpty)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: Icon(
                          s.isFamilyHead
                              ? Icons.shield_moon_outlined
                              : Icons.person_outline,
                          size: 16),
                      label: Text(s.roleLabel),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _familyName,
                decoration: const InputDecoration(labelText: 'Family name'),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Family code (share to invite)',
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        s.familyCode,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Invite',
                      icon: const Icon(Icons.person_add_alt),
                      onPressed: () => showInviteSheet(
                        context,
                        familyName: s.family?.familyName ?? '',
                        familyCode: s.familyCode,
                        inviterName: s.profile?.displayName ?? '',
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FamilySetupScreen())),
                icon: const Icon(Icons.family_restroom),
                label: const Text('Create or join a family'),
              ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: s.busy ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save details'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
