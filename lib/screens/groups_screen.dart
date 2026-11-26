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
import 'group_settings_screen.dart';
import 'places_screen.dart';
import '../strings.dart';

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
      appBar: AppBar(title: const Text(Txt.groups)),
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
                const _Note(icon: Icons.groups_rounded, text: Txt.youReNotInA),
              const SizedBox(height: 16),
              Text(Txt.joinAGroup, style: t.titleMedium),
              const SizedBox(height: 8),
              const JoinGroupForm(),
              const SizedBox(height: 24),
              Text(Txt.startAGroup, style: t.titleMedium),
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
                      label: const Text(Txt.leader),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.primary.withOpacity(0.1),
                      side: BorderSide.none,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: Txt.groupOptions,
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
                        child: Text(Txt.renameGroup),
                      ),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text(Txt.leaveGroup),
                    ),
                  ],
                ),
              ],
            ),
            _GroupSetup(group: g),
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
                    ? Txt.n1PersonWantsToJoin
                    : Txt.peopleWantToJoin(g.requests.length),
                style: t.titleSmall?.copyWith(color: FlockColors.warning),
              ),
              for (final r in g.requests) _RequestTile(group: g, request: r),
            ],
            const SizedBox(height: 12),
            Text(
              Txt.memberCount(g.members.length),
              style: t.titleSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            for (final m in g.members) _MemberTile(group: g, member: m),
            GroupPlaces(group: g),
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
      title: Txt.renameGroup,
      label: Txt.groupName,
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
      title: Txt.leave(g.name),
      text: g.isLeader && others
          ? Txt.youLlStopSeeingEveryone
          : g.isLeader
          ? Txt.youReTheOnlyOne
          : Txt.youLlStopSeeingEveryone2,
      action: Txt.leave2,
    );
    if (!ok || !context.mounted) return;
    final err = await app.leaveGroup(g);
    if (!context.mounted) return;
    _report(context, err);
  }
}

/// The group's server and tracking, which members get automatically, and
/// which group the map shows when you're in more than one.
class _GroupSetup extends StatelessWidget {
  const _GroupSetup({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final g = group;
    final c = g.config;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final several = (app.account?.groups.length ?? 0) > 1;
    final active = app.activeGroup?.id == g.id;
    void open() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GroupSettingsScreen(group: g)));

