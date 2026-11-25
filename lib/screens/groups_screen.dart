// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/server_config.dart';
import '../models/settings.dart';
import '../services/account_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/avatar.dart';

/// Your groups: who's in them, invite codes, and people asking to join.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().refreshAccount();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final a = app.account;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: RefreshIndicator(
        onRefresh: app.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (app.accountError != null && a == null)
              _Note(icon: Icons.cloud_off_rounded, text: app.accountError!)
            else if (a == null)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (a != null) ...[
              for (final g in a.groups) GroupCard(group: g),
              for (final p in a.pending) PendingCard(pending: p),
              if (a.groups.isEmpty && a.pending.isEmpty)
                const _Note(
                  icon: Icons.groups_rounded,
                  text:
                      'You\'re not in a group yet. Start one and share its '
                      'code, or ask someone for theirs.',
                ),
              const SizedBox(height: 16),
              Text('Join a group', style: t.titleMedium),
              const SizedBox(height: 8),
              const JoinGroupForm(),
              const SizedBox(height: 24),
              Text('Start a group', style: t.titleMedium),
              const SizedBox(height: 8),
              const CreateGroupForm(),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ cards --

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final g = group;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(g.name, style: t.titleLarge)),
                if (g.isLeader)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      label: const Text('Leader'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.primary.withOpacity(0.1),
                      side: BorderSide.none,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Group options',
                  onSelected: (v) async {
                    if (v == 'rename') {
                      await _rename(context, app, g);
                    } else if (v == 'leave') {
                      await _leave(context, app, g);
                    }
                  },
                  itemBuilder: (_) => [
                    if (g.isLeader)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename group'),
                      ),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text('Leave group'),
                    ),
                  ],
                ),
              ],
            ),
            if (g.isLeader && g.code != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InviteCodeCard(group: g),
              ),
            ],
            if (g.isLeader && g.requests.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                g.requests.length == 1
                    ? '1 person wants to join'
                    : '${g.requests.length} people want to join',
                style: t.titleSmall?.copyWith(color: FlockColors.warning),
              ),
              for (final r in g.requests) _RequestTile(group: g, request: r),
            ],
            const SizedBox(height: 12),
            Text(
              '${g.members.length} ${g.members.length == 1 ? 'member' : 'members'}',
              style: t.titleSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            for (final m in g.members) _MemberTile(group: g, member: m),
          ],
        ),
      ),
    );
  }

  static Future<void> _rename(
    BuildContext context,
    AppState app,
    Group g,
  ) async {
    final name = await _askText(
      context,
      title: 'Rename group',
      label: 'Group name',
      initial: g.name,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final err = await app.renameGroup(g, name);
    if (!context.mounted) return;
    _report(context, err);
  }

  static Future<void> _leave(
    BuildContext context,
    AppState app,
    Group g,
  ) async {
    final others = g.members.length > 1;
    final ok = await _confirm(
      context,
      title: 'Leave ${g.name}?',
      text: g.isLeader && others
          ? 'You\'ll stop seeing everyone in it, and they\'ll stop seeing '
                'you. The longest-standing member becomes the leader.'
          : g.isLeader
          ? 'You\'re the only one in it, so the group will be deleted.'
          : 'You\'ll stop seeing everyone in it, and they\'ll stop seeing you.',
      action: 'Leave',
    );
    if (!ok || !context.mounted) return;
    final err = await app.leaveGroup(g);
    if (!context.mounted) return;
    _report(context, err);
  }
}

/// A group you asked to join that the leader hasn't let you into yet.
class PendingCard extends StatelessWidget {
  const PendingCard({super.key, required this.pending});
  final PendingJoin pending;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: FlockColors.warning.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top_rounded, color: FlockColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pending.name, style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Waiting for ${pending.leaderName} to let you in. '
                    'Let them know it\'s you.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The group's invite code, big enough to read out, with Share and Copy.
class InviteCodeCard extends StatelessWidget {
  const InviteCodeCard({super.key, required this.group});
  final Group group;

