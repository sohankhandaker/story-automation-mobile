import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../core/api.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _prdPhaseNames = [
  '',
  'Document Header, Purpose & Product Summary',
  'Product Goals, Non-Goals, Target Users & Platforms',
  'MVP Scope & Core Concepts',
  'Architecture & User Flows',
  'State Machines & Functional Requirements',
  'Screen Requirements & Data Model',
  'API Contract & Permissions Matrix',
  'Validation Rules, Notifications & Reporting',
  'NFRs, Error Handling & Edge Cases',
  'AI Coding Guidance & User Stories',
];

const _prdStatusColors = {
  'Draft': Color(0xFF78909C),
  'In Progress': Color(0xFF1565C0),
  'Pending Review': Color(0xFF6A1B9A),
  'In Review': Color(0xFF1E88E5),
  'Changes Requested': Color(0xFFE53935),
  'Approved': Color(0xFF43A047),
  'Sent to Planner': Color(0xFF00897B),
};

// ── Models ────────────────────────────────────────────────────────────────────

class PrdReviewerStatus {
  final String githubUsername;
  final String? name;
  final String status; // Pending | Approved

  PrdReviewerStatus(
      {required this.githubUsername, this.name, required this.status});

  factory PrdReviewerStatus.fromJson(Map<String, dynamic> j) =>
      PrdReviewerStatus(
        githubUsername: j['github_username'] as String,
        name: j['name'] as String?,
        status: (j['status'] as String?) ?? 'Pending',
      );
}

class PrdDocument {
  final String id;
  final String noteId;
  final String? prdDraft;
  final int? prdGenerationPhase;
  final String status;
  final int currentVersionNumber;
  final String? githubIssueUrl;
  final int? githubIssueNumber;
  final String? reviewerGithubUsername;
  final String? reviewerName;
  final List<PrdReviewerStatus> reviewers;
  final DateTime createdAt;
  final DateTime updatedAt;

  PrdDocument.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        noteId = j['note_id'] as String,
        prdDraft = j['prd_draft'] as String?,
        prdGenerationPhase = j['prd_generation_phase'] as int?,
        status = (j['status'] as String?) ?? 'Draft',
        currentVersionNumber = (j['current_version_number'] as int?) ?? 0,
        githubIssueUrl = j['github_issue_url'] as String?,
        githubIssueNumber = j['github_issue_number'] as int?,
        reviewerGithubUsername = j['reviewer_github_username'] as String?,
        reviewerName = j['reviewer_name'] as String?,
        reviewers = (j['reviewers'] as List<dynamic>? ?? [])
            .map((r) =>
                PrdReviewerStatus.fromJson(r as Map<String, dynamic>))
            .toList(),
        createdAt = DateTime.parse(j['created_at'] as String),
        updatedAt = DateTime.parse(j['updated_at'] as String);
}

class PrdVersion {
  final String id;
  final String prdId;
  final int versionNumber;
  final String prdMarkdown;
  final String? changeSummary;
  final List<String> changedSections;
  final String? reviewerComment;
  final DateTime createdAt;

  PrdVersion.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        prdId = j['prd_id'] as String,
        versionNumber = j['version_number'] as int,
        prdMarkdown = j['prd_markdown'] as String,
        changeSummary = j['change_summary'] as String?,
        changedSections = List<String>.from(j['changed_sections'] ?? []),
        reviewerComment = j['reviewer_comment'] as String?,
        createdAt = DateTime.parse(j['created_at'] as String);
}

// ── Section parser (reused from BRD pattern) ─────────────────────────────────

class _PrdSection {
  final String heading;
  final int level;
  final String content;
  _PrdSection({required this.heading, required this.level, required this.content});
}

List<_PrdSection> _parsePrdSections(String markdown) {
  final sections = <_PrdSection>[];
  final lines = markdown.split('\n');
  String currentHeading = '';
  int currentLevel = 0;
  final buffer = StringBuffer();

  void flush() {
    if (currentHeading.isNotEmpty || buffer.isNotEmpty) {
      sections.add(_PrdSection(
        heading: currentHeading,
        level: currentLevel,
        content: buffer.toString().trim(),
      ));
      buffer.clear();
    }
  }

  for (final line in lines) {
    if (line.startsWith('### ')) {
      flush();
      currentHeading = line.substring(4).trim();
      currentLevel = 3;
    } else if (line.startsWith('## ')) {
      flush();
      currentHeading = line.substring(3).trim();
      currentLevel = 2;
    } else if (line.startsWith('# ')) {
      flush();
      currentHeading = line.substring(2).trim();
      currentLevel = 1;
    } else {
      buffer.writeln(line);
    }
  }
  flush();
  return sections;
}

