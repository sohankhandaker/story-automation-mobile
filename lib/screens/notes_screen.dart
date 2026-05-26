import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../core/api.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

// Phases 1-2 are prep (crawl + analyze), phases 3-9 map to BRD phases 1-7
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
  'KPIs, Roadmap, Risks & Acceptance Criteria',
];

const _statusColors = {
  'Draft': Color(0xFF78909C),
  'In Progress': Color(0xFF1565C0),
  'Pending Review': Color(0xFF6A1B9A),
  'In Review': Color(0xFF1E88E5),
  'Changes Requested': Color(0xFFE53935),
  'Approved': Color(0xFF43A047),
};

// ── Models ────────────────────────────────────────────────────────────────────

class MeetingNote {
  final String id;
  final String? title;
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
  final DateTime createdAt;

  MeetingNote.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String?,
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
        createdAt = DateTime.parse(j['created_at'] as String);
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

  Future<MeetingNote?> addEntry(String noteId, String content) async {
    try {
      final resp = await ApiClient.dio.post(
        '/api/notes/$noteId/entries',
        data: {'content': content},
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
    } catch (_) {}
  }
}

final notesProvider =
    StateNotifierProvider<NotesNotifier, AsyncValue<List<MeetingNote>>>(
  (_) => NotesNotifier(),
);

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? const Color(0xFF78909C);
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
                        color: Color(0xFF6B7A8D), fontSize: 14)),
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
            itemBuilder: (_, i) => _NoteCard(note: notes[i]),
          ),
        );
      },
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final MeetingNote note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isWorking =
        note.brdGenerationPhase != null || note.status == 'In Progress';
    final isDone = note.brdDraft != null && !isWorking;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => _NoteDetailScreen(note: note)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF43A047).withValues(alpha: 0.12)
                      : kPrimaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDone
                      ? Icons.description_rounded
                      : isWorking
                          ? Icons.hourglass_top_rounded
                          : Icons.note_alt_outlined,
                  color: isDone ? const Color(0xFF43A047) : kPrimary,
                  size: 22,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title ?? 'Processing…',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                                ? const Color(0xFF43A047)
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
            onPressed: () {
              Navigator.pop(context);
              ref.read(notesProvider.notifier).deleteNote(note.id);
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

  bool _sttAvailable = false;
  bool _listening = false;
  bool _submitting = false;
  String _sttStatus = '';

  @override
  void initState() {
    super.initState();
    _initStt();
  }

  Future<void> _initStt() async {
    final ok = await _stt.initialize(
      onStatus: (s) {
        if (mounted) setState(() => _listening = s == 'listening');
      },
      onError: (e) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _sttStatus = 'Listening…';
    });
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          final current = _notesCtrl.text;
          final appended = current.isEmpty
              ? result.recognizedWords
              : '$current ${result.recognizedWords}';
          setState(() {
            _notesCtrl.text = appended;
            _notesCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: appended.length));
            _listening = false;
            _sttStatus = '';
          });
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 4),
        partialResults: false,
      ),
    );
  }

  Future<void> _submit() async {
    final notes = _notesCtrl.text.trim();
    if (notes.isEmpty) return;
    setState(() => _submitting = true);
    final note = await ref.read(notesProvider.notifier).createNote(
          notes,
          _wikiCtrl.text.trim().isEmpty ? null : _wikiCtrl.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pop();
    if (note != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _NoteDetailScreen(note: note),
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
              Text(_sttStatus,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7A8D))),
            ]),
          ],
          const Gap(12),
          TextField(
            controller: _wikiCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'Wiki / Confluence / Notion URL (optional)',
              prefixIcon: Icon(Icons.link_rounded, size: 18),
            ),
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
  final void Function(MeetingNote updated) onAdded;

  const _AddMoreNotesSheet(
      {required this.noteId, required this.onAdded});

  @override
  ConsumerState<_AddMoreNotesSheet> createState() =>
      _AddMoreNotesSheetState();
}

