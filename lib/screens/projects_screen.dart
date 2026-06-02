import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../theme/sera_tokens.dart';
import 'notes_screen.dart' show MeetingNote, NoteCard;
import 'customers_screen.dart' show Customer, customersProvider, CustomerFormSheet;

// ── Model ─────────────────────────────────────────────────────────────────────

class Project {
  final String id;
  final String title;
  final String clientName;
  final String? url;
  final String? shortDescription;
  final String? customerId;
  final Customer? customer;
  final String? githubIssueUrl;
  final int? githubIssueNumber;
  final String status;
  final int notesCount;
  final DateTime createdAt;

  Project.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        clientName = j['client_name'] as String,
        url = j['url'] as String?,
        shortDescription = j['short_description'] as String?,
        customerId = j['customer_id'] as String?,
        customer = j['customer'] != null
            ? Customer.fromJson(j['customer'] as Map<String, dynamic>)
            : null,
        githubIssueUrl = j['github_issue_url'] as String?,
        githubIssueNumber = j['github_issue_number'] as int?,
        status = (j['status'] as String?) ?? 'Active',
        notesCount = (j['notes_count'] as int?) ?? 0,
        createdAt = DateTime.parse(j['created_at'] as String);
}

// ── Provider ──────────────────────────────────────────────────────────────────

