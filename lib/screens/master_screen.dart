import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Master / Users page — the central place to manage the family's users
/// (multi-user roster), their roles, and invitations. Backed by the `Members`
/// sheet in the shared family workbook.
class MasterScreen extends StatelessWidget {
  const MasterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Users / Master')),
      floatingActionButton: s.inFamily
          ? FloatingActionButton.extended(
              onPressed: () => _memberDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Add user'),
            )
          : null,
      body: !s.inFamily
          ? const _NoFamilyHint()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _familyCard(context, s),
                const SizedBox(height: 8),
                const SectionHeader('Family members'),
                if (s.members.isEmpty)
                  const EmptyState(icon: Icons.groups_outlined, message: 'No members yet.')
                else
                  ...s.members.map((m) => _memberTile(context, s, m)),
                const SizedBox(height: 16),
                const SectionHeader('Master data'),
                _categoriesCard(context),
              ],
            ),
    );
  }

  Widget _familyCard(BuildContext context, AppState s) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Icon(Icons.family_restroom),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.family?.familyName ?? s.profile?.familyName ?? 'Family',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('ID: ${s.profile?.familyId ?? ''}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Text('${s.members.length}',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(BuildContext context, AppState s, Member m) {
    final isSelf = m.email == s.profile?.email;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
        title: Row(children: [
          Flexible(child: Text(m.name)),
          if (isSelf) const Padding(padding: EdgeInsets.only(left: 6), child: Chip(label: Text('You'), visualDensity: VisualDensity.compact)),
        ]),
        subtitle: Text('${m.email}\n${m.role} • ${m.relationship}'
            '${m.active ? '' : ' • inactive'}'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _memberDialog(context, existing: m);
            if (v == 'remove' && !isSelf) s.removeMember(m.email);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (!isSelf) const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }

  Widget _categoriesCard(BuildContext context) {
    // Master data reference — expense categories used app-wide.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expense categories', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _Tag('Food'), _Tag('Groceries'), _Tag('Rent'), _Tag('Utilities'),
                _Tag('Travel'), _Tag('Health'), _Tag('Education'), _Tag('Shopping'),
                _Tag('Entertainment'), _Tag('EMI'), _Tag('Insurance'), _Tag('Other'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _memberDialog(BuildContext context, {Member? existing}) async {
    final email = TextEditingController(text: existing?.email ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    String role = existing?.role ?? 'Adult';
    String relationship = existing?.relationship ?? 'Other';
    if (!Member.relationships.contains(relationship)) relationship = 'Other';
    bool active = existing?.active ?? true;
    bool invite = existing == null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Add user' : 'Edit user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  enabled: existing == null,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: Member.roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setS(() => role = v ?? role),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: relationship,
                  decoration: const InputDecoration(labelText: 'Relationship'),
                  items: Member.relationships
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setS(() => relationship = v ?? relationship),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setS(() => active = v),
                ),
                if (existing == null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send Drive invite'),
                    subtitle: const Text('Share the family workbook with this email'),
                    value: invite,
                    onChanged: (v) => setS(() => invite = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    final s = context.read<AppState>();
    final m = Member(
      email: email.text.trim(),
      name: name.text.trim().isEmpty ? email.text.split('@').first : name.text.trim(),
      role: role,
      relationship: relationship,
      phone: phone.text.trim(),
      active: active,
    );
    await s.addOrUpdateMember(m);
    if (existing == null && invite && m.email.isNotEmpty) {
      await s.inviteMember(m.email);
    }
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _NoFamilyHint extends StatelessWidget {
  const _NoFamilyHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: EmptyState(
        icon: Icons.groups_outlined,
        message: 'Set a Family ID in “My Details” first.\n'
            'Then you can add multiple users here and invite them to the '
            'shared family workbook.',
      ),
    );
  }
}