class _AddMoreNotesSheetState
    extends ConsumerState<_AddMoreNotesSheet> {
  final _ctrl = TextEditingController();
  final _stt = SpeechToText();
  bool _sttAvailable = false;
  bool _listening = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _stt.initialize(
      onStatus: (s) {
        if (mounted) setState(() => _listening = s == 'listening');
      },
    ).then((ok) {
      if (mounted) setState(() => _sttAvailable = ok);
    });
  }

  @override
  void dispose() {
    _stt.stop();
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
                          fontSize: 12, color: Color(0xFF6B7A8D))),
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
                  icon:
                      const Icon(Icons.content_paste_rounded, size: 20),
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
                    onPressed: () async {
                      if (_listening) {
                        await _stt.stop();
                        setState(() => _listening = false);
                        return;
                      }
                      setState(() => _listening = true);
                      await _stt.listen(
                        onResult: (r) {
                          if (r.finalResult) {
                            final cur = _ctrl.text;
                            final app = cur.isEmpty
                                ? r.recognizedWords
                                : '$cur ${r.recognizedWords}';
                            setState(() {
                              _ctrl.text = app;
                              _ctrl.selection =
                                  TextSelection.fromPosition(
                                      TextPosition(offset: app.length));
                              _listening = false;
                            });
                          }
                        },
                        listenOptions: SpeechListenOptions(
                          listenFor: const Duration(minutes: 5),
                          pauseFor: const Duration(seconds: 4),
                          partialResults: false,
                        ),
                      );
                    },
                  ),
              ]),
            ),
          ]),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _submitting || _ctrl.text.trim().isEmpty
                      ? null
                      : () async {
                          setState(() => _submitting = true);
                          final navigator = Navigator.of(context);
                          final updated = await ref
                              .read(notesProvider.notifier)
                              .addEntry(
                                  widget.noteId, _ctrl.text.trim());
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
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.rocket_launch_rounded,
                  color: Color(0xFF1565C0), size: 20),
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
                          TextStyle(fontSize: 12, color: Color(0xFF6B7A8D))),
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
                    fontSize: 12, color: Color(0xFFE53935))),
          ],
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0)),
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
                  color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_add_rounded,
                  color: Color(0xFF6A1B9A), size: 20),
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
                          TextStyle(fontSize: 12, color: Color(0xFF6B7A8D))),
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
  bool _submitting = false;

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
                  color:
                      const Color(0xFFE53935).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_note_rounded,
                  color: Color(0xFFE53935), size: 20),
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
                          fontSize: 12, color: Color(0xFF6B7A8D))),
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

class _NoteDetailScreen extends ConsumerStatefulWidget {
  final MeetingNote note;

  const _NoteDetailScreen({required this.note});

