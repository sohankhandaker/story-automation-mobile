import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../theme/sera_tokens.dart';
import '../core/api.dart';
import '../models/user.dart';
import 'shared_widgets.dart';
import '../providers/auth_provider.dart';
import 'prd_screen.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

// Phases 1-2 are prep (crawl + analyze), phases 3-9 map to BRD phases 1-7
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

const _brdPhaseNames = [
  '',
  'Crawling Links & Extracting Context',
  'Analyzing Notes & Building Requirements',
  'Document Control & Executive Summary',
  'Business Context, Vision & Objectives',
  'Product Scope, Capability Map & Value Chain',
  'Stakeholders, Personas & Governance',
  'Business Processes & Functional Requirements',
  'Non-Functional Requirements, Data & Integrations',
  'KPIs, Roadmap & MVP Scope',
  'Risks, Acceptance Criteria & Checklists',
];

const _statusColors = {
  'Draft': SeraTokens.statusDraft,
  'In Progress': SeraTokens.statusInProgress,
  'Pending Review': SeraTokens.statusPendingReview,
  'In Review': SeraTokens.statusInReview,
  'Changes Requested': SeraTokens.statusChanges,
  'Approved': SeraTokens.statusApproved,
};

// ── Models ────────────────────────────────────────────────────────────────────

class ReviewerStatus {
  final String githubUsername;
  final String? name;
  final String status; // Pending | Approved

  ReviewerStatus({required this.githubUsername, this.name, required this.status});

  factory ReviewerStatus.fromJson(Map<String, dynamic> j) => ReviewerStatus(
        githubUsername: j['github_username'] as String,
        name: j['name'] as String?,
        status: (j['status'] as String?) ?? 'Pending',
      );
}

class MeetingNote {
  final String id;
  final String? projectId;
  final String? title;
  final String noteType;
  final String rawNotes;
  final String? wikiUrl;
  final String? brdDraft;
  final int? brdGenerationPhase;
  final String status;
  final int currentVersionNumber;
  final String? githubIssueUrl;
  final int? githubIssueNumber;
  final String? reviewerGithubUsername;
  final String? reviewerName;
  final List<ReviewerStatus> reviewers;
  final String? githubFileUrl;
  final String? githubFileRawUrl;
  // Change Request planner document
  final String? plannerDocContent;
  final String? plannerDocUrl;
  // PRD info — set in project notes list responses
  final String? prdStatus;
  final int? prdVersionNumber;
  final String? prdFileUrl;
  final String? prdFileRawUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  MeetingNote.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        projectId = j['project_id'] as String?,
        title = j['title'] as String?,
        noteType = (j['note_type'] as String?) ?? 'note',
        rawNotes = j['raw_notes'] as String,
        wikiUrl = j['wiki_url'] as String?,
        brdDraft = j['brd_draft'] as String?,
        brdGenerationPhase = j['brd_generation_phase'] as int?,
        status = (j['status'] as String?) ?? 'Draft',
        currentVersionNumber = (j['current_version_number'] as int?) ?? 0,
        githubIssueUrl = j['github_issue_url'] as String?,
        githubIssueNumber = j['github_issue_number'] as int?,
        reviewerGithubUsername = j['reviewer_github_username'] as String?,
        reviewerName = j['reviewer_name'] as String?,
        reviewers = (j['reviewers'] as List<dynamic>? ?? [])
            .map((r) => ReviewerStatus.fromJson(r as Map<String, dynamic>))
            .toList(),
        githubFileUrl = j['github_file_url'] as String?,
        githubFileRawUrl = j['github_file_raw_url'] as String?,
        plannerDocContent = j['planner_doc_content'] as String?,
        plannerDocUrl = j['planner_doc_url'] as String?,
        prdStatus = j['prd_status'] as String?,
        prdVersionNumber = j['prd_version_number'] as int?,
        prdFileUrl = j['prd_file_url'] as String?,
        prdFileRawUrl = j['prd_file_raw_url'] as String?,
        createdAt = DateTime.parse(j['created_at'] as String),
        updatedAt = DateTime.parse(
            (j['updated_at'] ?? j['created_at']) as String);
}

class NoteEntry {
  final String id;
  final String noteId;
  final String content;
  final DateTime createdAt;

  NoteEntry.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        noteId = j['note_id'] as String,
        content = j['content'] as String,
        createdAt = DateTime.parse(j['created_at'] as String);
}

class BrdVersion {
  final String id;
  final String noteId;
  final int versionNumber;
  final String brdMarkdown;
  final String? changeSummary;
  final List<String> changedSections;
  final String? reviewerComment;
  final DateTime createdAt;

  BrdVersion.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        noteId = j['note_id'] as String,
        versionNumber = j['version_number'] as int,
        brdMarkdown = j['brd_markdown'] as String,
        changeSummary = j['change_summary'] as String?,
        changedSections = List<String>.from(j['changed_sections'] ?? []),
        reviewerComment = j['reviewer_comment'] as String?,
        createdAt = DateTime.parse(j['created_at'] as String);
}

class _BrdSection {
  final String heading;
  final int level;
  final String content;
  _BrdSection({required this.heading, required this.level, required this.content});
}

// ── Section parser ────────────────────────────────────────────────────────────

