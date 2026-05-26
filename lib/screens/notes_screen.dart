import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../app.dart';
import '../core/api.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _brdPhaseNames = [
  '',
  'Document Control & Executive Summary',
  'Business Context, Vision & Objectives',
  'Product Scope, Capability Map & Value Chain',
  'Stakeholders, Personas & Governance',
  'Business Processes & Functional Requirements',
  'Non-Functional Requirements, Data, Integrations & Business Rules',
  'KPIs, Roadmap, Risks, Acceptance Criteria & Checklists',
];

const _statusColors = {
  'Draft': Color(0xFF78909C),
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
  return changedSections.any((c) => h.contains(c.toLowerCase()) || c.toLowerCase().contains(h));
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
                    color: kPrimaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.note_alt_outlined, size: 48, color: kPrimary),
                ),
                const Gap(16),
                const Text('No meeting notes yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Gap(6),
                const Text('Tap + New Meeting Note to get started',
                    style: TextStyle(color: Color(0xFF6B7A8D), fontSize: 14)),
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
    final isDone = note.brdDraft != null && note.brdGenerationPhase == null;
    final isWorking = note.brdGenerationPhase != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _NoteDetailScreen(note: note)),
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
                      : isWorking
                          ? kPrimaryLight
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
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Gap(4),
                    Row(
                      children: [
                        Text(
                          isWorking
                              ? (note.brdGenerationPhase == 0 ? 'Updating BRD…' : 'Generating BRD…')
                              : isDone
                                  ? 'v${note.currentVersionNumber} · BRD ready'
                                  : 'No BRD yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDone ? const Color(0xFF43A047) : cs.onSurfaceVariant,
                          ),
                        ),
                        if (isDone) ...[
                          const Gap(6),
                          _StatusChip(note.status),
                        ],
                      ],
                    ),
                    const Gap(2),
                    Text(
                      _formatDate(note.createdAt),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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
            _notesCtrl.selection =
                TextSelection.fromPosition(TextPosition(offset: appended.length));
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _NoteDetailScreen(note: note, polling: true),
        ),
      );
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Gap(16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: kPrimaryLight, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.note_add_rounded, color: kPrimary, size: 20),
              ),
              const Gap(10),
              const Text('New Meeting Note',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          const Gap(16),
          Stack(
            children: [
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
                child: Column(
                  children: [
                    IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste_rounded, size: 20),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _notesCtrl.text = data!.text!.trim();
                          _notesCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _notesCtrl.text.length),
                          );
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
                  ],
                ),
              ),
            ],
          ),
          if (_listening) ...[
            const Gap(6),
            Row(
              children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const Gap(8),
                Text(_sttStatus,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7A8D))),
              ],
            ),
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
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_submitting ? 'Generating BRD…' : 'Generate BRD'),
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

  const _RequestUpdateSheet({required this.noteId, required this.onSubmit});

  @override
  State<_RequestUpdateSheet> createState() => _RequestUpdateSheetState();
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
                  color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Gap(16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.1),
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    Text('AI will update only the affected sections',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7A8D))),
                  ],
                ),
              ),
            ],
          ),
          const Gap(16),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Describe what needs to change…\n\nExample: "Add GDPR compliance requirements to Section 14. Expand the KPI targets to include NPS score."',
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
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_submitting ? 'Submitting…' : 'Update BRD with AI'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Note Detail (BRD viewer) ──────────────────────────────────────────────────

class _NoteDetailScreen extends ConsumerStatefulWidget {
  final MeetingNote note;
  final bool polling;

  const _NoteDetailScreen({required this.note, this.polling = false});

  @override
  ConsumerState<_NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<_NoteDetailScreen>
    with SingleTickerProviderStateMixin {
  late MeetingNote _note;
  Timer? _pollTimer;
  TabController? _tabController;

  bool get _isWorking => _note.brdGenerationPhase != null;
  bool get _brdReady => _note.brdDraft != null && !_isWorking;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    if (_brdReady) _initTabs();
    if (widget.polling || _isWorking) _startPolling();
  }