bool _sectionIsChanged(String heading, List<String> changedSections) {
  final h = heading.toLowerCase();
  return changedSections.any(
      (c) => h.contains(c.toLowerCase()) || c.toLowerCase().contains(h));
}

// ── Provider ──────────────────────────────────────────────────────────────────

class PrdNotifier extends StateNotifier<AsyncValue<PrdDocument?>> {
  PrdNotifier() : super(const AsyncValue.data(null));

  Future<void> fetchPrd(String noteId) async {
    state = const AsyncValue.loading();
    try {
      final resp = await ApiClient.dio.get('/api/notes/$noteId/prd');
      state = AsyncValue.data(
          PrdDocument.fromJson(resp.data as Map<String, dynamic>));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        state = const AsyncValue.data(null);
      } else {
        state = AsyncValue.error(e, e.stackTrace);
      }
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<PrdDocument?> generatePrd(String noteId) async {
    try {
      final resp =
          await ApiClient.dio.post('/api/notes/$noteId/prd/generate');
      final prd =
          PrdDocument.fromJson(resp.data as Map<String, dynamic>);
      state = AsyncValue.data(prd);
      return prd;
    } catch (_) {
      return null;
    }
  }

  Future<PrdDocument?> pollPrd(String noteId) async {
    try {
      final resp = await ApiClient.dio.get('/api/notes/$noteId/prd');
      return PrdDocument.fromJson(resp.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<PrdDocument?> assignReviewer(
      String noteId, String username, String? name) async {
    try {
      final resp = await ApiClient.dio.post(
        '/api/notes/$noteId/prd/assign-reviewer',
        data: {
          'reviewer_github_username': username,
          if (name != null && name.isNotEmpty) 'reviewer_name': name,
        },
      );
      final prd =
          PrdDocument.fromJson(resp.data as Map<String, dynamic>);
      state = AsyncValue.data(prd);
      return prd;
    } catch (_) {
      return null;
    }
  }

  Future<PrdDocument?> submitFeedback(
      String noteId, String feedback) async {
    try {
      final resp = await ApiClient.dio.post(
        '/api/notes/$noteId/prd/feedback',
        data: {'feedback': feedback},
      );
      final prd =
          PrdDocument.fromJson(resp.data as Map<String, dynamic>);
      state = AsyncValue.data(prd);
      return prd;
    } catch (_) {
      return null;
    }
  }

  Future<PrdDocument?> sendToPlanner(String noteId) async {
    try {
      final resp = await ApiClient.dio
          .post('/api/notes/$noteId/prd/send-to-planner');
      final prd =
          PrdDocument.fromJson(resp.data as Map<String, dynamic>);
      state = AsyncValue.data(prd);
      return prd;
    } catch (_) {
      return null;
    }
  }

  void updatePrd(PrdDocument prd) {
    state = AsyncValue.data(prd);
  }

  Future<List<PrdVersion>> fetchVersions(String noteId) async {
    try {
      final resp =
          await ApiClient.dio.get('/api/notes/$noteId/prd/versions');
      return (resp.data['versions'] as List)
          .map((j) => PrdVersion.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

final prdProvider = StateNotifierProvider.family<PrdNotifier,
    AsyncValue<PrdDocument?>, String>(
  (_, __) => PrdNotifier(),
);

// ── Status chip ───────────────────────────────────────────────────────────────

class _PrdStatusChip extends StatelessWidget {
  final String status;
  const _PrdStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _prdStatusColors[status] ?? const Color(0xFF78909C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── PRD Screen (entry point) ──────────────────────────────────────────────────

class PrdScreen extends ConsumerStatefulWidget {
  final String noteId;
  const PrdScreen({super.key, required this.noteId});

  @override
  ConsumerState<PrdScreen> createState() => _PrdScreenState();
}

class _PrdScreenState extends ConsumerState<PrdScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(prdProvider(widget.noteId).notifier).fetchPrd(widget.noteId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final prdAsync = ref.watch(prdProvider(widget.noteId));

    return prdAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('PRD')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('PRD')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const Gap(12),
              Text('$e'),
              TextButton(
                onPressed: () => ref
                    .read(prdProvider(widget.noteId).notifier)
                    .fetchPrd(widget.noteId),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (prd) {
        if (prd == null) {
          return _PrdGeneratePrompt(noteId: widget.noteId);
        }
        return _PrdDetailScreen(noteId: widget.noteId, prd: prd);
      },
    );
  }
}

// ── Generate Prompt (no PRD yet) ──────────────────────────────────────────────

class _PrdGeneratePrompt extends ConsumerStatefulWidget {
  final String noteId;
  const _PrdGeneratePrompt({required this.noteId});

  @override
  ConsumerState<_PrdGeneratePrompt> createState() =>
      _PrdGeneratePromptState();
}

class _PrdGeneratePromptState extends ConsumerState<_PrdGeneratePrompt> {
  bool _generating = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PRD',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFE65100).withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.description_rounded,
                        size: 36, color: Color(0xFFE65100)),
                  ),
                  const Gap(16),
                  const Text(
                    'Generate Product Requirements Document',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const Gap(8),
                  Text(
                    'SERA will generate a comprehensive PRD from your approved BRD in 8 phases.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Gap(20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kPrimaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('8 generation phases:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: kPrimary)),
                  const Gap(8),
                  ..._prdPhaseNames
                      .skip(1)
                      .toList()
                      .asMap()
                      .entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e.key + 1}. ',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: kPrimary,
                                      fontWeight: FontWeight.w600),
                                ),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    style: const TextStyle(
                                        fontSize: 12, color: kPrimary),
                                  ),
                                ),
                              ],
                            ),
                          )),
                ],
              ),
            ),
            if (_error != null) ...[
              const Gap(12),
              Text(_error!,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFE53935))),
            ],
            const Gap(20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100)),
                onPressed: _generating
                    ? null
                    : () async {
                        setState(() {
                          _generating = true;
                          _error = null;
                        });
                        final prd = await ref
                            .read(prdProvider(widget.noteId).notifier)
                            .generatePrd(widget.noteId);
                        if (!mounted) return;
                        if (prd == null) {
                          setState(() {
                            _generating = false;
                            _error =
                                'Failed to start PRD generation. Check your GitHub config in Settings.';
                          });
                        }
                        // Success: prdProvider state updated → parent rebuilds to _PrdDetailScreen
                      },
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_generating
                    ? 'Creating GitHub ticket…'
                    : 'Generate PRD'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PRD Detail Screen ─────────────────────────────────────────────────────────

