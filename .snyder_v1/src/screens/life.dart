import 'package:flutter/material.dart';
import '../db.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key, required this.token, required this.refresh, required this.openSettings});
  final int token;
  final VoidCallback refresh;
  final VoidCallback openSettings;
  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  int view = 0;

  @override
  Widget build(BuildContext context) {
    return SnyderPage(
      title: 'Snyder Life',
      subtitle: 'Tasks • Family • Home goals',
      actions: [IconButton(onPressed: widget.openSettings, icon: const Icon(Icons.settings_outlined, color: SnyderColors.cyan))],
      child: Column(children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.task_alt), label: Text('Tasks')),
            ButtonSegment(value: 1, icon: Icon(Icons.family_restroom), label: Text('Family')),
            ButtonSegment(value: 2, icon: Icon(Icons.home_work_outlined), label: Text('Home Goals')),
          ],
          selected: {view},
          onSelectionChanged: (s) => setState(() => view = s.first),
        ),
        const SizedBox(height: 12),
        IndexedStack(index: view, children: [_tasks(), _family(), _homeGoals()]),
      ]),
    );
  }

  Widget _tasks() => FutureBuilder<List<Map<String, Object?>>>(
        key: ValueKey('tasks-${widget.token}'),
        future: AppDb.i.rows('tasks', orderBy: 'done ASC, due_date ASC, id ASC'),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          return SnyderCard(
            child: Column(children: [
              sectionTitle(Icons.task_alt, 'Household Tasks', trailing: IconButton(onPressed: () => _taskDialog(), icon: const Icon(Icons.add))),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No tasks yet.')),
              ...items.map((t) {
                final done = (t['done'] as int) == 1;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: done,
                  title: Text(t['name'].toString(), style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
                  subtitle: Text([t['category'], (t['due_date']?.toString().isNotEmpty == true ? shortDate(parseDate(t['due_date'])) : t['due_label'])].where((x) => x?.toString().isNotEmpty == true).join(' • ')),
                  secondary: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await _taskDialog(existing: t);
                      if (v == 'delete') {
                        await AppDb.i.delete('tasks', t['id'] as int);
                        widget.refresh();
                      }
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                  ),
                  onChanged: (v) async {
                    await AppDb.i.update('tasks', {'done': v == true ? 1 : 0, 'completed_at': v == true ? AppDb.i.now() : null}, t['id'] as int);
                    widget.refresh();
                  },
                );
              }),
            ]),
          );
        },
      );

  Widget _family() => FutureBuilder<List<Map<String, Object?>>>(
        key: ValueKey('family-${widget.token}'),
        future: AppDb.i.rows('household_members', orderBy: 'id ASC'),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          return SnyderCard(
            accent: SnyderColors.violet,
            child: Column(children: [
              sectionTitle(Icons.family_restroom, 'Family / Household', trailing: IconButton(onPressed: () => _memberDialog(), icon: const Icon(Icons.person_add_alt_1))),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Keep household roles, notes, homeschool context, and home responsibilities in one place.', style: TextStyle(color: SnyderColors.muted, fontSize: 12))),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Add household members when useful. This is optional.')),
              ...items.map((m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(backgroundColor: Color(0x3328E8FF), child: Icon(Icons.person, color: SnyderColors.cyan)),
                    title: Text(m['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([m['role'], m['notes']].where((x) => x?.toString().isNotEmpty == true).join(' • ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') await _memberDialog(existing: m);
                        if (v == 'delete') { await AppDb.i.delete('household_members', m['id'] as int); widget.refresh(); }
                      },
                      itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                    ),
                  )),
            ]),
          );
        },
      );

  Widget _homeGoals() => FutureBuilder<List<Map<String, Object?>>>(
        key: ValueKey('homegoals-${widget.token}'),
        future: AppDb.i.rows('home_goals', orderBy: 'done ASC, id ASC'),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          return SnyderCard(
            accent: SnyderColors.blue,
            child: Column(children: [
              sectionTitle(Icons.home_work_outlined, 'Home Goals / Family Priorities', trailing: IconButton(onPressed: () => _homeGoalDialog(), icon: const Icon(Icons.add))),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Backyard setup, pool safety, family trips, PC setup, pups — anything that matters to your home.')),
              ...items.map((g) {
                final target = g['target_cents'] as int;
                final saved = g['saved_cents'] as int;
                final done = (g['done'] as int) == 1;
                final progress = target <= 0 ? (done ? 1.0 : 0.0) : (saved / target).clamp(0.0, 1.0).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(done ? Icons.check_circle : Icons.star_border, color: done ? SnyderColors.green : SnyderColors.cyan),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g['name'].toString(), style: TextStyle(fontWeight: FontWeight.w800, decoration: done ? TextDecoration.lineThrough : null))),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') await _homeGoalDialog(existing: g);
                          if (v == 'toggle') { await AppDb.i.update('home_goals', {'done': done ? 0 : 1}, g['id'] as int); widget.refresh(); }
                          if (v == 'delete') { await AppDb.i.delete('home_goals', g['id'] as int); widget.refresh(); }
                        },
                        itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text(done ? 'Mark active' : 'Mark complete')), const PopupMenuItem(value: 'delete', child: Text('Delete'))],
                      ),
                    ]),
                    if (target > 0) ...[
                      Text('${moneyFromCents(saved)} / ${moneyFromCents(target)}', style: const TextStyle(color: SnyderColors.muted, fontSize: 11)),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(99), color: SnyderColors.blue, backgroundColor: SnyderColors.line),
                    ],
                    if (g['notes']?.toString().isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text(g['notes'].toString(), style: const TextStyle(color: SnyderColors.muted))),
                  ]),
                );
              }),
            ]),
          );
        },
      );

  Future<void> _taskDialog({Map<String, Object?>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final category = TextEditingController(text: existing?['category']?.toString() ?? 'Household');
    final label = TextEditingController(text: existing?['due_label']?.toString() ?? '');
    DateTime? due = existing?['due_date']?.toString().isNotEmpty == true ? parseDate(existing!['due_date']) : null;
    String recurrence = existing?['recurrence']?.toString() ?? 'none';
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text(existing == null ? 'Add task' : 'Edit task'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Task')),
        const SizedBox(height: 8), TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
        const SizedBox(height: 8), TextField(controller: label, decoration: const InputDecoration(labelText: 'Friendly due label (optional)')),
        const SizedBox(height: 8), DropdownButtonFormField<String>(initialValue: recurrence, decoration: const InputDecoration(labelText: 'Recurrence'), items: const [
          DropdownMenuItem(value: 'none', child: Text('One time')), DropdownMenuItem(value: 'daily', child: Text('Daily')), DropdownMenuItem(value: 'weekly', child: Text('Weekly')), DropdownMenuItem(value: 'monthly', child: Text('Monthly')), DropdownMenuItem(value: 'as needed', child: Text('As needed'))
        ], onChanged: (v) => setDialog(() => recurrence = v ?? 'none')),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Due date'), subtitle: Text(due == null ? 'No specific date' : shortDate(due!)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (due != null) IconButton(onPressed: () => setDialog(() => due = null), icon: const Icon(Icons.clear)), const Icon(Icons.calendar_month)]), onTap: () async { final d = await pickDate(context, due ?? DateTime.now()); if (d != null) setDialog(() => due = d); }),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))],
    )));
    if (ok == true && name.text.trim().isNotEmpty) {
      final row = {'name': name.text.trim(), 'category': category.text.trim().isEmpty ? 'Household' : category.text.trim(), 'due_date': due == null ? null : isoDate(due!), 'due_label': label.text.trim(), 'recurrence': recurrence};
      if (existing == null) {
        await AppDb.i.insert('tasks', {...row, 'done': 0, 'completed_at': null, 'created_at': AppDb.i.now()});
      } else {
        await AppDb.i.update('tasks', row, existing['id'] as int);
      }
      widget.refresh();
    }
  }

  Future<void> _memberDialog({Map<String, Object?>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final role = TextEditingController(text: existing?['role']?.toString() ?? '');
    final notes = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(existing == null ? 'Add household member' : 'Edit household member'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), const SizedBox(height: 8), TextField(controller: role, decoration: const InputDecoration(labelText: 'Role / context')), const SizedBox(height: 8), TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes'))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))]));
    if (ok == true && name.text.trim().isNotEmpty) {
      final row = {'name': name.text.trim(), 'role': role.text.trim(), 'notes': notes.text.trim()};
      if (existing == null) await AppDb.i.insert('household_members', {...row, 'created_at': AppDb.i.now()}); else await AppDb.i.update('household_members', row, existing['id'] as int);
      widget.refresh();
    }
  }

  Future<void> _homeGoalDialog({Map<String, Object?>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final target = TextEditingController(text: existing == null ? '' : ((existing['target_cents'] as int) / 100).toStringAsFixed(2));
    final saved = TextEditingController(text: existing == null ? '' : ((existing['saved_cents'] as int) / 100).toStringAsFixed(2));
    final category = TextEditingController(text: existing?['category']?.toString() ?? 'Home');
    final notes = TextEditingController(text: existing?['notes']?.toString() ?? '');
    DateTime? date = existing?['target_date']?.toString().isNotEmpty == true ? parseDate(existing!['target_date']) : null;
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(title: Text(existing == null ? 'Add home goal' : 'Edit home goal'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Goal')), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Target', prefixText: r'$ '))), const SizedBox(width: 8), Expanded(child: TextField(controller: saved, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Saved', prefixText: r'$ ')))]),
      const SizedBox(height: 8), TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 8), TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Target date'), subtitle: Text(date == null ? 'No deadline' : shortDate(date!)), onTap: () async { final x = await pickDate(context, date ?? DateTime.now().add(const Duration(days: 90))); if (x != null) setDialog(() => date = x); }),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))])));
    if (ok == true && name.text.trim().isNotEmpty) {
      final row = {'name': name.text.trim(), 'target_cents': centsFromText(target.text), 'saved_cents': centsFromText(saved.text), 'target_date': date == null ? null : isoDate(date!), 'category': category.text.trim().isEmpty ? 'Home' : category.text.trim(), 'notes': notes.text.trim()};
      if (existing == null) await AppDb.i.insert('home_goals', {...row, 'done': 0, 'created_at': AppDb.i.now()}); else await AppDb.i.update('home_goals', row, existing['id'] as int);
      widget.refresh();
    }
  }
}