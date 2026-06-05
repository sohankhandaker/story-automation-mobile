import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../theme/sera_tokens.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'notes_screen.dart' show MeetingNote, NoteCard;
import 'customers_screen.dart' show Customer, customersProvider, CustomerFormSheet;
import 'shared_widgets.dart' show WikiUrlInput;
import 'cr_detail_screen.dart' show CrDetailScreen;

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
  final bool hasSentPrd;
  final int notesCount;
  final int changeRequestCount;
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
        hasSentPrd = (j['has_sent_prd'] as bool?) ?? false,
        notesCount = (j['notes_count'] as int?) ?? 0,
        changeRequestCount = (j['change_request_count'] as int?) ?? 0,
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

  Future<void> delete(String projectId) async {
    try {
      await ApiClient.dio.delete('/api/projects/$projectId');
      await fetch();
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      throw Exception(detail ?? 'Failed to delete project');
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

  Future<MeetingNote?> createNote(String rawNotes, String? wikiUrl, {String noteType = 'note'}) async {
    try {
      final resp =
          await ApiClient.dio.post('/api/projects/$projectId/notes', data: {
        'raw_notes': rawNotes,
        if (wikiUrl != null && wikiUrl.isNotEmpty) 'wiki_url': wikiUrl,
        'note_type': noteType,
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

class ProjectsTab extends ConsumerStatefulWidget {
  const ProjectsTab({super.key});

  @override
  ConsumerState<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<ProjectsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Project> _filter(List<Project> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((p) {
      return p.title.toLowerCase().contains(q) ||
          p.clientName.toLowerCase().contains(q) ||
          (p.shortDescription ?? '').toLowerCase().contains(q) ||
          p.status.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
      data: (projects) {
        final filtered = _filter(projects);
        return RefreshIndicator(
          onRefresh: () => ref.read(projectsProvider.notifier).fetch(),
          child: projects.isEmpty
              ? const _ProjectsEmptyState()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: _SearchField(
                        controller: _searchCtrl,
                        hint: 'Search projects',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const _NoResults(
                              label: 'No projects match your search')
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Gap(12),
                              itemBuilder: (_, i) =>
                                  _ProjectCard(project: filtered[i]),
                            ),
                    ),
                  ],
                ),
        );
      },
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
      // Refresh customers so projects_count badge stays accurate
      ref.read(customersProvider.notifier).fetch();
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

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final Project project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  Project get project => widget.project;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MeetingNote> _filterNotes(List<MeetingNote> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((n) {
      return (n.title ?? '').toLowerCase().contains(q) ||
          n.rawNotes.toLowerCase().contains(q) ||
          n.status.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
        onPressed: () => _showAddNoteSheet(context, ref, isChangeRequest: project.hasSentPrd),
        backgroundColor: project.hasSentPrd ? SeraTokens.statusInProgressWarm : SeraTokens.primary,
        foregroundColor: Colors.white,
        icon: Icon(project.hasSentPrd ? Icons.change_circle_outlined : Icons.add_rounded),
        label: Text(
          project.hasSentPrd ? 'Change Request' : 'Add Notes',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const Gap(12),
              Text('$e', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13)),
              const Gap(12),
              FilledButton(
                onPressed: () => ref.read(projectNotesProvider(project.id).notifier).fetch(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (notes) {
          final regularNotes = notes.where((n) => n.noteType != 'change_request').toList();
          // All CRs newest first
          final crNotes = notes
              .where((n) => n.noteType == 'change_request')
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final approvedPrd = regularNotes.where(
            (n) => n.prdStatus == 'Sent to Planner').toList();
          final filteredRegular = _filterNotes(regularNotes);
          final filteredCr = _filterNotes(crNotes);
          final showSearch = (regularNotes.length + crNotes.length) > 0;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _ProjectInfoCard(project: project)),
              const SliverToBoxAdapter(child: Gap(4)),

              if (showSearch)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: _SearchField(
                      controller: _searchCtrl,
                      hint: 'Search notes & change requests',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),

              // ── Meeting Notes & BRDs ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(children: [
                    const Icon(Icons.description_rounded, size: 15, color: SeraTokens.fg3),
                    const Gap(7),
                    const Text('Meeting Notes & BRDs',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 13, color: SeraTokens.fg1)),
                    const Spacer(),
                    Text('${filteredRegular.length}',
                        style: const TextStyle(fontSize: 12, color: SeraTokens.muted)),
                  ]),
                ),
              ),
              if (regularNotes.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _NotesEmptyState(),
                  ),
                )
              else if (filteredRegular.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _NoResults(label: 'No notes match your search'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.separated(
                    itemCount: filteredRegular.length,
                    separatorBuilder: (_, __) => const Gap(10),
                    itemBuilder: (_, i) => NoteCard(note: filteredRegular[i]),
                  ),
                ),

              // ── PRD Management (only when hasSentPrd) ─────────────
              if (project.hasSentPrd) ...[
                const SliverToBoxAdapter(child: Gap(8)),
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: SeraTokens.statusApproved.withValues(alpha: 0.07),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      border: Border.all(color: SeraTokens.statusApproved.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.verified_rounded, size: 15, color: SeraTokens.statusApproved),
                      const Gap(7),
                      const Text('PRD Management',
                          style: TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 13, color: SeraTokens.statusApproved)),
                    ]),
                  ),
                ),

                // Approved PRD cards
                if (approvedPrd.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _ApprovedPrdCard(note: approvedPrd[i]),
                        childCount: approvedPrd.length,
                      ),
                    ),
                  ),

                // Change Requests header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(children: [
                      const Icon(Icons.change_circle_outlined,
                          size: 15, color: SeraTokens.statusInProgressWarm),
                      const Gap(7),
                      const Text('Change Requests',
                          style: TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 13, color: SeraTokens.fg1)),
                      const Spacer(),
                      Text('${filteredCr.length}',
                          style: const TextStyle(fontSize: 12, color: SeraTokens.muted)),
                    ]),
                  ),
                ),

                if (crNotes.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text('No change requests yet. Tap "Change Request" to create one.',
                          style: TextStyle(fontSize: 13, color: SeraTokens.muted)),
                    ),
                  )
                else if (filteredCr.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _NoResults(label: 'No change requests match your search'),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList.separated(
                      itemCount: filteredCr.length,
                      separatorBuilder: (_, __) => const Gap(10),
                      itemBuilder: (_, i) => _CrCard(note: filteredCr[i], projectId: project.id),
                    ),
                  ),
              ] else
                const SliverToBoxAdapter(
                    child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  void _showAddNoteSheet(BuildContext context, WidgetRef ref, {bool isChangeRequest = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProjectNoteSheet(projectId: project.id, isChangeRequest: isChangeRequest),
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
              try {
                await ref.read(projectsProvider.notifier).delete(project.id);
                if (context.mounted) {
                  Navigator.pop(context); // go back to customer detail
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Project deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceFirst('Exception: ', '')),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
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

// ── Attachment helper ─────────────────────────────────────────────────────────

class _ProjAttachedFile {
  final String name;
  final Uint8List bytes;
  final bool isImage;
  const _ProjAttachedFile(
      {required this.name, required this.bytes, required this.isImage});
}

// ── Add note sheet for project ────────────────────────────────────────────────

class _ProjectNoteSheet extends ConsumerStatefulWidget {
  final String projectId;
  final bool isChangeRequest;
  const _ProjectNoteSheet({required this.projectId, this.isChangeRequest = false});

  @override
  ConsumerState<_ProjectNoteSheet> createState() => _ProjectNoteSheetState();
}

class _ProjectNoteSheetState extends ConsumerState<_ProjectNoteSheet> {
  final _notesCtrl = TextEditingController();
  final _wikiCtrl = TextEditingController();
  final _stt = SpeechToText();
  final _imagePicker = ImagePicker();

  bool _sttAvailable = false;
  bool _listening = false;
  bool _loading = false;
  String _partialText = '';
  final List<_ProjAttachedFile> _attachments = [];
  final List<String> _wikiUrls = [];

  void _addWikiUrl() {
    final url = _wikiCtrl.text.trim();
    if (url.isEmpty) return;
    if (!_wikiUrls.contains(url)) setState(() => _wikiUrls.add(url));
    _wikiCtrl.clear();
  }

  @override
  void initState() {
    super.initState();
    _initStt();
  }

  Future<void> _initStt() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    final ok = await _stt.initialize(
      onStatus: (s) {
        if (mounted) setState(() => _listening = s == 'listening');
      },
      onError: (_) {
        if (mounted) setState(() { _listening = false; _partialText = ''; });
      },
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() { _listening = false; _partialText = ''; });
      return;
    }
    setState(() { _listening = true; _partialText = ''; });
    await _stt.listen(
      onResult: (r) {
        if (r.finalResult) {
          final cur = _notesCtrl.text;
          final appended =
              cur.isEmpty ? r.recognizedWords : '$cur ${r.recognizedWords}';
          setState(() {
            _notesCtrl.text = appended;
            _notesCtrl.selection =
                TextSelection.collapsed(offset: appended.length);
            _listening = false;
            _partialText = '';
          });
        } else {
          setState(() => _partialText = r.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      ),
    );
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Photo Library'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await _imagePicker.pickImage(
        source: source, imageQuality: 80, maxWidth: 1920);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _attachments
        .add(_ProjAttachedFile(name: picked.name, bytes: bytes, isImage: true)));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'doc', 'docx', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    setState(() => _attachments
        .add(_ProjAttachedFile(name: f.name, bytes: f.bytes!, isImage: false)));
  }

  bool _enhancing = false;

  Future<void> _enhanceAgainstPrd() async {
    final raw = _notesCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _enhancing = true);
    try {
      final resp = await ApiClient.dio.post(
        '/api/projects/${widget.projectId}/enhance-against-prd',
        data: {'raw_text': raw},
      );
      final enhanced = resp.data['enhanced_text'] as String;
      _notesCtrl.text = enhanced;
      _notesCtrl.selection = TextSelection.collapsed(offset: enhanced.length);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enhancement failed — try again')),
        );
      }
    }
    if (mounted) setState(() => _enhancing = false);
  }

  Future<void> _submit() async {
    final raw = _notesCtrl.text.trim();
    if (raw.isEmpty) return;
    if (_wikiCtrl.text.trim().isNotEmpty) _addWikiUrl();
    setState(() => _loading = true);

    final note = await ref
        .read(projectNotesProvider(widget.projectId).notifier)
        .createNote(
            raw,
            _wikiUrls.isEmpty ? null : _wikiUrls.join('\n'),
            noteType: widget.isChangeRequest ? 'change_request' : 'note',
        );

    if (note != null && _attachments.isNotEmpty) {
      for (final a in _attachments) {
        try {
          final form = FormData.fromMap({
            'file': MultipartFile.fromBytes(a.bytes, filename: a.name),
          });
          await ApiClient.dio
              .post('/api/notes/${note.id}/attachments', data: form);
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(note != null ? 'Note added to project' : 'Failed to add note')),
    );
  }

  @override
  void dispose() {
    _stt.stop();
    _notesCtrl.dispose();
    _wikiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Gap(16),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: widget.isChangeRequest
                      ? SeraTokens.statusInProgressWarm.withValues(alpha: 0.12)
                      : SeraTokens.primaryLight,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(
                widget.isChangeRequest ? Icons.change_circle_outlined : Icons.note_add_rounded,
                color: widget.isChangeRequest ? SeraTokens.statusInProgressWarm : SeraTokens.primary,
                size: 20,
              ),
            ),
            const Gap(10),
            Text(
              widget.isChangeRequest ? 'Change Request' : 'Add Meeting Notes',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ]),
          const Gap(16),
          Stack(children: [
            TextField(
              controller: _notesCtrl,
              maxLines: 7,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Paste or type your raw meeting notes here…\nOr use the mic to dictate.',
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.fromLTRB(14, 14, 50, 14),
              ),
            ),
            Positioned(
              right: 4, top: 4,
              child: Column(children: [
                IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _notesCtrl.text = data!.text!.trim();
                      _notesCtrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _notesCtrl.text.length));
                    }
                  },
                ),
                if (_sttAvailable)
                  IconButton(
                    tooltip: _listening ? 'Stop' : 'Dictate',
                    icon: Icon(
                      _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      size: 20,
                      color: _listening ? Colors.red : null,
                    ),
                    onPressed: _toggleListening,
                  ),
              ]),
            ),
          ]),
          if (_listening) ...[
            const Gap(6),
            Row(children: [
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const Gap(8),
              Expanded(
                child: Text(
                  _partialText.isNotEmpty ? _partialText : 'Listening…',
                  style: const TextStyle(fontSize: 12, color: SeraTokens.fg3),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
          if (widget.isChangeRequest) ...[
            const Gap(8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enhancing ? null : _enhanceAgainstPrd,
                icon: _enhancing
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: Text(_enhancing ? 'Enhancing…' : 'Enhance against PRD'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SeraTokens.statusInProgressWarm,
                  side: const BorderSide(color: SeraTokens.statusInProgressWarm),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          const Gap(10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_rounded, size: 16),
              label: const Text('Image'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
            const Gap(8),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: const Text('File'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
          ]),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 2),
            child: Text(
              'Files: PDF, DOCX, DOC, TXT, MD',
              style: TextStyle(fontSize: 11, color: SeraTokens.hint),
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            const Gap(8),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: _attachments.map((a) => Chip(
                avatar: Icon(
                  a.isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                  size: 14),
                label: Text(a.name,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setState(() => _attachments.remove(a)),
              )).toList(),
            ),
          ],
          const Gap(10),
          WikiUrlInput(
            controller: _wikiCtrl,
            urls: _wikiUrls,
            onAdd: _addWikiUrl,
            onRemove: (url) => setState(() => _wikiUrls.remove(url)),
          ),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_loading ? 'Saving…' : 'Save Notes'),
            ),
          ),
        ],
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

// ── Approved PRD card ─────────────────────────────────────────────────────────

class _ApprovedPrdCard extends StatelessWidget {
  final MeetingNote note;
  const _ApprovedPrdCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final dateStr = note.createdAt.toLocal().toString().substring(0, 10);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      decoration: BoxDecoration(
        color: SeraTokens.statusApproved.withValues(alpha: 0.05),
        border: Border.all(color: SeraTokens.statusApproved.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.verified_rounded, size: 16, color: SeraTokens.statusApproved),
              const Gap(8),
              Expanded(
                child: Text(
                  note.title ?? 'Approved PRD',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14, color: SeraTokens.fg1),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SeraTokens.statusApproved.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'v${note.prdVersionNumber ?? 1}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: SeraTokens.statusApproved),
                ),
              ),
            ]),
            const Gap(8),
            Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: SeraTokens.muted),
              const Gap(4),
              Text('Approved $dateStr',
                  style: const TextStyle(fontSize: 12, color: SeraTokens.muted)),
            ]),
            if (note.prdFileUrl != null || note.prdFileRawUrl != null) ...[
              const Gap(10),
              OutlinedButton.icon(
                onPressed: () async {
                  final url = note.prdFileUrl ?? note.prdFileRawUrl!;
                  // Navigate to GitHub link — use url_launcher if available
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PRD: $url'), duration: const Duration(seconds: 4)),
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: const Text('View PRD'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SeraTokens.statusApproved,
                  side: const BorderSide(color: SeraTokens.statusApproved),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Change Request card ───────────────────────────────────────────────────────

class _CrCard extends ConsumerStatefulWidget {
  final MeetingNote note;
  final String projectId;
  const _CrCard({required this.note, required this.projectId});

  @override
  ConsumerState<_CrCard> createState() => _CrCardState();
}

class _CrCardState extends ConsumerState<_CrCard> {
  late MeetingNote _note;
  bool _enhancing = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
  }

  @override
  void didUpdateWidget(_CrCard old) {
    super.didUpdateWidget(old);
    if (old.note.id == widget.note.id) _note = widget.note;
  }

  bool get _isClosed => _note.status == 'Closed';
  bool get _isGenerating => _note.brdGenerationPhase != null;

  Color get _statusColor {
    switch (_note.status) {
      case 'Closed': return SeraTokens.statusApproved;
      case 'In Review': return SeraTokens.statusInReview;
      default: return SeraTokens.statusInProgressWarm;
    }
  }

  // ── Enhance against PRD ──────────────────────────────────────────────────
  Future<void> _enhanceAgainstPrd() async {
    setState(() => _enhancing = true);
    try {
      // 1. Enhance raw notes against the approved PRD
      final enhResp = await ApiClient.dio.post(
        '/api/projects/${widget.projectId}/enhance-against-prd',
        data: {'raw_text': _note.rawNotes},
      );
      final enhanced = enhResp.data['enhanced_text'] as String;

      // 2. Save enhanced notes back to the CR
      await ApiClient.dio.patch('/api/notes/${_note.id}', data: {'content': enhanced});

      // 3. Trigger summary regeneration
      final regenResp = await ApiClient.dio.post('/api/notes/${_note.id}/regenerate-cr-summary');
      if (mounted) {
        setState(() => _note = MeetingNote.fromJson(regenResp.data as Map<String, dynamic>));
        ref.read(projectNotesProvider(widget.projectId).notifier).fetch();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enhanced — regenerating summary…')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enhancement failed — try again'),
              backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _enhancing = false);
  }

  // ── See Summary sheet ────────────────────────────────────────────────────
  void _showSummary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CrSummarySheet(note: _note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _note.createdAt.toLocal().toString().substring(0, 10);
    final hasSummary = _note.brdDraft != null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CrDetailScreen(note: _note)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isClosed ? Icons.check_circle_rounded
                        : _isGenerating ? Icons.hourglass_top_rounded
                        : Icons.change_circle_outlined,
                    color: _statusColor, size: 16,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Text(_note.title ?? 'Change Request',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_note.status,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: _statusColor)),
                ),
              ]),
              const Gap(8),

              // ── Summary preview ─────────────────────────────────────
              if (_isGenerating)
                Row(children: [
                  SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: SeraTokens.statusInProgressWarm)),
                  const Gap(8),
                  const Text('Generating summary…',
                      style: TextStyle(fontSize: 12, color: SeraTokens.statusInProgressWarm,
                          fontStyle: FontStyle.italic)),
                ])
              else if (hasSummary)
                Text(
                  _note.brdDraft!.replaceAll(RegExp(r'#+\s*'), '').trim(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SeraTokens.fg3, height: 1.4),
                )
              else
                Text(_note.rawNotes,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: SeraTokens.fg3)),

              const Gap(8),

              // ── Meta row ────────────────────────────────────────────
              Row(children: [
                const Icon(Icons.calendar_today_rounded, size: 11, color: SeraTokens.muted),
                const Gap(4),
                Text(dateStr, style: const TextStyle(fontSize: 11, color: SeraTokens.muted)),
                if (_isClosed && _note.plannerDocUrl != null) ...[
                  const Gap(10),
                  const Icon(Icons.attach_file_rounded, size: 11, color: SeraTokens.statusApproved),
                  const Gap(3),
                  const Text('Planner doc ready',
                      style: TextStyle(fontSize: 11, color: SeraTokens.statusApproved,
                          fontWeight: FontWeight.w600)),
                ],
              ]),

              // ── Action buttons ───────────────────────────────────────
              const Gap(10),
              const Divider(height: 1),
              const Gap(8),
              // Row 1: See Summary + Enhance against PRD
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showSummary,
                    icon: const Icon(Icons.summarize_rounded, size: 14),
                    label: const Text('See Summary'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (!_isClosed) ...[
                  const Gap(8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _enhancing ? null : _enhanceAgainstPrd,
                      icon: _enhancing
                          ? const SizedBox(width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_fix_high_rounded, size: 14),
                      label: Text(_enhancing ? 'Enhancing…' : 'Enhance against PRD'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SeraTokens.statusInProgressWarm,
                        side: const BorderSide(color: SeraTokens.statusInProgressWarm),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ]),
              // Row 2: Open ticket + Copy
              const Gap(6),
              Row(children: [
                if (_note.githubIssueUrl != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(_note.githubIssueUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: const Text('Open Ticket'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                if (_note.githubIssueUrl != null) const Gap(8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final content = _note.brdDraft ?? _note.rawNotes;
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CR Summary bottom sheet ───────────────────────────────────────────────────

class _CrSummarySheet extends StatelessWidget {
  final MeetingNote note;
  const _CrSummarySheet({required this.note});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasSummary = note.brdDraft != null && note.brdDraft!.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Gap(12),
            Center(
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const Gap(12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.summarize_rounded, size: 18, color: SeraTokens.primary),
                const Gap(10),
                Expanded(
                  child: Text(note.title ?? 'Change Request',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SeraTokens.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(note.status,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: SeraTokens.primary)),
                ),
              ]),
            ),
            const Gap(8),
            const Divider(height: 1),
            Expanded(
              child: hasSummary
                  ? ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        MarkdownBody(
                          data: note.brdDraft!,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 13, height: 1.6,
                                color: SeraTokens.fg1),
                            h1: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(note.brdGenerationPhase != null
                              ? Icons.hourglass_top_rounded
                              : Icons.pending_rounded,
                              size: 40, color: SeraTokens.muted),
                          const Gap(12),
                          Text(
                            note.brdGenerationPhase != null
                                ? 'Summary is being generated…'
                                : 'No summary yet. Use "Enhance against PRD" to generate one.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: SeraTokens.fg3),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable search + no-results widgets ──────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          borderSide: BorderSide(color: SeraTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          borderSide: BorderSide(color: SeraTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          borderSide: const BorderSide(color: SeraTokens.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String label;
  const _NoResults({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 38, color: SeraTokens.fg3),
            const Gap(8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SeraTokens.fg3,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