List<_BrdSection> _parseBrdSections(String markdown) {
  final sections = <_BrdSection>[];
  final lines = markdown.split('\n');
  String currentHeading = '';
  int currentLevel = 0;
  final buffer = StringBuffer();

  void flush() {
    if (currentHeading.isNotEmpty || buffer.isNotEmpty) {
      sections.add(_BrdSection(
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

// ── Attachment helper ─────────────────────────────────────────────────────────

class _AttachedFile {
  final String name;
  final Uint8List bytes;
  final bool isImage;
  const _AttachedFile(
      {required this.name, required this.bytes, required this.isImage});
}

// ── Provider ──────────────────────────────────────────────────────────────────

class NotesNotifier extends StateNotifier<AsyncValue<List<MeetingNote>>> {
  NotesNotifier() : super(const AsyncValue.loading()) {
    fetchNotes();
  }

  Future<void> fetchNotes() async {
    state = const AsyncValue.loading();
    try {
      final resp = await ApiClient.dio.get('/api/notes');
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
      final resp = await ApiClient.dio.post('/api/notes', data: {
        'raw_notes': rawNotes,
        if (wikiUrl != null && wikiUrl.isNotEmpty) 'wiki_url': wikiUrl,
      });
      final note = MeetingNote.fromJson(resp.data as Map<String, dynamic>);
      await fetchNotes();
      return note;
    } catch (_) {
      return null;
    }
  }

  Future<MeetingNote?> addEntry(String noteId, String content,
      {String? wikiUrl}) async {
    try {
      final resp = await ApiClient.dio.post(
        '/api/notes/$noteId/entries',
        data: {
          'content': content,
          if (wikiUrl != null) 'wiki_url': wikiUrl,
        },
      );
      final note = MeetingNote.fromJson(resp.data as Map<String, dynamic>);
      await fetchNotes();
      return note;
    } catch (_) {
      return null;
    }
  }

  Future<MeetingNote?> markReady(String noteId) async {
    try {
      final resp = await ApiClient.dio.post('/api/notes/$noteId/mark-ready');
      final note = MeetingNote.fromJson(resp.data as Map<String, dynamic>);
      await fetchNotes();
      return note;
    } catch (_) {
      return null;
    }
  }

  Future<MeetingNote?> assignReviewer(
      String noteId, String reviewerUsername, String? reviewerName) async {
    try {
      final resp = await ApiClient.dio.post(
        '/api/notes/$noteId/assign-reviewer',
        data: {
          'reviewer_github_username': reviewerUsername,
          if (reviewerName != null && reviewerName.isNotEmpty)
            'reviewer_name': reviewerName,
        },
      );
      final note = MeetingNote.fromJson(resp.data as Map<String, dynamic>);
      await fetchNotes();
      return note;
    } catch (_) {
      return null;
    }
  }

  Future<MeetingNote?> pollNote(String noteId) async {
    try {
      final resp = await ApiClient.dio.get('/api/notes/$noteId');
      return MeetingNote.fromJson(resp.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<MeetingNote?> submitFeedback(String noteId, String feedback) async {
    try {
      final resp = await ApiClient.dio.post(
        '/api/notes/$noteId/feedback',
        data: {'feedback': feedback},
      );
      return MeetingNote.fromJson(resp.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<List<NoteEntry>> fetchEntries(String noteId) async {
    try {
      final resp = await ApiClient.dio.get('/api/notes/$noteId/entries');
      return (resp.data['entries'] as List)
          .map((j) => NoteEntry.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<BrdVersion>> fetchVersions(String noteId) async {
    try {
      final resp = await ApiClient.dio.get('/api/notes/$noteId/versions');
      return (resp.data['versions'] as List)
          .map((j) => BrdVersion.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteNote(String noteId) async {
    try {
      await ApiClient.dio.delete('/api/notes/$noteId');
      await fetchNotes();
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      throw Exception(detail ?? 'Failed to delete note');
    }
  }

  Future<void> uploadAttachments(
      String noteId, List<({String name, Uint8List bytes})> files) async {
    for (final f in files) {
      try {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(f.bytes, filename: f.name),
        });
        await ApiClient.dio.post('/api/notes/$noteId/attachments', data: form);
      } catch (_) {}
    }
  }
}

final notesProvider =
    StateNotifierProvider<NotesNotifier, AsyncValue<List<MeetingNote>>>(
  (_) => NotesNotifier(),
);

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  final int? version;
  const _StatusChip(this.status, {this.version});

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? SeraTokens.statusDraft;
    final label = version != null ? 'v$version · $status' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Notes Tab (list) ──────────────────────────────────────────────────────────

class NotesTab extends ConsumerWidget {
  const NotesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const Gap(12),
            Text('$e'),
            TextButton(
              onPressed: () => ref.read(notesProvider.notifier).fetchNotes(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (notes) {
        if (notes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                      color: kPrimaryLight, shape: BoxShape.circle),
                  child: const Icon(Icons.note_alt_outlined,
                      size: 48, color: kPrimary),
                ),
                const Gap(16),
                const Text('No meeting notes yet',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Gap(6),
                const Text('Tap + New Meeting Note to get started',
                    style: TextStyle(
                        color: SeraTokens.fg3, fontSize: 14)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(notesProvider.notifier).fetchNotes(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: notes.length,
            itemBuilder: (_, i) => NoteCard(note: notes[i]),
          ),
        );
      },
    );
  }
}

class NoteCard extends ConsumerWidget {
  final MeetingNote note;
  const NoteCard({super.key, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isWorking =
        note.brdGenerationPhase != null || note.status == 'In Progress';
    final isDone = note.brdDraft != null && !isWorking;
    final isCR = note.noteType == 'change_request';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => NoteDetailScreen(note: note)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCR
                      ? SeraTokens.statusInProgressWarm.withValues(alpha: 0.12)
                      : isDone
                          ? SeraTokens.statusApproved.withValues(alpha: 0.12)
                          : kPrimaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCR
                      ? Icons.change_circle_outlined
                      : isDone
                          ? Icons.description_rounded
                          : isWorking
                              ? Icons.hourglass_top_rounded
                              : Icons.note_alt_outlined,
                  color: isCR
                      ? SeraTokens.statusInProgressWarm
                      : isDone ? SeraTokens.statusApproved : kPrimary,
                  size: 22,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isCR) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SeraTokens.statusInProgressWarm.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Change Request',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: SeraTokens.statusInProgressWarm,
                              ),
                            ),
                          ),
                          const Gap(6),
                        ],
                        Expanded(
                          child: Text(
                            note.title ?? 'Processing…',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Gap(4),
                    Row(
                      children: [
                        Text(
                          isWorking
                              ? (note.brdGenerationPhase == 0
                                  ? 'Updating BRD…'
                                  : note.brdGenerationPhase != null
                                      ? 'Generating… phase ${note.brdGenerationPhase}'
                                      : 'Starting pipeline…')
                              : isDone
                                  ? 'v${note.currentVersionNumber} · BRD ready'
                                  : 'Draft · add notes then mark ready',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDone
                                ? SeraTokens.statusApproved
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isDone) ...[
                          const Gap(6),
                          _StatusChip(note.status),
                        ],
                        if (note.githubIssueUrl != null) ...[
                          const Gap(4),
                          const Icon(Icons.link_rounded,
                              size: 14, color: kPrimary),
                        ],
                      ],
                    ),
                    const Gap(2),
                    Text(
                      _formatDate(note.createdAt),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: Color(0xFFB0BEC5)),
                onPressed: () => _confirmDelete(context, ref),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text(
            'This will permanently delete this meeting note and all its BRD versions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(notesProvider.notifier).deleteNote(note.id);
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

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── New Note Sheet ────────────────────────────────────────────────────────────

class NewNoteSheet extends ConsumerStatefulWidget {
  const NewNoteSheet({super.key});

  @override
  ConsumerState<NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends ConsumerState<NewNoteSheet> {
  final _notesCtrl = TextEditingController();
  final _wikiCtrl = TextEditingController();
  final _stt = SpeechToText();
  final _imagePicker = ImagePicker();

  bool _sttAvailable = false;
  bool _listening = false;
  bool _submitting = false;
  String _sttStatus = '';
  String _partialText = '';
  final List<_AttachedFile> _attachments = [];
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
      onError: (e) {
        if (mounted) {
          setState(() {
            _listening = false;
            _sttStatus = '';
            _partialText = '';
          });
        }
      },
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() {
        _listening = false;
        _sttStatus = '';
        _partialText = '';
      });
      return;
    }
    setState(() {
      _listening = true;
      _sttStatus = 'Listening…';
      _partialText = '';
    });
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          final base = _notesCtrl.text;
          final appended = base.isEmpty
              ? result.recognizedWords
              : '$base ${result.recognizedWords}';
          setState(() {
            _notesCtrl.text = appended;
            _notesCtrl.selection =
                TextSelection.collapsed(offset: appended.length);
            _listening = false;
            _sttStatus = '';
            _partialText = '';
          });
        } else {
          setState(() => _partialText = result.recognizedWords);
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
    final source = await _showImageSourceDialog();
    if (source == null) return;
    final picked = await _imagePicker.pickImage(
        source: source, imageQuality: 80, maxWidth: 1920);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _attachments
        .add(_AttachedFile(name: picked.name, bytes: bytes, isImage: true)));
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
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
        .add(_AttachedFile(name: f.name, bytes: f.bytes!, isImage: false)));
  }

  Future<void> _submit() async {
    final notes = _notesCtrl.text.trim();
    if (notes.isEmpty) return;
    // flush any URL typed but not yet added
    if (_wikiCtrl.text.trim().isNotEmpty) _addWikiUrl();
    setState(() => _submitting = true);
    final notifier = ref.read(notesProvider.notifier);
    final note = await notifier.createNote(
      notes,
      _wikiUrls.isEmpty ? null : _wikiUrls.join('\n'),
    );
    if (note != null && _attachments.isNotEmpty) {
      await notifier.uploadAttachments(
        note.id,
        _attachments.map((a) => (name: a.name, bytes: a.bytes)).toList(),
      );
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pop();
    if (note != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NoteDetailScreen(note: note),
      ));
    }
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
                  color: kPrimaryLight,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.note_add_rounded,
                  color: kPrimary, size: 20),
            ),
            const Gap(10),
            const Text('New Meeting Note',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ]),
          const Gap(16),
          Stack(children: [
            TextField(
              controller: _notesCtrl,
              maxLines: 7,
              decoration: const InputDecoration(
                hintText:
                    'Paste or type your raw meeting notes here…\nOr use the mic to dictate.',
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.fromLTRB(14, 14, 50, 14),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Column(children: [
                IconButton(
                  tooltip: 'Paste',
                  icon:
                      const Icon(Icons.content_paste_rounded, size: 20),
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
                if (_sttAvailable)
                  IconButton(
                    tooltip: _listening ? 'Stop' : 'Dictate',
                    icon: Icon(
                      _listening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
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
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const Gap(8),
              Expanded(
                child: Text(
                  _partialText.isNotEmpty ? _partialText : _sttStatus,
                  style: const TextStyle(
                      fontSize: 12, color: SeraTokens.fg3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
          const Gap(10),
          // ── Attach row ─────────────────────────────────────────────────
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_rounded, size: 16),
              label: const Text('Image'),
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
            const Gap(8),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: const Text('File'),
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              spacing: 6,
              runSpacing: 4,
              children: _attachments.map((a) {
                return Chip(
                  avatar: Icon(
                    a.isImage
                        ? Icons.image_rounded
                        : Icons.insert_drive_file_rounded,
                    size: 14,
                  ),
                  label: Text(a.name,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() => _attachments.remove(a)),
                );
              }).toList(),
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
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_submitting ? 'Saving…' : 'Save Notes'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add More Notes Sheet ──────────────────────────────────────────────────────

class _AddMoreNotesSheet extends ConsumerStatefulWidget {
  final String noteId;
  final String? initialWikiUrl;
  final void Function(MeetingNote updated) onAdded;

  const _AddMoreNotesSheet(
      {required this.noteId, this.initialWikiUrl, required this.onAdded});

  @override
  ConsumerState<_AddMoreNotesSheet> createState() =>
      _AddMoreNotesSheetState();
}

class _AddMoreNotesSheetState
    extends ConsumerState<_AddMoreNotesSheet> {
  final _ctrl = TextEditingController();
  final _wikiCtrl = TextEditingController();
  final _stt = SpeechToText();
  final _imagePicker = ImagePicker();
  bool _sttAvailable = false;
  bool _listening = false;
  bool _submitting = false;
  String _partialText = '';
  final List<_AttachedFile> _attachments = [];
  late final List<String> _wikiUrls;

  void _addWikiUrl() {
    final url = _wikiCtrl.text.trim();
    if (url.isEmpty) return;
    if (!_wikiUrls.contains(url)) setState(() => _wikiUrls.add(url));
    _wikiCtrl.clear();
  }

  @override
  void initState() {
    super.initState();
    // Seed existing URLs from the note's wiki_url (newline-separated)
    final existing = widget.initialWikiUrl ?? '';
    _wikiUrls = existing.isEmpty
        ? []
        : existing.split('\n').where((u) => u.isNotEmpty).toList();
    _ctrl.addListener(() { if (mounted) setState(() {}); });
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
        if (mounted) {
          setState(() {
            _listening = false;
            _partialText = '';
          });
        }
      },
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() {
        _listening = false;
        _partialText = '';
      });
      return;
    }
    setState(() {
      _listening = true;
      _partialText = '';
    });
    await _stt.listen(
      onResult: (r) {
        if (r.finalResult) {
          final cur = _ctrl.text;
          final app =
              cur.isEmpty ? r.recognizedWords : '$cur ${r.recognizedWords}';
          setState(() {
            _ctrl.text = app;
            _ctrl.selection = TextSelection.collapsed(offset: app.length);
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
        .add(_AttachedFile(name: picked.name, bytes: bytes, isImage: true)));
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
        .add(_AttachedFile(name: f.name, bytes: f.bytes!, isImage: false)));
  }

  @override
  void dispose() {
    _stt.stop();
    _ctrl.dispose();
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
                  color: kPrimaryLight,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add_comment_rounded,
                  color: kPrimary, size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add More Notes',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(
                      'AI will incorporate this context into the BRD',
                      style: TextStyle(
                          fontSize: 12, color: SeraTokens.fg3)),
                ],
              ),
            ),
          ]),
          const Gap(16),
          Stack(children: [
            TextField(
              controller: _ctrl,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText:
                    'Add additional requirements, decisions, constraints…',
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.fromLTRB(14, 14, 50, 14),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Column(children: [
                IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  onPressed: () async {
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _ctrl.text = data!.text!.trim();
                      _ctrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _ctrl.text.length));
                    }
                  },
                ),
                if (_sttAvailable)
                  IconButton(
                    tooltip: _listening ? 'Stop' : 'Dictate',
                    icon: Icon(
                      _listening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
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
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const Gap(8),
              Expanded(
                child: Text(
                  _partialText.isNotEmpty ? _partialText : 'Listening…',
                  style: const TextStyle(
                      fontSize: 12, color: SeraTokens.fg3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
          const Gap(10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_rounded, size: 16),
              label: const Text('Image'),
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
            const Gap(8),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: const Text('File'),
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              spacing: 6,
              runSpacing: 4,
              children: _attachments.map((a) {
                return Chip(
                  avatar: Icon(
                    a.isImage
                        ? Icons.image_rounded
                        : Icons.insert_drive_file_rounded,
                    size: 14,
                  ),
                  label: Text(a.name,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() => _attachments.remove(a)),
                );
              }).toList(),
            ),
          ],
          const Gap(10),
          WikiUrlInput(
            controller: _wikiCtrl,
            urls: _wikiUrls,
            onAdd: _addWikiUrl,
            onRemove: (url) => setState(() => _wikiUrls.remove(url)),
          ),
          const Gap(12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting || _ctrl.text.trim().isEmpty
                  ? null
                  : () async {
                      if (_wikiCtrl.text.trim().isNotEmpty) _addWikiUrl();
                      setState(() => _submitting = true);
                      final navigator = Navigator.of(context);
                      final notifier = ref.read(notesProvider.notifier);
                      final updated = await notifier.addEntry(
                        widget.noteId,
                        _ctrl.text.trim(),
                        wikiUrl: _wikiUrls.isEmpty ? null : _wikiUrls.join('\n'),
                      );
                      if (updated != null && _attachments.isNotEmpty) {
                        await notifier.uploadAttachments(
                          widget.noteId,
                          _attachments
                              .map((a) => (name: a.name, bytes: a.bytes))
                              .toList(),
                        );
                      }
                      if (!mounted) return;
                      navigator.pop();
                      if (updated != null) {
                        widget.onAdded(updated);
                      }
                    },
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.note_add_rounded, size: 18),
              label: Text(_submitting ? 'Saving…' : 'Add Note'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mark as Ready Sheet ───────────────────────────────────────────────────────
// Simplified: no reviewer selection here — that happens after BRD is generated.

class _MarkReadySheet extends ConsumerStatefulWidget {
  final MeetingNote note;
  final void Function(MeetingNote updated) onMarked;

  const _MarkReadySheet({required this.note, required this.onMarked});

  @override
  ConsumerState<_MarkReadySheet> createState() => _MarkReadySheetState();
}

class _MarkReadySheetState extends ConsumerState<_MarkReadySheet> {
  bool _submitting = false;
  String? _error;

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
                  color: SeraTokens.statusInProgress.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.rocket_launch_rounded,
                  color: SeraTokens.statusInProgress, size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start BRD Generation',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  Text('Creates a GitHub ticket and generates the full BRD',
                      style:
                          TextStyle(fontSize: 12, color: SeraTokens.fg3)),
                ],
              ),
            ),
          ]),
          const Gap(20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What happens:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: kPrimary)),
                const Gap(6),
                ...[
                  '🔗 GitHub ticket created, board moved to In Progress',
                  '🤖 Agent analyzes all your notes + crawls any links',
                  '📄 Full BRD generated in 7 phases (~2 min)',
                  '👤 You assign a reviewer once the BRD is ready',
                  '✅ Reviewer approves via GitHub — board moves to Done',
                ].map((s) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 12, color: kPrimary)),
                    )),
              ],
            ),
          ),
          if (_error != null) ...[
            const Gap(12),
            Text(_error!,
                style: const TextStyle(
                    fontSize: 12, color: SeraTokens.statusChanges)),
          ],
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: SeraTokens.statusInProgress),
              onPressed: _submitting
                  ? null
                  : () async {
                      setState(() {
                        _submitting = true;
                        _error = null;
                      });
                      final navigator = Navigator.of(context);
                      final updated = await ref
                          .read(notesProvider.notifier)
                          .markReady(widget.note.id);
                      if (!mounted) return;
                      if (updated != null) {
                        navigator.pop();
                        widget.onMarked(updated);
                      } else {
                        setState(() {
                          _submitting = false;
                          _error =
                              'Failed to create GitHub issue. Check your GitHub config in Settings.';
                        });
                      }
                    },
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(_submitting
                  ? 'Creating GitHub ticket…'
                  : 'Start BRD Generation'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Assign Reviewer Sheet ─────────────────────────────────────────────────────

class _AssignReviewerSheet extends ConsumerStatefulWidget {
  final MeetingNote note;
  final void Function(MeetingNote updated) onAssigned;

  const _AssignReviewerSheet(
      {required this.note, required this.onAssigned});

  @override
  ConsumerState<_AssignReviewerSheet> createState() =>
      _AssignReviewerSheetState();
}

class _AssignReviewerSheetState
    extends ConsumerState<_AssignReviewerSheet> {
  ReviewerItem? _selected;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final reviewers = ref.read(authProvider).user?.reviewerList ?? [];

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
                  color: SeraTokens.statusPendingReview.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_add_rounded,
                  color: SeraTokens.statusPendingReview, size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assign Reviewer',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(
                      'Reviewer will be notified on GitHub to review the BRD',
                      style:
                          TextStyle(fontSize: 12, color: SeraTokens.fg3)),
                ],
              ),
            ),
          ]),
          const Gap(20),
          const Text('Select Reviewer',
              style:
                  TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                    style: TextStyle(fontSize: 12, color: Colors.orange),
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
                                  color: SeraTokens.fg3)),
                          contentPadding: EdgeInsets.zero,
                          activeColor: SeraTokens.statusPendingReview,
                        ))
                    .toList(),
              ),
            ),
          if (_error != null) ...[
            const Gap(8),
            Text(_error!,
                style: const TextStyle(
                    fontSize: 12, color: SeraTokens.statusChanges)),
          ],
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: SeraTokens.statusPendingReview),
              onPressed: _submitting || _selected == null
                  ? null
                  : () async {
                      setState(() {
                        _submitting = true;
                        _error = null;
                      });
                      final navigator = Navigator.of(context);
                      final updated = await ref
                          .read(notesProvider.notifier)
                          .assignReviewer(
                            widget.note.id,
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
                          _error = 'Failed to assign reviewer. Try again.';
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

// ── Request Update Sheet ──────────────────────────────────────────────────────

class _RequestUpdateSheet extends StatefulWidget {
  final String noteId;
  final void Function(String feedback) onSubmit;

  const _RequestUpdateSheet(
      {required this.noteId, required this.onSubmit});

  @override
  State<_RequestUpdateSheet> createState() =>
      _RequestUpdateSheetState();
}

class _RequestUpdateSheetState extends State<_RequestUpdateSheet> {
  final _ctrl = TextEditingController();
  final _wikiCtrl = TextEditingController();
  final List<String> _wikiUrls = [];
  bool _submitting = false;

  void _addWikiUrl() {
    final url = _wikiCtrl.text.trim();
    if (url.isEmpty) return;
    if (!_wikiUrls.contains(url)) setState(() => _wikiUrls.add(url));
    _wikiCtrl.clear();
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
                  color:
                      SeraTokens.statusChanges.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_note_rounded,
                  color: SeraTokens.statusChanges, size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Request BRD Update',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                  Text('AI updates only the affected sections',
                      style: TextStyle(
                          fontSize: 12, color: SeraTokens.fg3)),
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
                  'Describe what needs to change…\n\nExample: "Add GDPR compliance to Section 14. Expand KPI targets to include NPS."',
              alignLabelWithHint: true,
              contentPadding: EdgeInsets.all(14),
            ),
          ),
          const Gap(12),
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
              onPressed: _submitting || _ctrl.text.trim().isEmpty
                  ? null
                  : () {
                      if (_wikiCtrl.text.trim().isNotEmpty) _addWikiUrl();
                      setState(() => _submitting = true);
                      final feedback = _wikiUrls.isEmpty
                          ? _ctrl.text.trim()
                          : '${_ctrl.text.trim()}\n\nAdditional context URLs:\n${_wikiUrls.map((u) => '- $u').join('\n')}';
                      widget.onSubmit(feedback);
                    },
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_submitting
                  ? 'Submitting…'
                  : 'Update BRD with AI'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Note Detail Screen ────────────────────────────────────────────────────────

class NoteDetailScreen extends ConsumerStatefulWidget {
  final MeetingNote note;

  const NoteDetailScreen({super.key, required this.note});

  @override
  ConsumerState<NoteDetailScreen> createState() =>
      NoteDetailScreenState();
}

class NoteDetailScreenState extends ConsumerState<NoteDetailScreen>
    with TickerProviderStateMixin {
  late MeetingNote _note;
  Timer? _pollTimer;
  TabController? _tabController;
  int _entryVersion = 0;

  // ── Pipeline phase ────────────────────────────────────────────────────────
  String _phase = 'brd'; // 'brd' | 'prd'
  PrdDocument? _prd;
  bool _prdLoading = false; // true while fetching PRD from backend
  Timer? _prdPollTimer;
  TabController? _prdTabController;

  // ── BRD getters ───────────────────────────────────────────────────────────
  bool get _isDraft =>
      _note.status == 'Draft' && _note.brdGenerationPhase == null;
  bool get _isWorking =>
      _note.brdGenerationPhase != null || _note.status == 'In Progress';
  bool get _brdReady => _note.brdDraft != null && !_isWorking;
  bool get _shouldPoll =>
      _isWorking ||
      _note.status == 'In Review' ||
      _note.status == 'Changes Requested';

  // ── PRD getters ───────────────────────────────────────────────────────────
  bool get _prdIsWorking =>
      _prd != null &&
      (_prd!.prdGenerationPhase != null || _prd!.status == 'In Progress');
  bool get _prdReady => _prd != null && _prd!.prdDraft != null && !_prdIsWorking;
  bool get _prdShouldPoll =>
      _prd != null &&
      (_prdIsWorking ||
          _prd!.status == 'In Review' ||
          _prd!.status == 'Changes Requested');

  // Show pipeline stepper once BRD is approved or PRD has started
  bool get _showPipeline =>
      _note.status == 'Approved' || _prd != null;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    if (_brdReady) _initTabs();
    if (_shouldPoll) _startPolling();
    if (_note.status == 'Approved') {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fetchAndInitPrd());
    }
    // Always fetch fresh state from server on open — widget.note may be stale
    // if the user navigated away during generation and the provider wasn't refreshed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOnOpen());
  }

  Future<void> _refreshOnOpen() async {
    final updated =
        await ref.read(notesProvider.notifier).pollNote(_note.id);
    if (updated == null || !mounted) return;
    setState(() {
      _note = updated;
      if (_brdReady && _tabController == null) _initTabs();
    });
    // Start polling if the note is now in a working / review state
    // and polling hasn't already been started from initState.
    if (_shouldPoll && _pollTimer == null) _startPolling();
    // Load PRD if note just became approved and we didn't already start.
    if (updated.status == 'Approved' && _prd == null) _fetchAndInitPrd();
  }

  void _initTabs() {
    _tabController?.dispose();
    _tabController = TabController(length: 3, vsync: this);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final updated =
          await ref.read(notesProvider.notifier).pollNote(_note.id);
      if (updated != null && mounted) {
        final wasWorking = _isWorking;
        setState(() {
          _note = updated;
          if (_brdReady && _tabController == null) _initTabs();
        });
        // Stop polling when generation finishes or note is approved
        if ((wasWorking && !_isWorking) || updated.status == 'Approved') {
          _pollTimer?.cancel();
          ref.read(notesProvider.notifier).fetchNotes();
          // BRD just became approved — fetch PRD immediately and auto-switch
          if (updated.status == 'Approved' && _prd == null) {
            _fetchAndInitPrd();
          }
        }
      }
    });
  }

  void _openMarkReady() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MarkReadySheet(
        note: _note,
        onMarked: (updated) {
          setState(() => _note = updated);
          _startPolling(); // pipeline is now running
        },
      ),
    );
  }

  void _openAssignReviewer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignReviewerSheet(
        note: _note,
        onAssigned: (updated) {
          setState(() => _note = updated);
          _startPolling(); // poll for reviewer comments
        },
      ),
    );
  }

  void _openAddMoreNotes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMoreNotesSheet(
        noteId: _note.id,
        initialWikiUrl: _note.wikiUrl,
        onAdded: (updated) => setState(() {
          _note = updated;
          _entryVersion++;
        }),
      ),
    );
  }

  void _openRequestUpdate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestUpdateSheet(
        noteId: _note.id,
        onSubmit: (feedback) async {
          Navigator.pop(context);
          final updated = await ref
              .read(notesProvider.notifier)
              .submitFeedback(_note.id, feedback);
          if (updated != null && mounted) {
            setState(() => _note = updated);
            _startPolling();
          }
        },
      ),
    );
  }

  // ── PRD phase methods ─────────────────────────────────────────────────────

  void _initPrdTabs() {
    _prdTabController?.dispose();
    _prdTabController = TabController(length: 2, vsync: this);
  }

  Future<void> _fetchAndInitPrd() async {
    if (!mounted || _prdLoading) return; // guard against concurrent calls
    setState(() => _prdLoading = true);
    try {
      await ref.read(prdProvider(_note.id).notifier).fetchPrd(_note.id);
      if (!mounted) return;
      final prd = ref.read(prdProvider(_note.id)).valueOrNull;
      setState(() {
        _prdLoading = false;
        _prd = prd;
        if (_prdReady && _prdTabController == null) _initPrdTabs();
        // Auto-advance to PRD phase whenever PRD exists and has started
        if (prd != null && prd.status != 'Draft') {
          _phase = 'prd';
        }
      });
      if (_prdShouldPoll) _startPrdPolling();
    } catch (e) {
      if (mounted) setState(() => _prdLoading = false);
    }
  }

  void _startPrdPolling() {
    _prdPollTimer?.cancel();
    _prdPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final updated = await ref
          .read(prdProvider(_note.id).notifier)
          .pollPrd(_note.id);
      if (updated != null && mounted) {
        final wasWorking = _prdIsWorking;
        setState(() {
          _prd = updated;
          if (_prdReady && _prdTabController == null) _initPrdTabs();
        });
        if (wasWorking && !_prdIsWorking) {
          _prdPollTimer?.cancel();
        }
      }
    });
  }

  Future<void> _generatePrd() async {
    final updated = await ref
        .read(prdProvider(_note.id).notifier)
        .generatePrd(_note.id);
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _prd = updated;
        _phase = 'prd';
      });
      _startPrdPolling();
    }
  }

  void _openPrdAssignReviewer() {
    if (_prd == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrdAssignReviewerSheetInline(
        prd: _prd!,
        noteId: _note.id,
        onAssigned: (updated) {
          setState(() => _prd = updated);
          _startPrdPolling();
        },
      ),
    );
  }

  void _openPrdRequestUpdate() {
    if (_prd == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrdUpdateSheetInline(
        noteId: _note.id,
        onSubmit: (feedback) async {
          Navigator.pop(context);
          final updated = await ref
              .read(prdProvider(_note.id).notifier)
              .submitFeedback(_note.id, feedback);
          if (updated != null && mounted) {
            setState(() => _prd = updated);
            _startPrdPolling();
          }
        },
      ),
    );
  }

  Future<void> _sendToPlanner() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    if (ok != true) return;
    final updated = await ref
        .read(prdProvider(_note.id).notifier)
        .sendToPlanner(_note.id);
    if (updated != null && mounted) setState(() => _prd = updated);
  }


  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController?.dispose();
    _prdPollTimer?.cancel();
    _prdTabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isDraft
          ? _buildDraftBody()
          : _isWorking
              ? _buildLoadingBody()
              : _phase == 'prd'
                  ? _buildPrdBody()
                  : _buildReadyBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    Widget titleWidget;

    if (_isDraft) {
      final t = _note.title == 'New Note' ? 'Meeting Notes' : (_note.title ?? 'Meeting Notes');
      titleWidget = Text(t,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          overflow: TextOverflow.ellipsis);
    } else if (_isWorking) {
      titleWidget = const Text('Generating BRD…',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
    } else if (_phase == 'prd' && _prdIsWorking) {
      titleWidget = const Text('Generating PRD…',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
    } else if (_phase == 'prd' && _prd != null) {
      titleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_note.title ?? 'PRD',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis),
          Text('PRD · v${_prd!.currentVersionNumber} · ${_prd!.status}',
              style: const TextStyle(fontSize: 11, color: SeraTokens.muted)),
        ],
      );
    } else {
      titleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_note.title ?? 'BRD',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis),
          Text('BRD · v${_note.currentVersionNumber} · ${_note.status}',
              style: const TextStyle(fontSize: 11, color: SeraTokens.muted)),
        ],
      );
    }

    return AppBar(
      title: titleWidget,
      actions: [
        // Mark as Ready — Draft state
        if (_isDraft)
          IconButton(
            icon: const Icon(Icons.rocket_launch_rounded, color: SeraTokens.statusInProgress),
            tooltip: 'Start BRD Generation',
            onPressed: _openMarkReady,
          ),

        // ── BRD phase actions ─────────────────────────────────────────────
        if (_brdReady && _phase == 'brd') ...[
          _StatusChip(_note.status, version: _note.currentVersionNumber),
          const Gap(2),
          if (_note.githubIssueUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View on GitHub',
              onPressed: () => launchUrl(Uri.parse(_note.githubIssueUrl!)),
            ),
          if (_note.status == 'Pending Review' ||
              _note.status == 'In Review' ||
              _note.status == 'Changes Requested')
            IconButton(
              icon: const Icon(Icons.person_add_rounded, color: SeraTokens.statusPendingReview),
              tooltip: _note.reviewers.isNotEmpty ? 'Add Another Reviewer' : 'Assign Reviewer',
              onPressed: _openAssignReviewer,
            ),
          if (_note.status != 'Pending Review' && _note.status != 'Approved')
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'update') _openRequestUpdate();
                if (v == 'copy') {
                  Clipboard.setData(ClipboardData(text: _note.brdDraft ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('BRD copied to clipboard')),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'update', child: ListTile(leading: Icon(Icons.edit_note_rounded), title: Text('Request Update'), contentPadding: EdgeInsets.zero, dense: true)),
                PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Copy BRD'), contentPadding: EdgeInsets.zero, dense: true)),
              ],
            ),
          if (_note.status == 'Approved') ...[
            if (_note.githubIssueUrl != null)
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                tooltip: 'Open BRD ticket',
                onPressed: () => launchUrl(Uri.parse(_note.githubIssueUrl!),
                    mode: LaunchMode.externalApplication),
              ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copy BRD',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _note.brdDraft ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('BRD copied to clipboard')),
                );
              },
            ),
          ],
        ],

        // ── PRD phase actions ─────────────────────────────────────────────
        if (_phase == 'prd' && _prd != null && !_prdIsWorking) ...[
          _StatusChip(_prd!.status, version: _prd!.currentVersionNumber),
          const Gap(2),
          if (_prd!.githubIssueUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View on GitHub',
              onPressed: () => launchUrl(Uri.parse(_prd!.githubIssueUrl!)),
            ),
          if (_prd!.status == 'Pending Review' ||
              _prd!.status == 'In Review' ||
              _prd!.status == 'Changes Requested')
            IconButton(
              icon: const Icon(Icons.person_add_rounded, color: SeraTokens.statusPendingReview),
              tooltip: _prd!.reviewers.isNotEmpty ? 'Add Another Reviewer' : 'Assign Reviewer',
              onPressed: _openPrdAssignReviewer,
            ),
          if (_prd!.status == 'In Review' || _prd!.status == 'Changes Requested')
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: SeraTokens.statusChanges),
              tooltip: 'Request PRD Update',
              onPressed: _openPrdRequestUpdate,
            ),
          if (_prd!.status == 'Approved')
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Color(0xFF00897B), size: 20),
              tooltip: 'Send to Planner',
              onPressed: _sendToPlanner,
            ),
          if (_prd!.prdDraft != null) ...[
            if (_prd!.githubIssueUrl != null)
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                tooltip: 'Open PRD ticket',
                onPressed: () => launchUrl(Uri.parse(_prd!.githubIssueUrl!),
                    mode: LaunchMode.externalApplication),
              ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copy PRD',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _prd!.prdDraft ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PRD copied to clipboard')),
                );
              },
            ),
          ],
        ],
      ],
      bottom: _buildAppBarBottom(),
    );
  }

  // Draft body: shows notes timeline + Add More Notes button
  Widget _buildDraftBody() {
    return _NotesHistoryTab(
      note: _note,
      onAddMore: _openAddMoreNotes,
      key: ValueKey('${_note.id}_$_entryVersion'),
    );
  }

  Widget _buildLoadingBody() {
    return GenerationProgressWidget(
      phase: _note.brdGenerationPhase,
      phaseNames: _brdPhaseNames,
      documentLabel: 'BRD',
      isUpdate: _note.brdDraft != null && _note.brdGenerationPhase == 0,
    );
  }

  Widget _buildReadyBody() {
    if (_tabController == null) return const SizedBox.shrink();
    return TabBarView(
      controller: _tabController,
      children: [
        _BrdDraftTab(note: _note),
        _VersionsTab(note: _note),
        _NotesHistoryTab(
          note: _note,
          onAddMore: null,
          key: ValueKey(_note.currentVersionNumber),
        ),
      ],
    );
  }

  // ── AppBar bottom helper ──────────────────────────────────────────────────

  PreferredSizeWidget? _buildAppBarBottom() {
    const tabStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

    Widget? phaseTabs;
    if (_showPipeline) {
      if (_phase == 'brd' && _brdReady && _tabController != null) {
        phaseTabs = TabBar(
          controller: _tabController,
          labelStyle: tabStyle,
          unselectedLabelStyle: tabStyle,
          tabs: const [Tab(text: 'BRD Draft'), Tab(text: 'Versions'), Tab(text: 'Notes History')],
          labelColor: kPrimary,
          indicatorColor: kPrimary,
          unselectedLabelColor: SeraTokens.muted,
        );
      } else if (_phase == 'prd' && _prdReady && _prdTabController != null) {
        phaseTabs = TabBar(
          controller: _prdTabController,
          labelStyle: tabStyle,
          unselectedLabelStyle: tabStyle,
          tabs: const [Tab(text: 'PRD Content'), Tab(text: 'Versions')],
          labelColor: kPrimary,
          indicatorColor: kPrimary,
          unselectedLabelColor: SeraTokens.muted,
        );
      }
      final height = phaseTabs != null ? 96.0 : 48.0;
      return PreferredSize(
        preferredSize: Size.fromHeight(height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PipelineStepper(
              brdStatus: _note.status,
              prdStatus: _prd?.status,
              activePhase: _phase,
              onBrdTap: () => setState(() => _phase = 'brd'),
              onPrdTap: _note.status == 'Approved'
                  ? () {
                      setState(() => _phase = 'prd');
                      // Re-fetch if prd is null or stale (no draft yet)
                      if (_prd == null || (_prd!.status == 'Draft' && !_prdLoading)) {
                        _fetchAndInitPrd();
                      }
                    }
                  : null,
            ),
            if (phaseTabs != null) phaseTabs,
          ],
        ),
      );
    }

    if (_brdReady && _tabController != null) {
      return TabBar(
        controller: _tabController,
        labelStyle: tabStyle,
        unselectedLabelStyle: tabStyle,
        tabs: const [Tab(text: 'BRD Draft'), Tab(text: 'Versions'), Tab(text: 'Notes History')],
        labelColor: kPrimary,
        indicatorColor: kPrimary,
        unselectedLabelColor: SeraTokens.muted,
      );
    }
    return null;
  }

  // ── PRD phase body ────────────────────────────────────────────────────────

  Widget _buildPrdBody() {
    // Show spinner while loading PRD state from backend
    if (_prdLoading) return const Center(child: CircularProgressIndicator());
    if (_prd == null || _prd!.status == 'Draft') {
      return _buildPrdGeneratePrompt();
    }
    if (_prdIsWorking) return _buildPrdLoadingBody();
    if (_prdReady) return _buildPrdReadyBody();
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildPrdGeneratePrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kPrimaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.description_rounded, size: 36, color: kPrimary),
            ),
            const Gap(20),
            const Text(
              'Generate PRD',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
            const Gap(8),
            const Text(
              'The BRD is approved. Generate the\nProduct Requirements Document next.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: SeraTokens.fg3, height: 1.5),
            ),
            const Gap(28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _generatePrd,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Generate PRD', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrdLoadingBody() {
    return GenerationProgressWidget(
      phase: _prd!.prdGenerationPhase,
      phaseNames: _prdPhaseNames,
      documentLabel: 'PRD',
      isUpdate: _prd!.prdDraft != null && _prd!.prdGenerationPhase == 0,
    );
  }

  Widget _buildPrdReadyBody() {
    if (_prdTabController == null) return const SizedBox.shrink();
    return TabBarView(
      controller: _prdTabController,
      children: [
        PrdContentTab(prd: _prd!, noteId: _note.id),
        PrdVersionsTab(noteId: _note.id, currentVersionNumber: _prd!.currentVersionNumber),
      ],
    );
  }
}