    final Widget info;
    if (c == null) {
      info = Container(
        margin: const EdgeInsets.only(top: 8, right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FlockColors.warning.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: FlockColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                g.isLeader
                    ? Txt.notSetUpYetAdd
                    : Txt.waitingForToSetUp(g.leaderName),
              ),
            ),
            if (g.isLeader)
              TextButton(onPressed: open, child: const Text(Txt.setUp)),
          ],
        ),
      );
    } else {
      final server = c.host.isEmpty ? Txt.unknownServer : c.host;
      info = ListTile(
        contentPadding: const EdgeInsets.only(right: 4),
        leading: Icon(Icons.tune_rounded, color: cs.primary),
        title: Text(Txt.tracking2(c.trackingMode.label)),
        subtitle: Text(
          Txt.server2(server),
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        trailing: g.isLeader
            ? TextButton(onPressed: open, child: const Text(Txt.settings2))
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        info,
        if (several)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: active
                ? Chip(
                    avatar: const Icon(Icons.map_rounded, size: 18),
                    label: const Text(Txt.onYourMapNow),
                    side: BorderSide.none,
                    backgroundColor: cs.primary.withOpacity(0.1),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () => app.setActiveGroup(g),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text(Txt.showThisGroupOnMy),
                  ),
          ),
      ],
    );
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
                  Text(Txt.waitingForToLetYou(pending.leaderName)),
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

  /// The message a leader sends. Paste it whole into Flock's Invite box.
  static String shareText(Group g) =>
      Txt.joinOnFlockInstallFlock(g.name, g.invite ?? g.code);

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
            Txt.inviteCode,
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
                tooltip: Txt.copy,
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: group.invite ?? code),
                  );
                  if (context.mounted) {
                    _report(context, null, ok: Txt.inviteCopied);
                  }
                },
              ),
              IconButton(
                tooltip: Txt.newCode,
                icon: const Icon(Icons.autorenew_rounded),
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    title: Txt.makeANewCode,
                    text: Txt.theOldCodeStopsWorking,
                    action: Txt.newCode,
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
              ShareParams(text: shareText(group), subject: Txt.joinMeOnFlock),
            ),
            icon: const Icon(Icons.share_rounded),
            label: const Text(Txt.shareInvite),
          ),
          const SizedBox(height: 4),
          Text(
            Txt.shareSendsTheFullInvite,
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
                  Txt.newToFlock(
                    r.username,
                    timeAgo(r.accountCreated).toLowerCase(),
                  ),
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
              tooltip: Txt.sayNo,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _do(() => app.deny(widget.group, r)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _do(() => app.approve(widget.group, r)),
              child: const Text(Txt.letIn),
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
      title: Text(me ? Txt.nameYou(m.name) : m.name),
      subtitle: Text(
        m.leader ? Txt.leader : '@${m.username}',
        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: canManage
          ? PopupMenuButton<String>(
              tooltip: Txt.optionsFor(m.name),
              onSelected: (v) async {
                if (v == 'remove') {
                  final ok = await _confirm(
                    context,
                    title: Txt.remove(m.name),
                    text: Txt.theyLlStopSeeingEveryone(group.name),
                    action: Txt.remove2,
                  );
                  if (!ok || !context.mounted) return;
                  final err = await app.removeMember(group, m.username);
                  if (!context.mounted) return;
                  _report(context, err);
                } else if (v == 'leader') {
                  final ok = await _confirm(
                    context,
                    title: Txt.makeTheLeader(m.name),
                    text: Txt.theyLlApproveNewPeople,
                    action: Txt.makeLeader,
                  );
                  if (!ok || !context.mounted) return;
                  final err = await app.makeLeader(group, m.username);
                  if (!context.mounted) return;
                  _report(context, err);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'leader', child: Text(Txt.makeLeader)),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(Txt.removeFromGroup),
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
      label: Txt.groupName,
      hint: Txt.eGTheCrew,
      icon: Icons.group_add_rounded,
      button: Txt.start,
      busy: _busy,
      error: _error,
      capitalization: TextCapitalization.words,
      onSubmit: _go,
      onChanged: () => setState(() => _error = null),
    );
  }
}

/// "Join a group": paste the invite a leader shared; they then let you in.
class JoinGroupForm extends StatefulWidget {
  const JoinGroupForm({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  State<JoinGroupForm> createState() => _JoinGroupFormState();
}

class _JoinGroupFormState extends State<JoinGroupForm> {
  final _invite = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _filled;

  /// Fill in an invite link that opened the app.
  void _takePending(String? link) {
    if (link == null || link == _filled) return;
    _filled = link;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _invite.text = link;
      setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) {
      _invite.text = d!.text!.trim();
      setState(() => _error = null);
    }
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().joinWithInvite(_invite.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      _invite.clear();
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    _takePending(context.select<AppState, String?>((a) => a.pendingInvite));
    return ListenableBuilder(
      listenable: _invite,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _invite,
            autocorrect: false,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: Txt.invite,
              hintText: Txt.pasteTheInviteYouWere,
              prefixIcon: const Icon(Icons.vpn_key_rounded),
              suffixIcon: IconButton(
                tooltip: Txt.paste,
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
              errorText: _error,
              errorMaxLines: 4,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _invite.text.trim().isNotEmpty && !_busy ? _go : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text(Txt.askToJoin),
          ),
        ],
      ),
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
          child: const Text(Txt.cancel),
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
          child: const Text(Txt.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text(Txt.save),
        ),
      ],
    ),
  );
}