  void _initTabs() {
    _tabController?.dispose();
    _tabController = TabController(length: 3, vsync: this);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final updated = await ref.read(notesProvider.notifier).pollNote(_note.id);
      if (updated != null && mounted) {
        final wasWorking = _isWorking;
        setState(() {
          _note = updated;
          if (_brdReady && _tabController == null) _initTabs();
        });
        if (wasWorking && !_isWorking) {
          _pollTimer?.cancel();
          ref.read(notesProvider.notifier).fetchNotes();
        }
      }
    });
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
          final updated =
              await ref.read(notesProvider.notifier).submitFeedback(_note.id, feedback);
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _note.title ?? 'Processing…',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_brdReady) ...[
            _StatusChip(_note.status),
            const Gap(4),
            IconButton(
              icon: const Icon(Icons.edit_note_rounded),
              tooltip: 'Request Update',
              onPressed: _openRequestUpdate,
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded),
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
        bottom: _brdReady && _tabController != null
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'BRD Draft'),
                  Tab(text: 'Versions'),
                  Tab(text: 'Raw Notes'),
                ],
                labelColor: kPrimary,
                indicatorColor: kPrimary,
                unselectedLabelColor: const Color(0xFF8896A5),
              )
            : null,
      ),
      body: _isWorking ? _buildLoadingBody(cs) : _buildReadyBody(cs),
    );
  }

  Widget _buildLoadingBody(ColorScheme cs) {
    final isUpdate = _note.brdDraft != null && _note.brdGenerationPhase == 0;
    final phase = _note.brdGenerationPhase;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const Gap(20),
          Text(
            isUpdate ? 'Updating BRD from feedback…' : 'Generating your BRD…',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Gap(8),
          if (!isUpdate && phase != null && phase > 0) ...[
            Text(
              'Phase $phase of 7',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: kPrimary),
            ),
            const Gap(4),
            Text(
              _brdPhaseNames[phase],
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const Gap(8),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: phase / 7,
                backgroundColor: cs.onSurfaceVariant.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
              ),
            ),
          ] else
            Text(
              isUpdate
                  ? 'The AI is applying your requested changes.\nThis takes about 30–60 seconds.'
                  : 'The AI is reading your notes${_note.wikiUrl != null ? '\nand crawling the wiki link' : ''}.\nThis takes about 1–2 minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildReadyBody(ColorScheme cs) {
    if (_tabController == null) return const SizedBox.shrink();
    return TabBarView(
      controller: _tabController,
      children: [
        _BrdDraftTab(brdMarkdown: _note.brdDraft ?? ''),
        _VersionsTab(note: _note),
        _RawNotesTab(note: _note),
      ],
    );
  }
}

// ── BRD Draft tab ─────────────────────────────────────────────────────────────

class _BrdDraftTab extends StatelessWidget {
  final String brdMarkdown;
  const _BrdDraftTab({required this.brdMarkdown});

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: brdMarkdown,
      selectable: true,
      padding: const EdgeInsets.all(16),
      styleSheet: MarkdownStyleSheet(
        h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kPrimary),
        h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        p: const TextStyle(fontSize: 14, height: 1.5),
        tableHead: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tableBody: const TextStyle(fontSize: 13),
      ),
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
    _load();
  }

  void _load() {
    _versionsFuture = ref.read(notesProvider.notifier).fetchVersions(widget.note.id);
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
                style: TextStyle(color: cs.onSurfaceVariant)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: versions.length,
          itemBuilder: (_, i) {
            final v = versions[i];
            final isCurrent = v.versionNumber == widget.note.currentVersionNumber;
            return _VersionCard(
              version: v,
              isCurrent: isCurrent,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _BrdVersionScreen(version: v, isCurrent: isCurrent),
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

  const _VersionCard({
    required this.version,
    required this.isCurrent,
    required this.onTap,
  });

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
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isCurrent ? kPrimaryLight : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'v${version.versionNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isCurrent ? kPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            version.changeSummary ?? 'Initial generation',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
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
                      ],
                    ),
                    const Gap(4),
                    Row(
                      children: [
                        Text(
                          _formatDate(version.createdAt),
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        if (changedCount > 0) ...[
                          const Gap(8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
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
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Raw Notes tab ─────────────────────────────────────────────────────────────

class _RawNotesTab extends StatelessWidget {
  final MeetingNote note;
  const _RawNotesTab({required this.note});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.wikiUrl != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kPrimaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 16, color: kPrimary),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      note.wikiUrl!,
                      style: const TextStyle(fontSize: 12, color: kPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
          ],
          Text(note.rawNotes, style: const TextStyle(fontSize: 14, height: 1.6)),
        ],
      ),
    );
  }
}

// ── BRD Version Screen (diff view) ───────────────────────────────────────────

class _BrdVersionScreen extends StatelessWidget {
  final BrdVersion version;
  final bool isCurrent;

  const _BrdVersionScreen({required this.version, required this.isCurrent});

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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (hasChanges)
              Text(
                '${version.changedSections.length} section${version.changedSections.length == 1 ? '' : 's'} changed',
                style: const TextStyle(fontSize: 12, color: Color(0xFFFF8F00)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy BRD',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: version.brdMarkdown));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('BRD copied to clipboard')),
              );
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
                    const Row(
                      children: [
                        Icon(Icons.edit_note_rounded,
                            size: 16, color: Color(0xFFFF8F00)),
                        Gap(6),
                        Text(
                          'Changed Sections',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFFFF8F00)),
                        ),
                      ],
                    ),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: version.changedSections
                          .map((s) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
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
                            child: Text(
                              version.reviewerComment!,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7A8D),
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Section-by-section BRD content
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final section = sections[i];
                final isChanged = hasChanges &&
                    _sectionIsChanged(section.heading, version.changedSections);

                final headingPrefix = '#' * section.level;
                final sectionMarkdown =
                    '$headingPrefix ${section.heading}\n\n${section.content}';

                if (isChanged) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    decoration: BoxDecoration(
                      border: const Border(
                        left: BorderSide(color: Color(0xFFFF8F00), width: 3),
                      ),
                      color: const Color(0xFFFF8F00).withValues(alpha: 0.04),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: MarkdownBody(
                            data: sectionMarkdown,
                            selectable: true,
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
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8F00).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Changed',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF8F00)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: MarkdownBody(
                    data: sectionMarkdown,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