class _PrdDetailScreen extends ConsumerStatefulWidget {
  final String noteId;
  final PrdDocument prd;

  const _PrdDetailScreen({required this.noteId, required this.prd});

  @override
  ConsumerState<_PrdDetailScreen> createState() =>
      _PrdDetailScreenState();
}

class _PrdDetailScreenState extends ConsumerState<_PrdDetailScreen>
    with SingleTickerProviderStateMixin {
  late PrdDocument _prd;
  Timer? _pollTimer;
  TabController? _tabController;

  bool get _isWorking =>
      _prd.prdGenerationPhase != null || _prd.status == 'In Progress';

  bool get _prdReady => _prd.prdDraft != null && !_isWorking;

  bool get _shouldPoll =>
      _isWorking ||
      _prd.status == 'In Review' ||
      _prd.status == 'Changes Requested';

  @override
  void initState() {
    super.initState();
    _prd = widget.prd;
    if (_prdReady) _initTabs();
    if (_shouldPoll) _startPolling();
  }

  void _initTabs() {
    _tabController?.dispose();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      final updated = await ref
          .read(prdProvider(widget.noteId).notifier)
          .pollPrd(widget.noteId);
      if (updated != null && mounted) {
        final wasWorking = _isWorking;
        ref
            .read(prdProvider(widget.noteId).notifier)
            .updatePrd(updated);
        setState(() {
          _prd = updated;
          if (_prdReady && _tabController == null) _initTabs();
        });
        if ((wasWorking && !_isWorking) ||
            updated.status == 'Approved' ||
            updated.status == 'Sent to Planner') {
          _pollTimer?.cancel();
        }
      }
    });
  }

  void _openAssignReviewer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrdAssignReviewerSheet(
        prd: _prd,
        noteId: widget.noteId,
        onAssigned: (updated) {
          setState(() => _prd = updated);
          _startPolling();
        },
      ),
    );
  }

  void _openRequestUpdate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrdFeedbackSheet(
        noteId: widget.noteId,
        onSubmit: (feedback) async {
          Navigator.pop(context);
          final updated = await ref
              .read(prdProvider(widget.noteId).notifier)
              .submitFeedback(widget.noteId, feedback);
          if (updated != null && mounted) {
            setState(() => _prd = updated);
            _startPolling();
          }
        },
      ),
    );
  }

  Future<void> _sendToPlanner() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send to Planner'),
        content: const Text(
            'This will mark the PRD as sent to the Planner Agent. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = await ref
        .read(prdProvider(widget.noteId).notifier)
        .sendToPlanner(widget.noteId);
    if (updated != null && mounted) {
      setState(() => _prd = updated);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isWorking
          ? _buildLoadingBody()
          : _prdReady
              ? _buildReadyBody()
              : const Center(child: CircularProgressIndicator()),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        _isWorking ? 'Generating PRD…' : 'PRD',
        style:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (_prdReady) ...[
          _PrdStatusChip(_prd.status),
          const Gap(2),
          if (_prd.githubIssueUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View on GitHub',
              onPressed: () =>
                  launchUrl(Uri.parse(_prd.githubIssueUrl!)),
            ),
          if (_prd.status == 'Pending Review' ||
              _prd.status == 'In Review' ||
              _prd.status == 'Changes Requested')
            IconButton(
              icon: const Icon(Icons.person_add_rounded,
                  color: Color(0xFF6A1B9A)),
              tooltip: _prd.reviewers.isNotEmpty
                  ? 'Add Another Reviewer'
                  : 'Assign Reviewer',
              onPressed: _openAssignReviewer,
            ),
          if (_prd.status == 'In Review' ||
              _prd.status == 'Changes Requested')
            IconButton(
              icon: const Icon(Icons.edit_note_rounded,
                  color: Color(0xFFE53935)),
              tooltip: 'Request PRD Update',
              onPressed: _openRequestUpdate,
            ),
          if (_prd.status == 'Approved')
            IconButton(
              icon: const Icon(Icons.send_rounded,
                  color: Color(0xFF00897B), size: 20),
              tooltip: 'Send to Planner',
              onPressed: _sendToPlanner,
            ),
          if (_prd.prdDraft != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copy PRD',
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _prd.prdDraft ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('PRD copied to clipboard')),
                );
              },
            ),
        ],
      ],
      bottom: _prdReady && _tabController != null
          ? TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'PRD Content'),
                Tab(text: 'Versions'),
              ],
              labelColor: kPrimary,
              indicatorColor: kPrimary,
              unselectedLabelColor: const Color(0xFF8896A5),
            )
          : null,
    );
  }

  Widget _buildLoadingBody() {
    final isUpdate =
        _prd.prdDraft != null && _prd.prdGenerationPhase == 0;
    final phase = _prd.prdGenerationPhase;
    final totalPhases = _prdPhaseNames.length - 1;
    final hasPhase = !isUpdate && phase != null && phase > 0 && phase < _prdPhaseNames.length;
    final phaseVal = hasPhase ? phase : 0;
    final pct = hasPhase ? phaseVal / totalPhases : (isUpdate ? null : 0.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: pct != null && pct > 0 ? pct : null,
                  color: kPrimary,
                ),
              ),
              const Gap(10),
              Expanded(
                child: Text(
                  hasPhase
                      ? _prdPhaseNames[phaseVal]
                      : (isUpdate ? 'Applying your changes…' : 'Generating PRD…'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: kPrimary,
                  ),
                ),
              ),
              if (pct != null)
                Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: kPrimary,
                  ),
                ),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: kPrimaryLight,
              color: kPrimary,
            ),
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              hasPhase
                  ? 'Phase $phaseVal of $totalPhases  ·  ${((pct ?? 0) * 100).round()}% complete'
                  : (isUpdate
                      ? 'Applying your changes. About 30–60 seconds.'
                      : 'Generating PRD in 10 phases…  About 2–3 minutes.'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ),
        Container(height: 1, color: const Color(0xFFE8EDF2)),
      ],
    );
  }

  Widget _buildReadyBody() {
    if (_tabController == null) return const SizedBox.shrink();
    return TabBarView(
      controller: _tabController,
      children: [
        PrdContentTab(prd: _prd, noteId: widget.noteId),
        PrdVersionsTab(
            noteId: widget.noteId,
            currentVersionNumber: _prd.currentVersionNumber),
      ],
    );
  }
}