  @override
  ConsumerState<_NoteDetailScreen> createState() =>
      _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<_NoteDetailScreen>
    with SingleTickerProviderStateMixin {
  late MeetingNote _note;
  Timer? _pollTimer;
  TabController? _tabController;

  // Draft: notes collected, no BRD yet, not working
  bool get _isDraft =>
      _note.status == 'Draft' && _note.brdGenerationPhase == null;

  // Working: pipeline running (initial or update)
  bool get _isWorking =>
      _note.brdGenerationPhase != null || _note.status == 'In Progress';

  // BRD exists and not actively regenerating
  bool get _brdReady => _note.brdDraft != null && !_isWorking;

  // Poll while generating or while under active review (to catch updates)
  bool get _shouldPoll =>
      _isWorking ||
      _note.status == 'In Review' ||
      _note.status == 'Changes Requested';

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    if (_brdReady) _initTabs();
    if (_shouldPoll) _startPolling();
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
        onAdded: (updated) => setState(() => _note = updated),
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
      body: _isDraft
          ? _buildDraftBody()
          : _isWorking
              ? _buildLoadingBody()
              : _buildReadyBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        _isDraft
            ? (_note.title == 'New Note' ? 'Meeting Notes' : (_note.title ?? 'Meeting Notes'))
            : _isWorking
                ? 'Generating BRD…'
                : (_note.title ?? 'BRD'),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // Mark as Ready — Draft state
        if (_isDraft)
          IconButton(
            icon: const Icon(Icons.rocket_launch_rounded,
                color: Color(0xFF1565C0)),
            tooltip: 'Start BRD Generation',
            onPressed: _openMarkReady,
          ),

        // Status + actions when BRD exists
        if (_brdReady) ...[
          _StatusChip(_note.status),
          const Gap(2),
          if (_note.githubIssueUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View on GitHub',
              onPressed: () => launchUrl(Uri.parse(_note.githubIssueUrl!)),
            ),
          // Assign Reviewer — BRD ready, waiting for reviewer
          if (_note.status == 'Pending Review')
            IconButton(
              icon: const Icon(Icons.person_add_rounded,
                  color: Color(0xFF6A1B9A)),
              tooltip: 'Assign Reviewer',
              onPressed: _openAssignReviewer,
            ),
          // Overflow: Request Update + Copy BRD
          if (_note.status != 'Pending Review' &&
              _note.status != 'Approved')
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'update') _openRequestUpdate();
                if (v == 'copy') {
                  Clipboard.setData(
                      ClipboardData(text: _note.brdDraft ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('BRD copied to clipboard')),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'update',
                  child: ListTile(
                    leading: Icon(Icons.edit_note_rounded),
                    title: Text('Request Update'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: Icon(Icons.copy_rounded),
                    title: Text('Copy BRD'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
          if (_note.status == 'Approved')
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copy BRD',
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _note.brdDraft ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('BRD copied to clipboard')),
                );
              },
            ),
        ],
      ],
      bottom: _brdReady && _tabController != null
          ? TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'BRD Draft'),
                Tab(text: 'Versions'),
                Tab(text: 'Notes History'),
              ],
              labelColor: kPrimary,
              indicatorColor: kPrimary,
              unselectedLabelColor: const Color(0xFF8896A5),
            )
          : null,
    );
  }

  // Draft body: shows notes timeline + Add More Notes button
  Widget _buildDraftBody() {
    return _NotesHistoryTab(
      note: _note,
      onAddMore: _openAddMoreNotes,
      key: ValueKey(_note.id),
    );
  }

  Widget _buildLoadingBody() {
    final cs = Theme.of(context).colorScheme;
    final isUpdate =
        _note.brdDraft != null && _note.brdGenerationPhase == 0;
    final phase = _note.brdGenerationPhase;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const Gap(20),
          Text(
            isUpdate ? 'Updating BRD…' : 'Generating BRD…',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Gap(8),
          if (!isUpdate && phase != null && phase > 0 &&
              phase < _brdPhaseNames.length) ...[
            Text(
              phase <= 2
                  ? 'Step $phase of 9'
                  : 'Phase ${phase - 2} of 7',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: kPrimary),
            ),
            const Gap(4),
            Text(
              _brdPhaseNames[phase],
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const Gap(8),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: phase / (_brdPhaseNames.length - 1),
                backgroundColor:
                    cs.onSurfaceVariant.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(kPrimary),
              ),
            ),
          ] else
            Text(
              isUpdate
                  ? 'Applying your changes. About 30–60 seconds.'
                  : 'Crawling links, analyzing notes, generating BRD…\nAbout 1–2 minutes.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
        ],
      ),
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
          onAddMore: null, // entries locked once pipeline starts
          key: ValueKey(_note.currentVersionNumber),
        ),
      ],
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
        // Status banner (shown for all non-Draft, non-In-Progress statuses)
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
              child: Row(children: [
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
                                    ? 'Under Review by @${note.reviewerGithubUsername}'
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
                                color: Color(0xFF6B7A8D))),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        SliverToBoxAdapter(
          child: Markdown(
            data: note.brdDraft ?? '',
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
      ],
    );
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
                          color: const Color(0xFFFF8F00)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
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
            // Wiki URL pill
            if (widget.note.wikiUrl != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: kPrimaryLight,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.link_rounded,
                      size: 16, color: kPrimary),
                  const Gap(6),
                  Expanded(
                    child: Text(widget.note.wikiUrl!,
                        style: const TextStyle(
                            fontSize: 12, color: kPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
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
                    Text(
                      'Entry ${widget.index + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: kPrimary),
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
                    fontSize: 12, color: Color(0xFFFF8F00)),
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
                  color: const Color(0xFFFF8F00).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFF8F00).withValues(alpha: 0.3)),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8F00)
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(s,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFFF8F00))),
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
                                size: 14, color: Color(0xFF6B7A8D)),
                            const Gap(6),
                            Expanded(
                              child: Text(version.reviewerComment!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7A8D),
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
                              color: Color(0xFFFF8F00), width: 3)),
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
                            color: const Color(0xFFFF8F00)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
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