class ProjectsNotifier extends StateNotifier<AsyncValue<List<Project>>> {
  ProjectsNotifier() : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final resp = await ApiClient.dio.get('/api/projects');
      final list = (resp.data['projects'] as List)
          .map((j) => Project.fromJson(j as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } on DioException catch (e, s) {
      // 401 is handled by the auth interceptor (redirects to login) — don't surface it here
      if (e.response?.statusCode == 401) return;
      state = AsyncValue.error(e, s);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<bool> delete(String projectId) async {
    try {
      await ApiClient.dio.delete('/api/projects/$projectId');
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Project?> create({
    required String title,
    required String clientName,
    String? customerId,
    String? url,
    String? shortDescription,
  }) async {
    try {
      final resp = await ApiClient.dio.post('/api/projects', data: {
        'title': title,
        'client_name': clientName,
        if (customerId != null) 'customer_id': customerId,
        if (url != null && url.isNotEmpty) 'url': url,
        if (shortDescription != null && shortDescription.isNotEmpty)
          'short_description': shortDescription,
      });
      final project = Project.fromJson(resp.data as Map<String, dynamic>);
      await fetch();
      return project;
    } catch (_) {
      return null;
    }
  }
}

final projectsProvider =
    StateNotifierProvider<ProjectsNotifier, AsyncValue<List<Project>>>(
        (_) => ProjectsNotifier());

// Provider for notes scoped to a specific project
final projectNotesProvider = StateNotifierProvider.family<
    _ProjectNotesNotifier, AsyncValue<List<MeetingNote>>, String>(
  (_, projectId) => _ProjectNotesNotifier(projectId),
);

class _ProjectNotesNotifier
    extends StateNotifier<AsyncValue<List<MeetingNote>>> {
  final String projectId;
  _ProjectNotesNotifier(this.projectId) : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final resp =
          await ApiClient.dio.get('/api/projects/$projectId/notes');
      final list = (resp.data['notes'] as List)
          .map((j) => MeetingNote.fromJson(j as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 401) return;
      state = AsyncValue.error(e, s);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<MeetingNote?> createNote(String rawNotes, String? wikiUrl) async {
    try {
      final resp =
          await ApiClient.dio.post('/api/projects/$projectId/notes', data: {
        'raw_notes': rawNotes,
        if (wikiUrl != null && wikiUrl.isNotEmpty) 'wiki_url': wikiUrl,
      });
      final note = MeetingNote.fromJson(resp.data as Map<String, dynamic>);
      await fetch();
      return note;
    } catch (_) {
      return null;
    }
  }
}

// ── Projects tab ──────────────────────────────────────────────────────────────

class ProjectsTab extends ConsumerWidget {
  const ProjectsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);

    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const Gap(12),
            Text('$e',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
            const Gap(12),
            FilledButton(
              onPressed: () => ref.read(projectsProvider.notifier).fetch(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (projects) => RefreshIndicator(
        onRefresh: () => ref.read(projectsProvider.notifier).fetch(),
        child: projects.isEmpty
            ? const _ProjectsEmptyState()
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: projects.length,
                separatorBuilder: (_, __) => const Gap(12),
                itemBuilder: (_, i) => _ProjectCard(project: projects[i]),
              ),
      ),
    );
  }
}

// ── Project card ──────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final Project project;
  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(SeraTokens.r2xl),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(project: project),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(SeraTokens.r2xl),
          border: Border.all(color: SeraTokens.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header gradient strip
            Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SeraTokens.primary, Color(0xFF0A3468)],
                ),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: SeraTokens.primaryLight,
                          borderRadius: BorderRadius.circular(SeraTokens.rMd),
                        ),
                        child: const Icon(Icons.folder_rounded,
                            color: SeraTokens.primary, size: 22),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              project.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: SeraTokens.fg1,
                                height: 1.25,
                              ),
                            ),
                            const Gap(4),
                            Row(
                              children: [
                                const Icon(Icons.business_rounded,
                                    size: 13, color: SeraTokens.fg3),
                                const Gap(5),
                                Expanded(
                                  child: Text(
                                    project.clientName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: SeraTokens.fg3,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: SeraTokens.disabled, size: 20),
                    ],
                  ),
                  if (project.shortDescription != null &&
                      project.shortDescription!.isNotEmpty) ...[
                    const Gap(10),
                    Text(
                      project.shortDescription!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SeraTokens.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const Gap(12),
                  Row(
                    children: [
                      _MetaChip(
                        icon: Icons.description_outlined,
                        label: '${project.notesCount} note${project.notesCount == 1 ? '' : 's'}',
                        color: SeraTokens.primary,
                      ),
                      if (project.githubIssueUrl != null) ...[
                        const Gap(8),
                        _MetaChip(
                          icon: Icons.link_rounded,
                          label: '#${project.githubIssueNumber}',
                          color: const Color(0xFF24292F),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        _formatDate(project.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: SeraTokens.hint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const Gap(4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ── New project sheet ─────────────────────────────────────────────────────────

class NewProjectSheet extends ConsumerStatefulWidget {
  final Customer? preselectedCustomer;
  const NewProjectSheet({super.key, this.preselectedCustomer});

  @override
  ConsumerState<NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends ConsumerState<NewProjectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Customer? _selectedCustomer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.preselectedCustomer;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final project = await ref.read(projectsProvider.notifier).create(
          title: _titleCtrl.text.trim(),
          clientName: _selectedCustomer?.name ?? '',
          customerId: _selectedCustomer?.id,
          url: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          shortDescription:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );

    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.pop(context);

    if (project != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project "${project.title}" created')),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create project')),
      );
    }
  }

  void _pickCustomer() async {
    final customers = ref.read(customersProvider).valueOrNull ?? [];
    final picked = await showModalBottomSheet<Customer?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerPickerSheet(
        customers: customers,
        selected: _selectedCustomer,
        onRefresh: () => ref.read(customersProvider.notifier).fetch(),
      ),
    );
    if (picked != null) setState(() => _selectedCustomer = picked);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: SeraTokens.primaryLight,
                        borderRadius: BorderRadius.circular(SeraTokens.rMd),
                      ),
                      child: const Icon(Icons.folder_open_rounded, color: SeraTokens.primary, size: 20),
                    ),
                    const Gap(12),
                    const Text('New Project',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: SeraTokens.fg1)),
                  ],
                ),
                const Gap(20),

                // Customer selector — hidden when opened from CustomerDetailScreen
                if (widget.preselectedCustomer == null) ...[
                  GestureDetector(
                    onTap: _pickCustomer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: SeraTokens.surface,
                        borderRadius: BorderRadius.circular(SeraTokens.rLg),
                        border: Border.all(
                          color: _selectedCustomer != null
                              ? SeraTokens.primary.withValues(alpha: 0.6)
                              : SeraTokens.borderStrong,
                          width: _selectedCustomer != null ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.business_rounded, size: 20,
                              color: _selectedCustomer != null ? SeraTokens.primary : SeraTokens.fg3),
                          const Gap(12),
                          Expanded(
                            child: _selectedCustomer == null
                                ? const Text('Select Customer *',
                                    style: TextStyle(fontSize: 14, color: SeraTokens.fg3))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_selectedCustomer!.name,
                                          style: const TextStyle(
                                              fontSize: 14, fontWeight: FontWeight.w600,
                                              color: SeraTokens.fg1)),
                                      if (_selectedCustomer!.url != null)
                                        Text(_selectedCustomer!.url!,
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11.5, color: SeraTokens.primary)),
                                    ],
                                  ),
                          ),
                          Icon(Icons.expand_more_rounded, size: 20,
                              color: _selectedCustomer != null ? SeraTokens.primary : SeraTokens.hint),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedCustomer == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text('A customer is required',
                          style: TextStyle(fontSize: 11, color: SeraTokens.fg3)),
                    ),
                  const Gap(14),
                ],

                // Project title
                TextFormField(
                  controller: _titleCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Project Title',
                    prefixIcon: Icon(Icons.title_rounded, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const Gap(14),
                // Project URL
                TextFormField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Project URL (optional)',
                    hintText: 'https://',
                    prefixIcon: Icon(Icons.link_rounded, size: 20),
                  ),
                ),
                const Gap(14),
                // Description
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Short Description (optional)',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 44),
                      child: Icon(Icons.notes_rounded, size: 20),
                    ),
                  ),
                ),
                const Gap(22),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: (_loading || (widget.preselectedCustomer == null && _selectedCustomer == null)) ? null : _submit,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Create Project'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Project detail screen ─────────────────────────────────────────────────────