// ── PRD Content tab ───────────────────────────────────────────────────────────

class PrdContentTab extends ConsumerWidget {
  final PrdDocument prd;
  final String noteId;

  const PrdContentTab({super.key, required this.prd, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final statusColor =
        _prdStatusColors[prd.status] ?? cs.primary;

    return CustomScrollView(
      slivers: [
        if (prd.status != 'Draft' && prd.status != 'In Progress')
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      prd.status == 'Approved' ||
                              prd.status == 'Sent to Planner'
                          ? Icons.check_circle_rounded
                          : prd.status == 'Pending Review'
                              ? Icons.hourglass_top_rounded
                              : Icons.rate_review_rounded,
                      size: 16,
                      color: statusColor,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prd.status == 'Approved'
                                ? 'PRD Approved ✓'
                                : prd.status == 'Sent to Planner'
                                    ? 'PRD sent to Planner Agent'
                                    : prd.status == 'Pending Review'
                                        ? 'PRD Ready — tap Assign Reviewer to start review'
                                        : prd.status == 'In Review'
                                            ? 'Under Review'
                                            : 'Changes Requested',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: statusColor),
                          ),
                          if (prd.githubIssueUrl != null &&
                              prd.status != 'Pending Review')
                            const Text(
                                'GitHub issue linked · comments trigger AI updates',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B7A8D))),
                        ],
                      ),
                    ),
                  ]),
                  if (prd.reviewers.isNotEmpty) ...[
                    const Gap(10),
                    const Divider(height: 1),
                    const Gap(8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: prd.reviewers.map((r) {
                        final approved = r.status == 'Approved';
                        final color = approved
                            ? const Color(0xFF43A047)
                            : const Color(0xFF1E88E5);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: color.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  approved
                                      ? Icons.check_circle_rounded
                                      : Icons.hourglass_empty_rounded,
                                  size: 12,
                                  color: color,
                                ),
                                const Gap(4),
                                Text('@${r.githubUsername}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: color)),
                                const Gap(4),
                                Text(approved ? 'Approved' : 'Pending',
                                    style: TextStyle(
                                        fontSize: 10, color: color)),
                              ]),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (prd.status == 'In Review' ||
            prd.status == 'Changes Requested')
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _PrdFeedbackSheet(
                      noteId: noteId,
                      onSubmit: (feedback) async {
                        Navigator.pop(context);
                        await ref
                            .read(prdProvider(noteId).notifier)
                            .submitFeedback(noteId, feedback);
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded,
                    size: 16, color: Color(0xFFE53935)),
                label: const Text('Request PRD Update'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        if (prd.status == 'Approved')
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B)),
                onPressed: () async {
                  final updated = await ref
                      .read(prdProvider(noteId).notifier)
                      .sendToPlanner(noteId);
                  if (updated != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('PRD sent to Planner Agent')),
                    );
                  }
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send to Planner Agent'),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Markdown(
            data: prd.prdDraft ?? '',
            selectable: true,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            styleSheet: MarkdownStyleSheet(
              h1: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              h2: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kPrimary),
              h3: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold),
              p: const TextStyle(fontSize: 14, height: 1.5),
              tableHead: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
              tableBody: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Gap(32)),
      ],
    );
  }
}