  static String shareText(Group g) =>
      'Join "${g.name}" on Flock: open Flock, go to Groups → Join a group, '
      'and enter the code ${g.code}';

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final code = group.code ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite code',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    _report(context, null, ok: 'Code copied.');
                  }
                },
              ),
              IconButton(
                tooltip: 'New code',
                icon: const Icon(Icons.autorenew_rounded),
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    title: 'Make a new code?',
                    text:
                        'The old code stops working. People already in the '
                        'group stay in.',
                    action: 'New code',
                  );
                  if (!ok || !context.mounted) return;
                  final err = await app.newInviteCode(group);
                  if (!context.mounted) return;
                  _report(context, err);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: shareText(group), subject: 'Join me on Flock'),
            ),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share code'),
          ),
          const SizedBox(height: 4),
          Text(
            'Anyone with the code can ask to join. You decide who gets in.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  const _RequestTile({required this.group, required this.request});
  final Group group;
  final JoinRequest request;

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _busy = false;

  Future<void> _do(Future<String?> Function() f) async {
    setState(() => _busy = true);
    final err = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    _report(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = widget.request;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 8),
      child: Row(
        children: [
          UserAvatar(username: r.username, name: r.name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name, style: t.titleMedium),
                Text(
                  '@${r.username} · new to Flock ${timeAgo(r.accountCreated).toLowerCase()}',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Say no',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _do(() => app.deny(widget.group, r)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _do(() => app.approve(widget.group, r)),
              child: const Text('Let in'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.group, required this.member});
  final Group group;
  final GroupMember member;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final m = member;
    final me = m.username == app.settings.username;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final canManage = group.isLeader && !me;
    return ListTile(
      contentPadding: const EdgeInsets.only(right: 4),
      leading: UserAvatar(username: m.username, name: m.name, size: 40),
      title: Text(me ? '${m.name} (you)' : m.name),
      subtitle: Text(
        m.leader ? 'Leader' : '@${m.username}',
        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: canManage
          ? PopupMenuButton<String>(
              tooltip: 'Options for ${m.name}',
              onSelected: (v) async {
                if (v == 'remove') {
                  final ok = await _confirm(
                    context,
                    title: 'Remove ${m.name}?',
                    text:
                        'They\'ll stop seeing everyone in ${group.name}, and '
                        'everyone stops seeing them.',
                    action: 'Remove',
                  );
                  if (!ok || !context.mounted) return;
                  final err = await app.removeMember(group, m.username);
                  if (!context.mounted) return;
                  _report(context, err);
                } else if (v == 'leader') {
                  final ok = await _confirm(
                    context,
                    title: 'Make ${m.name} the leader?',
                    text:
                        'They\'ll approve new people and manage the code. '
                        'You stay in the group.',
                    action: 'Make leader',
                  );
                  if (!ok || !context.mounted) return;
                  final err = await app.makeLeader(group, m.username);
                  if (!context.mounted) return;
                  _report(context, err);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'leader', child: Text('Make leader')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from group'),
                ),
              ],
            )
          : null,
    );
  }
}

/// Someone's photo from their card if we have it, else their initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.username,
    required this.name,
    this.size = 40,
  });
  final String username;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final card = app.cardFor(username);
    final isMe = username == app.settings.username;
    final tid = card?.trackerId ?? '';
    return Avatar(
      colorKey: '${app.settings.baseTopic}/$username/$kDeviceName',
      initials: tid.isNotEmpty ? tid : trackerIdFromDisplayName(name),
      face: isMe ? app.myFace : card?.face,
      size: size,
      label: name,
      enlargeable: true,
    );
  }
}

// ------------------------------------------------------------------ forms --

/// "Start a group": name it, become its leader, get a code.
class CreateGroupForm extends StatefulWidget {
  const CreateGroupForm({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  State<CreateGroupForm> createState() => _CreateGroupFormState();
}

class _CreateGroupFormState extends State<CreateGroupForm> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().createGroup(_name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      _name.clear();
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InlineForm(
      controller: _name,
      label: 'Group name',
      hint: 'e.g. Class of 2024',
      icon: Icons.group_add_rounded,
      button: 'Start',
      busy: _busy,
      error: _error,
      capitalization: TextCapitalization.words,
      onSubmit: _go,
      onChanged: () => setState(() => _error = null),
    );
  }
}

/// "Join a group": enter the code a leader shared; they then let you in.
class JoinGroupForm extends StatefulWidget {
  const JoinGroupForm({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  State<JoinGroupForm> createState() => _JoinGroupFormState();
}

class _JoinGroupFormState extends State<JoinGroupForm> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().joinGroup(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      _code.clear();
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InlineForm(
      controller: _code,
      label: 'Invite code',
      hint: 'e.g. K7Q-2MX',
      icon: Icons.vpn_key_rounded,
      button: 'Ask to join',
      busy: _busy,
      error: _error,
      capitalization: TextCapitalization.characters,
      onSubmit: _go,
      onChanged: () => setState(() => _error = null),
    );
  }
}

class _InlineForm extends StatelessWidget {
  const _InlineForm({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.button,
    required this.busy,
    required this.error,
    required this.capitalization,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String button;
  final bool busy;
  final String? error;
  final TextCapitalization capitalization;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ready = controller.text.trim().isNotEmpty && !busy;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: capitalization,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  prefixIcon: Icon(icon),
                  errorText: error,
                  errorMaxLines: 3,
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => ready ? onSubmit() : null,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton(
                onPressed: ready ? onSubmit : null,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(button),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- helpers --

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

void _report(BuildContext context, String? error, {String? ok}) {
  final text = error ?? ok;
  if (text == null) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