class ProjectDetailScreen extends ConsumerWidget {
  final Project project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(projectNotesProvider(project.id));

    return Scaffold(
      backgroundColor: SeraTokens.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(project.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            Text(
              project.clientName,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: SeraTokens.fg3,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (project.githubIssueUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View on GitHub',
              onPressed: () =>
                  launchUrl(Uri.parse(project.githubIssueUrl!)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(projectNotesProvider(project.id).notifier).fetch(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _confirmDelete(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Colors.red, size: 20),
                  title: Text('Delete Project',
                      style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddNoteSheet(context, ref),
        backgroundColor: SeraTokens.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Notes',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _ProjectInfoCard(project: project)),
          const SliverToBoxAdapter(child: Gap(4)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.description_rounded,
                      size: 15, color: SeraTokens.fg3),
                  const Gap(7),
                  const Text(
                    'Meeting Notes & BRDs',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: SeraTokens.fg1,
                    ),
                  ),
                  const Spacer(),
                  notesAsync.when(
                    data: (notes) => Text('${notes.length}',
                        style: const TextStyle(
                            fontSize: 12, color: SeraTokens.muted)),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          notesAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 40, color: Colors.red),
                    const Gap(12),
                    Text('$e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                    const Gap(12),
                    FilledButton(
                      onPressed: () => ref
                          .read(projectNotesProvider(project.id).notifier)
                          .fetch(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (notes) => notes.isEmpty
                ? const SliverFillRemaining(
                    child: _NotesEmptyState(),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const Gap(10),
                      itemBuilder: (_, i) => NoteCard(note: notes[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddNoteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProjectNoteSheet(projectId: project.id, ref: ref),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
            'Delete "${project.title}"? This will also delete all notes under this project.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context); // close dialog
              final ok = await ref
                  .read(projectsProvider.notifier)
                  .delete(project.id);
              if (ok && context.mounted) {
                Navigator.pop(context); // go back to customer detail
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Project deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Project info card ─────────────────────────────────────────────────────────

class _ProjectInfoCard extends StatelessWidget {
  final Project project;
  const _ProjectInfoCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF04111F), Color(0xFF0A3468)],
        ),
        borderRadius: BorderRadius.circular(SeraTokens.r2xl),
        boxShadow: [
          BoxShadow(
            color: SeraTokens.primary.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SeraTokens.rMd),
                ),
                child: const Icon(Icons.folder_rounded,
                    color: Colors.white, size: 18),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const Gap(3),
                    Row(
                      children: [
                        const Icon(Icons.business_rounded,
                            size: 12,
                            color: Color(0xB3FFFFFF)),
                        const Gap(4),
                        Text(
                          project.clientName,
                          style: const TextStyle(
                            color: Color(0xB3FFFFFF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (project.shortDescription != null &&
              project.shortDescription!.isNotEmpty) ...[
            const Gap(12),
            Text(
              project.shortDescription!,
              style: const TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
          if (project.url != null && project.url!.isNotEmpty) ...[
            const Gap(12),
            InkWell(
              onTap: () => launchUrl(Uri.parse(project.url!)),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      size: 14, color: Color(0xFF60A5FA)),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      project.url!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF60A5FA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (project.githubIssueUrl != null) ...[
            const Gap(12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(SeraTokens.rSm),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bug_report_outlined,
                      size: 13, color: Colors.white70),
                  const Gap(6),
                  Text(
                    'GitHub Issue #${project.githubIssueNumber}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Add note sheet for project ────────────────────────────────────────────────

class _ProjectNoteSheet extends StatefulWidget {
  final String projectId;
  final WidgetRef ref;
  const _ProjectNoteSheet({required this.projectId, required this.ref});

  @override
  State<_ProjectNoteSheet> createState() => _ProjectNoteSheetState();
}

class _ProjectNoteSheetState extends State<_ProjectNoteSheet> {
  final _notesCtrl = TextEditingController();
  final _wikiCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _wikiCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _notesCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _loading = true);

    final note = await widget.ref
        .read(projectNotesProvider(widget.projectId).notifier)
        .createNote(raw, _wikiCtrl.text.trim().isEmpty ? null : _wikiCtrl.text.trim());

    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.pop(context);

    if (note != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note added to project')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add note')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Gap(18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: SeraTokens.primaryLight,
                    borderRadius: BorderRadius.circular(SeraTokens.rMd),
                  ),
                  child: const Icon(Icons.note_add_rounded,
                      color: SeraTokens.primary, size: 20),
                ),
                const Gap(12),
                const Text(
                  'Add Meeting Notes',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: SeraTokens.fg1,
                  ),
                ),
              ],
            ),
            const Gap(20),
            Stack(children: [
              TextFormField(
                controller: _notesCtrl,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Meeting Notes',
                  hintText:
                      'Paste or type your meeting notes, requirements, decisions…',
                  alignLabelWithHint: true,
                  contentPadding: EdgeInsets.fromLTRB(14, 14, 50, 14),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  onPressed: () async {
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _notesCtrl.text = data!.text!.trim();
                      _notesCtrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _notesCtrl.text.length));
                    }
                  },
                ),
              ),
            ]),
            const Gap(14),
            TextFormField(
              controller: _wikiCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Wiki / Reference URL (optional)',
                hintText: 'https://',
                prefixIcon: Icon(Icons.link_rounded, size: 20),
              ),
            ),
            const Gap(22),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Save Notes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty states ──────────────────────────────────────────────────────────────

class _ProjectsEmptyState extends StatelessWidget {
  const _ProjectsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SeraTokens.primaryLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.folder_open_rounded,
                  size: 40, color: SeraTokens.primary),
            ),
            const Gap(20),
            const Text(
              'No projects yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: SeraTokens.fg1,
              ),
            ),
            const Gap(8),
            const Text(
              'Tap + New Project to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SeraTokens.fg3,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesEmptyState extends StatelessWidget {
  const _NotesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: SeraTokens.primaryLight, borderRadius: BorderRadius.circular(SeraTokens.rPill)),
              child: const Icon(Icons.note_alt_outlined, size: 36, color: SeraTokens.primary),
            ),
            const Gap(18),
            const Text('No notes yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: SeraTokens.fg1)),
            const Gap(8),
            const Text('Tap + Add Notes to start generating\na BRD for this project.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SeraTokens.fg3, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Customer picker sheet ─────────────────────────────────────────────────────

class _CustomerPickerSheet extends StatelessWidget {
  final List<Customer> customers;
  final Customer? selected;
  final VoidCallback onRefresh;

  const _CustomerPickerSheet({
    required this.customers,
    required this.selected,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Gap(12),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Gap(16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('Select Customer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SeraTokens.fg1)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const CustomerFormSheet(),
                    ).then((_) => onRefresh());
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (customers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(Icons.business_rounded, size: 40, color: SeraTokens.disabled),
                  const Gap(12),
                  const Text('No customers yet.\nCreate one first.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SeraTokens.muted, fontSize: 13)),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: customers.length,
                itemBuilder: (_, i) {
                  final c = customers[i];
                  final isSelected = selected?.id == c.id;
                  return ListTile(
                    leading: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: isSelected ? SeraTokens.primaryLight : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(SeraTokens.rMd),
                      ),
                      child: Icon(Icons.business_rounded,
                          size: 18,
                          color: SeraTokens.primary),
                    ),
                    title: Text(c.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isSelected ? SeraTokens.primary : SeraTokens.fg1,
                        )),
                    subtitle: c.url != null
                        ? Text(c.url!, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5))
                        : null,
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: SeraTokens.primary, size: 20)
                        : null,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          const Gap(12),
        ],
      ),
    );
  }
}