// ── PRD Versions tab ──────────────────────────────────────────────────────────

class PrdVersionsTab extends ConsumerStatefulWidget {
  final String noteId;
  final int currentVersionNumber;

  const PrdVersionsTab(
      {super.key, required this.noteId, required this.currentVersionNumber});

  @override
  ConsumerState<PrdVersionsTab> createState() =>
      _PrdVersionsTabState();
}

class _PrdVersionsTabState extends ConsumerState<PrdVersionsTab> {
  late Future<List<PrdVersion>> _versionsFuture;

  @override
  void initState() {
    super.initState();
    _versionsFuture = ref
        .read(prdProvider(widget.noteId).notifier)
        .fetchVersions(widget.noteId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<PrdVersion>>(
      future: _versionsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final versions = snap.data ?? [];
        if (versions.isEmpty) {
          return Center(
              child: Text('No versions yet',
                  style:
                      TextStyle(color: cs.onSurfaceVariant)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: versions.length,
          itemBuilder: (_, i) {
            final v = versions[i];
            final isCurrent =
                v.versionNumber == widget.currentVersionNumber;
            return _PrdVersionCard(
              version: v,
              isCurrent: isCurrent,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _PrdVersionScreen(
                      version: v, isCurrent: isCurrent),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PrdVersionCard extends StatelessWidget {
  final PrdVersion version;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PrdVersionCard(
      {required this.version,
      required this.isCurrent,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final changedCount = version.changedSections.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isCurrent
                    ? kPrimaryLight
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  'v${version.versionNumber}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isCurrent
                          ? kPrimary
                          : cs.onSurfaceVariant),
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        version.changeSummary ??
                            'Initial generation',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              kPrimary.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(6),
                        ),
                        child: const Text('Current',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: kPrimary)),
                      ),
                  ]),
                  const Gap(4),
                  Row(children: [
                    Text(
                      _fmt(version.createdAt),
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant),
                    ),
                    if (changedCount > 0) ...[
                      const Gap(8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8F00)
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$changedCount section${changedCount == 1 ? '' : 's'} changed',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF8F00)),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Assign Reviewer Sheet ─────────────────────────────────────────────────────

class _PrdAssignReviewerSheet extends ConsumerStatefulWidget {
  final PrdDocument prd;
  final String noteId;
  final void Function(PrdDocument updated) onAssigned;

  const _PrdAssignReviewerSheet(
      {required this.prd,
      required this.noteId,
      required this.onAssigned});

  @override
  ConsumerState<_PrdAssignReviewerSheet> createState() =>
      _PrdAssignReviewerSheetState();
}

class _PrdAssignReviewerSheetState
    extends ConsumerState<_PrdAssignReviewerSheet> {
  ReviewerItem? _selected;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final reviewers =
        ref.read(authProvider).user?.reviewerList ?? [];

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
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
                  color: const Color(0xFF6A1B9A)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_add_rounded,
                  color: Color(0xFF6A1B9A), size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assign PRD Reviewer',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17)),
                  Text(
                      'Reviewer will be notified on GitHub to review the PRD',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7A8D))),
                ],
              ),
            ),
          ]),
          const Gap(20),
          const Text('Select Reviewer',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const Gap(8),
          if (reviewers.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.orange),
                Gap(8),
                Expanded(
                  child: Text(
                    'No reviewers configured. Go to Settings to add reviewers.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange),
                  ),
                ),
              ]),
            )
          else
            RadioGroup<ReviewerItem>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Column(
                children: reviewers
                    .map((r) => RadioListTile<ReviewerItem>(
                          value: r,
                          title: Text(r.name,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          subtitle: Text('@${r.githubUsername}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7A8D))),
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFF6A1B9A),
                        ))
                    .toList(),
              ),
            ),
          if (_error != null) ...[
            const Gap(8),
            Text(_error!,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFE53935))),
          ],
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A)),
              onPressed: _submitting || _selected == null
                  ? null
                  : () async {
                      setState(() {
                        _submitting = true;
                        _error = null;
                      });
                      final navigator = Navigator.of(context);
                      final updated = await ref
                          .read(prdProvider(widget.noteId)
                              .notifier)
                          .assignReviewer(
                            widget.noteId,
                            _selected!.githubUsername,
                            _selected!.name,
                          );
                      if (!mounted) return;
                      if (updated != null) {
                        navigator.pop();
                        widget.onAssigned(updated);
                      } else {
                        setState(() {
                          _submitting = false;
                          _error =
                              'Failed to assign reviewer. Try again.';
                        });
                      }
                    },
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_submitting
                  ? 'Assigning reviewer…'
                  : 'Assign & Start Review'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PRD Feedback Sheet ────────────────────────────────────────────────────────

