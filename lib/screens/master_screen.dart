// material re-exports the Flutter foundation `Category` annotation, which would
// clash with our `Category` model — hide it so the model wins.
import 'package:flutter/material.dart' hide Category;
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../widgets/common.dart';

/// Master / Users page — manage the family's users (multi-user roster), their
/// roles and invitations (backed by the shared family workbook), plus the
/// editable **expense category master** (icons + names, stored per user in the
/// personal workbook).
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (s.inFamily) ...[
            _familyCard(context, s),
            const SizedBox(height: 8),
            const SectionHeader('Family members'),
            if (s.members.isEmpty)
              const EmptyState(
                  icon: Icons.groups_outlined, message: 'No members yet.')
            else
              ...s.members.map((m) => _memberTile(context, s, m)),
          ] else
            _noFamilyCard(context),
          const SizedBox(height: 16),
          SectionHeader(
            'Expense categories',
            trailing: TextButton.icon(
              onPressed: () => _categoryDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
          if (s.categories.isEmpty)
            const EmptyState(
                icon: Icons.category_outlined, message: 'No categories yet.')
          else
            ...s.categories.map((c) => _categoryTile(context, s, c)),
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('ID: ${s.profile?.familyId ?? ''}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Text('${s.members.length}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _noFamilyCard(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.groups_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Set a Family ID in “My Details” to add users and share a '
                'common wallet. You can still manage your expense categories '
                'below.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(BuildContext context, AppState s, Member m) {
    final isSelf = m.email == s.profile?.email;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
        title: Row(children: [
          Flexible(child: Text(m.name)),
          if (isSelf)
            const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(
                    label: Text('You'),
                    visualDensity: VisualDensity.compact)),
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
            if (!isSelf)
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }

  // --- category master -------------------------------------------------------
  Widget _categoryTile(BuildContext context, AppState s, Category c) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(CategoryIcons.byKey(c.iconKey),
              size: 20, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(c.name),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _categoryDialog(context, existing: c);
            if (v == 'delete') s.deleteCategory(c.name);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Future<void> _categoryDialog(BuildContext context, {Category? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String iconKey = existing?.iconKey ?? CategoryIcons.keys.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(existing == null ? 'Add category' : 'Edit category'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: existing == null,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 16),
                  Text('Icon', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in CategoryIcons.keys)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setS(() => iconKey = k),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: k == iconKey
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: k == iconKey
                                    ? scheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Icon(CategoryIcons.byKey(k),
                                size: 22,
                                color: k == iconKey
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (saved != true || !context.mounted) return;
    final s = context.read<AppState>();
    if (existing == null) {
      await s.addCategory(nameCtrl.text, iconKey);
    } else {
      await s.updateCategory(existing.name, nameCtrl.text, iconKey);
    }
  }

  // --- members ---------------------------------------------------------------
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
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: Member.roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
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
                    subtitle: const Text(
                        'Share the family workbook with this email'),
                    value: invite,
                    onChanged: (v) => setS(() => invite = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    final s = context.read<AppState>();
    final m = Member(
      email: email.text.trim(),
      name: name.text.trim().isEmpty
          ? email.text.split('@').first
          : name.text.trim(),
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