// ── Pipeline stepper ──────────────────────────────────────────────────────────

class _PipelineStepper extends StatelessWidget {
  final String brdStatus;
  final String? prdStatus;
  final String activePhase;
  final VoidCallback onBrdTap;
  final VoidCallback? onPrdTap;

  const _PipelineStepper({
    required this.brdStatus,
    required this.prdStatus,
    required this.activePhase,
    required this.onBrdTap,
    required this.onPrdTap,
  });

  @override
  Widget build(BuildContext context) {
    final brdDone = brdStatus == 'Approved';
    final prdDone = prdStatus == 'Approved' || prdStatus == 'Sent to Planner';
    final prdStarted = prdStatus != null && prdStatus != 'Draft';

    return Container(
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _StepButton(
            label: 'BRD',
            done: brdDone,
            active: activePhase == 'brd',
            enabled: true,
            onTap: onBrdTap,
          ),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: prdStarted
                    ? kPrimary.withValues(alpha: 0.35)
                    : const Color(0xFFE0E8F0),
              ),
            ),
          ),
          _StepButton(
            label: 'PRD',
            done: prdDone,
            active: activePhase == 'prd',
            enabled: onPrdTap != null,
            onTap: onPrdTap,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;

  const _StepButton({
    required this.label,
    required this.done,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? SeraTokens.statusApproved
        : active
            ? kPrimary
            : const Color(0xFFB0BEC5);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kPrimary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: active ? Border.all(color: kPrimary, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done)
              const Icon(Icons.check_circle_rounded, size: 14, color: SeraTokens.statusApproved)
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? kPrimary : Colors.transparent,
                  border: active ? null : Border.all(color: const Color(0xFFB0BEC5), width: 1.5),
                ),
              ),
            const Gap(6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PRD inline sheets (mirror BRD equivalents) ────────────────────────────────

class _PrdAssignReviewerSheetInline extends ConsumerStatefulWidget {
  final PrdDocument prd;
  final String noteId;
  final void Function(PrdDocument) onAssigned;

  const _PrdAssignReviewerSheetInline({
    required this.prd,
    required this.noteId,
    required this.onAssigned,
  });

  @override
  ConsumerState<_PrdAssignReviewerSheetInline> createState() =>
      _PrdAssignReviewerSheetInlineState();
}

class _PrdAssignReviewerSheetInlineState
    extends ConsumerState<_PrdAssignReviewerSheetInline> {
  ReviewerItem? _selected;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final reviewers = ref.read(authProvider).user?.reviewerList ?? [];

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
                  color: SeraTokens.statusPendingReview.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_add_rounded,
                  color: SeraTokens.statusPendingReview, size: 20),
            ),
            const Gap(10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assign PRD Reviewer',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  Text('Reviewer will be notified on GitHub to review the PRD',
                      style: TextStyle(fontSize: 12, color: SeraTokens.fg3)),
                ],
              ),
            ),
          ]),
          const Gap(20),
          const Text('Select Reviewer',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Gap(8),
          if (reviewers.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                Gap(8),
                Expanded(
                  child: Text(
                    'No reviewers configured. Go to Settings to add reviewers.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
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
                                  fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: Text('@${r.githubUsername}',
                              style: const TextStyle(
                                  fontSize: 12, color: SeraTokens.fg3)),
                          contentPadding: EdgeInsets.zero,
                          activeColor: SeraTokens.statusPendingReview,
                        ))
                    .toList(),
              ),
            ),
          if (_error != null) ...[
            const Gap(8),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: SeraTokens.statusChanges)),
          ],
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: SeraTokens.statusPendingReview),
              onPressed: _submitting || _selected == null
                  ? null
                  : () async {
                      setState(() { _submitting = true; _error = null; });
                      final navigator = Navigator.of(context);
                      final updated = await ref
                          .read(prdProvider(widget.noteId).notifier)
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
                          _error = 'Failed to assign reviewer. Try again.';
                        });
                      }
                    },
              icon: _submitting
                  ? const SizedBox(
                      width: 18, height: 18,
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

class _PrdUpdateSheetInline extends StatefulWidget {
  final String noteId;
  final Future<void> Function(String feedback) onSubmit;

  const _PrdUpdateSheetInline({required this.noteId, required this.onSubmit});

  @override
  State<_PrdUpdateSheetInline> createState() => _PrdUpdateSheetInlineState();
}

class _PrdUpdateSheetInlineState extends State<_PrdUpdateSheetInline> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Request PRD Update', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Gap(4),
          const Text('Describe the changes you want. The AI will propose updates for your confirmation.',
              style: TextStyle(fontSize: 13, color: SeraTokens.fg3, height: 1.4)),
          const Gap(16),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g. Section 5 is missing the authentication flow…',
              alignLabelWithHint: true,
            ),
          ),
          const Gap(16),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _loading || _ctrl.text.trim().isEmpty ? null : () async {
                setState(() => _loading = true);
                await widget.onSubmit(_ctrl.text.trim());
              },
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Feedback', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── BRD Draft tab ─────────────────────────────────────────────────────────────

