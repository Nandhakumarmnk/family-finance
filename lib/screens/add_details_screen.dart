import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';

/// "Add Details" — edit the signed-in user's profile and link/create a family.
class AddDetailsScreen extends StatefulWidget {
  const AddDetailsScreen({super.key});

  @override
  State<AddDetailsScreen> createState() => _AddDetailsScreenState();
}

class _AddDetailsScreenState extends State<AddDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _occupation;
  late TextEditingController _familyId;
  late TextEditingController _familyName;
  late String _currency;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().profile!;
    _name = TextEditingController(text: p.displayName);
    _phone = TextEditingController(text: p.phone);
    _occupation = TextEditingController(text: p.occupation);
    _familyId = TextEditingController(text: p.familyId);
    _familyName = TextEditingController(text: p.familyName);
    _currency = p.currencyCode;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _occupation.dispose();
    _familyId.dispose();
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
    final fid = _familyId.text.trim();
    if (fid.isNotEmpty && fid != s.profile!.familyId ||
        (fid.isNotEmpty && !s.inFamily)) {
      await s.createOrJoinFamily(fid, _familyName.text.trim());
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Details saved to Drive')));
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile!;
    return Scaffold(
      appBar: AppBar(title: const Text('My Details')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                    ? NetworkImage(p.photoUrl!)
                    : null,
                child: (p.photoUrl == null || p.photoUrl!.isEmpty)
                    ? Text(p.displayName.isEmpty ? '?' : p.displayName[0])
                    : null,
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
            const SizedBox(height: 4),
            Text(
              'Use the same Family ID across family members to share one '
              'common wallet workbook on Drive.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _familyId,
              decoration: const InputDecoration(
                labelText: 'Family ID',
                hintText: 'e.g. sharma_family_2026',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _familyName,
              decoration: const InputDecoration(labelText: 'Family name'),
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
    );
  }
}