class _PrdFeedbackSheet extends StatefulWidget {
  final String noteId;
  final void Function(String feedback) onSubmit;

  const _PrdFeedbackSheet(
      {required this.noteId, required this.onSubmit});

  @override
  State<_PrdFeedbackSheet> createState() =>
      _PrdFeedbackSheetState();
}

class _PrdFeedbackSheetState extends State<_PrdFeedbackSheet> {
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
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
                  color: const Color(0xFFE53935)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_note_rounded,
                  color: Color(0xFFE53935), size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Request PRD Update',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17)),
                  Text('AI updates only the affected sections',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7A8D))),
                ],
              ),
            ),
          ]),
          const Gap(16),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              hintText:
                  'Describe what needs to change in the PRD…\n\nExample: "Expand the user personas section with more detail on enterprise users. Add GDPR requirements to Section 4."',
              alignLabelWithHint: true,
              contentPadding: EdgeInsets.all(14),
            ),
          ),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting || _ctrl.text.trim().isEmpty
                  ? null
                  : () {
                      setState(() => _submitting = true);
                      widget.onSubmit(_ctrl.text.trim());
                    },
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded,
                      size: 18),
              label: Text(_submitting
                  ? 'Submitting…'
                  : 'Update PRD with AI'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PRD Version Screen ────────────────────────────────────────────────────────

class _PrdVersionScreen extends StatelessWidget {
  final PrdVersion version;
  final bool isCurrent;

  const _PrdVersionScreen(
      {required this.version, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final sections = _parsePrdSections(version.prdMarkdown);
    final hasChanges = version.changedSections.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${version.versionNumber}${isCurrent ? ' (Current)' : ''}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (hasChanges)
              Text(
                '${version.changedSections.length} section${version.changedSections.length == 1 ? '' : 's'} changed',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFFF8F00)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy PRD',
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: version.prdMarkdown));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('PRD copied to clipboard')));
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (hasChanges)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F00)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFF8F00)
                          .withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.edit_note_rounded,
                          size: 16, color: Color(0xFFFF8F00)),
                      Gap(6),
                      Text('Changed Sections',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFFFF8F00))),
                    ]),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: version.changedSections
                          .map((s) => Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8F00)
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(s,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w500,
                                        color:
                                            Color(0xFFFF8F00))),
                              ))
                          .toList(),
                    ),
                    if (version.reviewerComment != null) ...[
                      const Gap(8),
                      const Divider(height: 1),
                      const Gap(8),
                      Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment_outlined,
                                size: 14,
                                color: Color(0xFF6B7A8D)),
                            const Gap(6),
                            Expanded(
                              child: Text(
                                  version.reviewerComment!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7A8D),
                                      fontStyle:
                                          FontStyle.italic)),
                            ),
                          ]),
                    ],
                  ],
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final section = sections[i];
                final isChanged = hasChanges &&
                    _sectionIsChanged(
                        section.heading, version.changedSections);
                final headingPrefix = '#' * section.level;
                final md =
                    '$headingPrefix ${section.heading}\n\n${section.content}';
                final mdStyle = MarkdownStyleSheet(
                  h1: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  h2: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kPrimary),
                  h3: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                  p: const TextStyle(fontSize: 14, height: 1.5),
                  tableHead: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                  tableBody: const TextStyle(fontSize: 13),
                );

                if (isChanged) {
                  return Container(
                    margin:
                        const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    decoration: const BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: Color(0xFFFF8F00),
                              width: 3)),
                    ),
                    child: Stack(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            12, 8, 8, 8),
                        child: MarkdownBody(
                            data: md,
                            selectable: true,
                            styleSheet: mdStyle),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8F00)
                                .withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(4),
                          ),
                          child: const Text('Changed',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF8F00))),
                        ),
                      ),
                    ]),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: MarkdownBody(
                      data: md,
                      selectable: true,
                      styleSheet: mdStyle),
                );
              },
              childCount: sections.length,
            ),
          ),
          const SliverToBoxAdapter(child: Gap(32)),
        ],
      ),
    );
  }
}
