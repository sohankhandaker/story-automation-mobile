import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  final _githubCtrl = TextEditingController();
  final _reviewerNameCtrl = TextEditingController();
  final _reviewerUserCtrl = TextEditingController();
  final _reviewerEmailCtrl = TextEditingController();
  final _ghTokenCtrl = TextEditingController();
  final _ghOwnerCtrl = TextEditingController();
  final _ghRepoCtrl = TextEditingController();
  final _ghProjectNumberCtrl = TextEditingController();
  bool _saving = false;
  bool _ghTokenVisible = false;

  @override
  void initState() {
    super.initState();
    _populateFromUser(ref.read(authProvider).user);
  }

  void _populateFromUser(User? user) {
    _githubCtrl.text = user?.githubUsername ?? '';
    _ghTokenCtrl.text = user?.ghToken ?? '';
    _ghOwnerCtrl.text = user?.ghOwner ?? '';
    _ghRepoCtrl.text = user?.ghRepo ?? '';
    _ghProjectNumberCtrl.text = user?.ghProjectNumber?.toString() ?? '';
  }

  @override
  void dispose() {
    _githubCtrl.dispose();
    _reviewerNameCtrl.dispose();
    _reviewerUserCtrl.dispose();
    _reviewerEmailCtrl.dispose();
    _ghTokenCtrl.dispose();
    _ghOwnerCtrl.dispose();
    _ghRepoCtrl.dispose();
    _ghProjectNumberCtrl.dispose();
    super.dispose();
  }

  List<ReviewerItem> get _reviewers =>
      ref.read(authProvider).user?.reviewerList ?? [];

  Future<void> _save() async {
    setState(() => _saving = true);
    final projectNumber = int.tryParse(_ghProjectNumberCtrl.text.trim());
    String? tok = _ghTokenCtrl.text.trim().isEmpty ? null : _ghTokenCtrl.text.trim();
    String? own = _ghOwnerCtrl.text.trim().isEmpty ? null : _ghOwnerCtrl.text.trim();
    String? rep = _ghRepoCtrl.text.trim().isEmpty ? null : _ghRepoCtrl.text.trim();
    await ref.read(authProvider.notifier).updateSettings(
          _githubCtrl.text.trim().isEmpty ? null : _githubCtrl.text.trim(),
          _reviewers.map((r) => r.toJson()).toList(),
          ghToken: tok,
          ghOwner: own,
          ghRepo: rep,
          ghProjectNumber: projectNumber,
        );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  void _addReviewer() {
    final name = _reviewerNameCtrl.text.trim();
    final username = _reviewerUserCtrl.text.trim();
    final email = _reviewerEmailCtrl.text.trim();
    if (name.isEmpty || username.isEmpty) return;

    final current = List<ReviewerItem>.from(_reviewers);
    current.add(ReviewerItem(
      name: name,
      githubUsername: username,
      email: email.isEmpty ? null : email,
    ));
    ref.read(authProvider.notifier).updateSettings(
          _githubCtrl.text.trim().isEmpty ? null : _githubCtrl.text.trim(),
          current.map((r) => r.toJson()).toList(),
          ghToken: _ghTokenCtrl.text.trim().isEmpty ? null : _ghTokenCtrl.text.trim(),
          ghOwner: _ghOwnerCtrl.text.trim().isEmpty ? null : _ghOwnerCtrl.text.trim(),
          ghRepo: _ghRepoCtrl.text.trim().isEmpty ? null : _ghRepoCtrl.text.trim(),
          ghProjectNumber: int.tryParse(_ghProjectNumberCtrl.text.trim()),
        );
    _reviewerNameCtrl.clear();
    _reviewerUserCtrl.clear();
    _reviewerEmailCtrl.clear();
    setState(() {});
  }

  void _removeReviewer(int index) {
    final current = List<ReviewerItem>.from(_reviewers);
    current.removeAt(index);
    ref.read(authProvider.notifier).updateSettings(
          _githubCtrl.text.trim().isEmpty ? null : _githubCtrl.text.trim(),
          current.map((r) => r.toJson()).toList(),
          ghToken: _ghTokenCtrl.text.trim().isEmpty ? null : _ghTokenCtrl.text.trim(),
          ghOwner: _ghOwnerCtrl.text.trim().isEmpty ? null : _ghOwnerCtrl.text.trim(),
          ghRepo: _ghRepoCtrl.text.trim().isEmpty ? null : _ghRepoCtrl.text.trim(),
          ghProjectNumber: int.tryParse(_ghProjectNumberCtrl.text.trim()),
        );
    setState(() {});
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red, size: 22),
            Gap(10),
            Text('Sign Out', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const Gap(10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authProvider.notifier).logout();
    // _AppRoot in app.dart observes auth state and routes to LoginScreen
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final cs = Theme.of(context).colorScheme;

    // Re-sync controllers whenever the logged-in user changes (e.g. after re-login)
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (prev?.user?.id != next.user?.id) {
        _populateFromUser(next.user);
      }
    });

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // ── Profile ───────────────────────────────────────────────
        _SectionCard(
          title: 'Profile',
          icon: Icons.person_rounded,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (user?.avatarUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      user!.avatarUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _AvatarInitials(user),
                    ),
                  )
                else
                  _AvatarInitials(user),
                const Gap(16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const Gap(5),
                      _InfoRow(
                          icon: Icons.email_outlined, label: user?.email ?? ''),
                      if (user?.githubUsername != null) ...[
                        const Gap(3),
                        _InfoRow(
                            icon: Icons.alternate_email_rounded,
                            label: user!.githubUsername!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Gap(14),

        // ── GitHub ────────────────────────────────────────────────
        _SectionCard(
          title: 'GitHub',
          icon: Icons.code_rounded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Link your GitHub account so the system can attribute your activity on issues and pull requests.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4),
                ),
                const Gap(16),
                TextField(
                  controller: _githubCtrl,
                  decoration: InputDecoration(
                    labelText: 'GitHub Username',
                    hintText: 'e.g. your-github-handle',
                    prefixIcon:
                        const Icon(Icons.alternate_email_rounded, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF7FAFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFFD8E8FF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFFD8E8FF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Gap(14),

        // ── GitHub Project ────────────────────────────────────────
        _SectionCard(
          title: 'GitHub Project',
          icon: Icons.dashboard_customize_rounded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect your own GitHub project board. Leave empty to use the default workspace project.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
                ),
                const Gap(16),
                TextField(
                  controller: _ghTokenCtrl,
                  obscureText: !_ghTokenVisible,
                  enableInteractiveSelection: true,
                  decoration: InputDecoration(
                    labelText: 'GitHub Token (PAT)',
                    hintText: 'ghp_...',
                    prefixIcon: const Icon(Icons.key_rounded, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _ghTokenVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                          ),
                          tooltip: _ghTokenVisible ? 'Hide' : 'Show',
                          onPressed: () => setState(() => _ghTokenVisible = !_ghTokenVisible),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste_rounded, size: 20),
                          tooltip: 'Paste from clipboard',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              _ghTokenCtrl.text = data!.text!.trim();
                            }
                          },
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF7FAFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD8E8FF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD8E8FF)),
                    ),
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: _FormField(
                        controller: _ghOwnerCtrl,
                        label: 'Owner / Org',
                        icon: Icons.business_rounded,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _FormField(
                        controller: _ghRepoCtrl,
                        label: 'Repository',
                        icon: Icons.folder_rounded,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                _FormField(
                  controller: _ghProjectNumberCtrl,
                  label: 'Project Number',
                  icon: Icons.tag_rounded,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        const Gap(14),

        // ── Reviewers ─────────────────────────────────────────────
        _SectionCard(
          title: 'Reviewers',
          icon: Icons.group_rounded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Empty state
                if (_reviewers.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFF),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: const Color(0xFFD8E8FF)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.group_add_rounded,
                            size: 32,
                            color: kPrimary.withValues(alpha: 0.35)),
                        const Gap(8),
                        Text(
                          'No reviewers added yet',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                // Reviewer cards
                if (_reviewers.isNotEmpty)
                  ...List.generate(_reviewers.length, (i) {
                    final r = _reviewers[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReviewerCard(
                        reviewer: r,
                        onRemove: () => _removeReviewer(i),
                      ),
                    );
                  }),

                const Gap(16),
                // Divider with label
                Row(
                  children: [
                    Expanded(
                        child: Divider(color: cs.outlineVariant)),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'ADD REVIEWER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    Expanded(
                        child: Divider(color: cs.outlineVariant)),
                  ],
                ),
                const Gap(14),

                // Add form
                Row(
                  children: [
                    Expanded(
                      child: _FormField(
                        controller: _reviewerNameCtrl,
                        label: 'Full Name',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _FormField(
                        controller: _reviewerUserCtrl,
                        label: 'GitHub Username',
                        icon: Icons.alternate_email_rounded,
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: _FormField(
                        controller: _reviewerEmailCtrl,
                        label: 'Email (optional)',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    const Gap(10),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _addReviewer,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.person_add_rounded,
                            size: 18),
                        label: const Text('Add'),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                Text(
                  'Email enables direct review notifications.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const Gap(28),

        // ── Save ──────────────────────────────────────────────────
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Save Settings',
                style: TextStyle(fontSize: 15)),
          ),
        ),
        const Gap(12),

        // ── Sign out ──────────────────────────────────────────────
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.red, size: 18),
            label: const Text('Sign Out',
                style: TextStyle(color: Colors.red, fontSize: 15)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: kPrimaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: kPrimary),
                ),
                const Gap(10),
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          child,
        ],
      ),
    );
  }
}

class _AvatarInitials extends StatelessWidget {
  final User? user;
  const _AvatarInitials(this.user);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimary, kPrimaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        user?.name.substring(0, 1).toUpperCase() ?? '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const Gap(5),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ReviewerCard extends StatelessWidget {
  final ReviewerItem reviewer;
  final VoidCallback onRemove;
  const _ReviewerCard({required this.reviewer, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final initial = reviewer.name.substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0E4FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kPrimary, kPrimaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reviewer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const Gap(3),
                  _InfoRow(
                      icon: Icons.alternate_email_rounded,
                      label: reviewer.githubUsername),
                  if (reviewer.email != null) ...[
                    const Gap(2),
                    _InfoRow(
                        icon: Icons.email_outlined, label: reviewer.email!),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.remove_circle_outline_rounded,
                  color: Colors.red.shade300, size: 22),
              onPressed: onRemove,
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        filled: true,
        fillColor: const Color(0xFFF7FAFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD8E8FF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD8E8FF)),
        ),
      ),
    );
  }
}