class _BrdDraftTab extends StatelessWidget {
  final MeetingNote note;
  const _BrdDraftTab({required this.note});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // Status + reviewers banner
        if (note.status != 'Draft' && note.status != 'In Progress')
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_statusColors[note.status] ?? cs.primary)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: (_statusColors[note.status] ?? cs.primary)
                        .withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      note.status == 'Approved'
                          ? Icons.check_circle_rounded
                          : note.status == 'Pending Review'
                              ? Icons.hourglass_top_rounded
                              : Icons.rate_review_rounded,
                      size: 16,
                      color: _statusColors[note.status] ?? cs.primary,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.status == 'Approved'
                                ? 'BRD Approved ✓'
                                : note.status == 'Pending Review'
                                    ? 'BRD Ready — tap Assign Reviewer to start review'
                                    : note.status == 'In Review'
                                        ? 'Under Review'
                                        : 'Changes Requested',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _statusColors[note.status] ??
                                    cs.primary),
                          ),
                          if (note.githubIssueUrl != null &&
                              note.status != 'Pending Review')
                            const Text(
                                'GitHub issue linked · comments trigger AI updates',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: SeraTokens.fg3)),
                        ],
                      ),
                    ),
                  ]),
                  // Reviewer list with per-person status
                  if (note.reviewers.isNotEmpty) ...[
                    const Gap(10),
                    const Divider(height: 1),
                    const Gap(8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: note.reviewers.map((r) {
                        final approved = r.status == 'Approved';
                        final color = approved
                            ? SeraTokens.statusApproved
                            : SeraTokens.statusInReview;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: color.withValues(alpha: 0.4)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              approved
                                  ? Icons.check_circle_rounded
                                  : Icons.hourglass_empty_rounded,
                              size: 12,
                              color: color,
                            ),
                            const Gap(4),
                            Text(
                              '@${r.githubUsername}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: color),
                            ),
                            const Gap(4),
                            Text(
                              approved ? 'Approved' : 'Pending',
                              style: TextStyle(
                                  fontSize: 10, color: color),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // Dynamic Document Control — overrides any static version in the generated markdown
        SliverToBoxAdapter(
          child: DocControlCard(
            docType: 'BRD',
            version: note.currentVersionNumber,
            status: note.status,
            updatedAt: note.updatedAt,
            reviewer: note.reviewerName ?? note.reviewerGithubUsername,
          ),
        ),
        SliverToBoxAdapter(
          child: Markdown(
            data: note.brdDraft ?? '',
            selectable: true,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
      ],
    );
  }
}

// ── Dynamic Document Control card ────────────────────────────────────────────

class DocControlCard extends StatelessWidget {
  final String docType;      // 'BRD' or 'PRD'
  final int version;
  final String status;
  final DateTime updatedAt;
  final String? reviewer;

  const DocControlCard({
    required this.docType,
    required this.version,
    required this.status,
    required this.updatedAt,
    this.reviewer,
  });

  static String _fmt(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? SeraTokens.statusDraft;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: SeraTokens.surfaceBlue,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SeraTokens.borderBlue),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: SeraTokens.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(children: [
              const Icon(Icons.article_rounded, size: 14, color: SeraTokens.primary),
              const Gap(6),
              Text('$docType — Document Control',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12,
                      color: SeraTokens.primary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(status,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
          ),
          // Meta rows
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                DocControlRow(label: 'Version', value: 'v$version'),
                const Gap(6),
                DocControlRow(label: 'Last Updated', value: _fmt(updatedAt)),
                if (reviewer != null) ...[
                  const Gap(6),
                  DocControlRow(label: 'Reviewer', value: reviewer!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DocControlRow extends StatelessWidget {
  final String label;
  final String value;
  const DocControlRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 90,
        child: Text(label,
            style: const TextStyle(
                fontSize: 11.5, color: SeraTokens.muted, fontWeight: FontWeight.w600)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontSize: 11.5, color: SeraTokens.fg1)),
      ),
    ]);
  }
}

// ── Versions tab ──────────────────────────────────────────────────────────────

class _VersionsTab extends ConsumerStatefulWidget {
  final MeetingNote note;
  const _VersionsTab({required this.note});

  @override
  ConsumerState<_VersionsTab> createState() => _VersionsTabState();
}

class _VersionsTabState extends ConsumerState<_VersionsTab> {
  late Future<List<BrdVersion>> _versionsFuture;

  @override
  void initState() {
    super.initState();
    _versionsFuture =
        ref.read(notesProvider.notifier).fetchVersions(widget.note.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<BrdVersion>>(
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
                v.versionNumber == widget.note.currentVersionNumber;
            return _VersionCard(
              version: v,
              isCurrent: isCurrent,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _BrdVersionScreen(
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

class _VersionCard extends StatelessWidget {
  final BrdVersion version;
  final bool isCurrent;
  final VoidCallback onTap;

  const _VersionCard(
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
                        version.changeSummary ?? 'Initial generation',
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
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
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
                          color: SeraTokens.statusInProgressWarm
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$changedCount section${changedCount == 1 ? '' : 's'} changed',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: SeraTokens.statusInProgressWarm),
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

// ── Notes History tab ─────────────────────────────────────────────────────────

class _NotesHistoryTab extends ConsumerStatefulWidget {
  final MeetingNote note;
  final VoidCallback? onAddMore;

  const _NotesHistoryTab({required this.note, this.onAddMore, super.key});

  @override
  ConsumerState<_NotesHistoryTab> createState() =>
      _NotesHistoryTabState();
}

class _NotesHistoryTabState extends ConsumerState<_NotesHistoryTab> {
  late Future<List<NoteEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture =
        ref.read(notesProvider.notifier).fetchEntries(widget.note.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<NoteEntry>>(
      future: _entriesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? [];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // Wiki URL pills (supports multiple newline-separated URLs)
            if (widget.note.wikiUrl != null) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.note.wikiUrl!
                    .split('\n')
                    .where((u) => u.trim().isNotEmpty)
                    .map((url) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: kPrimaryLight,
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.link_rounded,
                                size: 14, color: kPrimary),
                            const Gap(5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(url,
                                  style: const TextStyle(
                                      fontSize: 11, color: kPrimary),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ))
                    .toList(),
              ),
              const Gap(16),
            ],

            // Entry timeline
            ...entries.asMap().entries.map((e) {
              final idx = e.key;
              final entry = e.value;
              return _EntryCard(
                  entry: entry, index: idx, total: entries.length);
            }),

            if (entries.isEmpty)
              Center(
                child: Text('No entries yet',
                    style:
                        TextStyle(color: cs.onSurfaceVariant)),
              ),

            // Add More Notes button
            if (widget.onAddMore != null) ...[
              const Gap(16),
              OutlinedButton.icon(
                onPressed: widget.onAddMore,
                icon: const Icon(Icons.add_comment_rounded, size: 18),
                label: const Text('Add More Notes'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: const BorderSide(color: kPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EntryCard extends StatefulWidget {
  final NoteEntry entry;
  final int index;
  final int total;

  const _EntryCard(
      {required this.entry, required this.index, required this.total});

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _expanded = false;

  String _entryTitle(String content) {
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }
    return 'Note ${widget.index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = widget.index == widget.total - 1;
    final preview = widget.entry.content.length > 180
        ? '${widget.entry.content.substring(0, 180)}…'
        : widget.entry.content;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline connector
          Column(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: kPrimaryLight,
                shape: BoxShape.circle,
                border: Border.all(color: kPrimary, width: 1.5),
              ),
              child: Center(
                child: Text(
                  '${widget.index + 1}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: kPrimary),
                ),
              ),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 1.5,
                  color: cs.outlineVariant,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
          ]),
          const Gap(12),
          // Entry content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        _entryTitle(widget.entry.content),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: kPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      _fmt(widget.entry.createdAt),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ]),
                  const Gap(6),
                  Text(
                    _expanded ? widget.entry.content : preview,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  if (widget.entry.content.length > 180)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _expanded ? 'Show less' : 'Show more',
                          style: const TextStyle(
                              fontSize: 12,
                              color: kPrimary,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── BRD Version Screen (diff view) ───────────────────────────────────────────

class _BrdVersionScreen extends StatelessWidget {
  final BrdVersion version;
  final bool isCurrent;

  const _BrdVersionScreen(
      {required this.version, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final sections = _parseBrdSections(version.brdMarkdown);
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
                    fontSize: 12, color: SeraTokens.statusInProgressWarm),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy BRD',
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: version.brdMarkdown));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('BRD copied to clipboard')));
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Changed sections banner
          if (hasChanges)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SeraTokens.statusInProgressWarm.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: SeraTokens.statusInProgressWarm.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.edit_note_rounded,
                          size: 16, color: SeraTokens.statusInProgressWarm),
                      Gap(6),
                      Text('Changed Sections',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: SeraTokens.statusInProgressWarm)),
                    ]),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: version.changedSections
                          .map((s) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: SeraTokens.statusInProgressWarm
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(s,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: SeraTokens.statusInProgressWarm)),
                              ))
                          .toList(),
                    ),
                    if (version.reviewerComment != null) ...[
                      const Gap(8),
                      const Divider(height: 1),
                      const Gap(8),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment_outlined,
                                size: 14, color: SeraTokens.fg3),
                            const Gap(6),
                            Expanded(
                              child: Text(version.reviewerComment!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: SeraTokens.fg3,
                                      fontStyle: FontStyle.italic)),
                            ),
                          ]),
                    ],
                  ],
                ),
              ),
            ),

          // Section-by-section content
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
                      fontSize: 14, fontWeight: FontWeight.bold),
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
                              color: SeraTokens.statusInProgressWarm, width: 3)),
                    ),
                    child: Stack(children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                            color: SeraTokens.statusInProgressWarm
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Changed',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: SeraTokens.statusInProgressWarm)),
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
