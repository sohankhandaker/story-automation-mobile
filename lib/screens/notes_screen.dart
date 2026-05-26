import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../app.dart';
import '../core/api.dart';

// ── Models ────────────────────────────────────────────────────────────────────

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

class MeetingNote {
  final String id;
  final String? title;
  final String rawNotes;
  final String? wikiUrl;
  final String? brdDraft;
  final int? brdGenerationPhase;
  final DateTime createdAt;

  MeetingNote.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String?,
        rawNotes = j['raw_notes'] as String,
        wikiUrl = j['wiki_url'] as String?,
        brdDraft = j['brd_draft'] as String?,
        brdGenerationPhase = j['brd_generation_phase'] as int?,
        createdAt = DateTime.parse(j['created_at'] as String);
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
                  child: const Icon(Icons.note_alt_outlined,
                      size: 48, color: kPrimary),
                ),
                const Gap(16),
                const Text('No meeting notes yet',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    final isDone = note.brdDraft != null && note.title != 'Processing…';

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
                      : kPrimaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDone
                      ? Icons.description_rounded
                      : Icons.hourglass_top_rounded,
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
                    Text(
                      isDone ? 'BRD ready' : 'Generating BRD…',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDone
                            ? const Color(0xFF43A047)
                            : cs.onSurfaceVariant,
                      ),
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
        content: const Text('This will permanently delete this meeting note and its BRD.'),
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
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
              TextPosition(offset: appended.length),
            );
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
                    color: kPrimaryLight,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.note_add_rounded,
                    color: kPrimary, size: 20),
              ),
              const Gap(10),
              const Text('New Meeting Note',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          const Gap(16),

          // Notes input with voice + paste
          Stack(
            children: [
              TextField(
                controller: _notesCtrl,
                maxLines: 7,
                decoration: InputDecoration(
                  hintText:
                      'Paste or type your raw meeting notes here…\nOr use the mic to dictate.',
                  alignLabelWithHint: true,
                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 50, 14),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Column(
                  children: [
                    // Paste button
                    IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste_rounded, size: 20),
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _notesCtrl.text = data!.text!.trim();
                          _notesCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _notesCtrl.text.length),
                          );
                        }
                      },
                    ),
                    // Mic button
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const Gap(8),
                Text(_sttStatus,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7A8D))),
              ],
            ),
          ],

          const Gap(12),

          // Wiki URL field
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
              label: Text(_submitting ? 'Generating BRD…' : 'Generate BRD'),
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
  ConsumerState<_NoteDetailScreen> createState() =>
      _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<_NoteDetailScreen> {
  late MeetingNote _note;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    if (widget.polling && _note.brdDraft == null) {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final updated =
          await ref.read(notesProvider.notifier).pollNote(_note.id);
      if (updated != null && mounted) {
        setState(() => _note = updated);
        if (updated.brdDraft != null) {
          _pollTimer?.cancel();
          ref.read(notesProvider.notifier).fetchNotes();
        }
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brdReady = _note.brdDraft != null && _note.title != 'Processing…';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _note.title ?? 'Processing…',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (brdReady)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy BRD',
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _note.brdDraft ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('BRD copied to clipboard')),
                );
              },
            ),
        ],
      ),
      body: !brdReady
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const Gap(20),
                  const Text(
                    'Generating your BRD…',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const Gap(8),
                  if (_note.brdGenerationPhase != null) ...[
                    Text(
                      'Phase ${_note.brdGenerationPhase} of 7',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: kPrimary),
                    ),
                    const Gap(4),
                    Text(
                      _brdPhaseNames[_note.brdGenerationPhase!],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const Gap(8),
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        value: _note.brdGenerationPhase! / 7,
                        backgroundColor:
                            cs.onSurfaceVariant.withValues(alpha: 0.15),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(kPrimary),
                      ),
                    ),
                  ] else
                    Text(
                      'The AI is reading your notes${_note.wikiUrl != null ? '\nand crawling the wiki link' : ''}.\nThis takes about 1–2 minutes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 14),
                    ),
                ],
              ),
            )
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'BRD Draft'),
                      Tab(text: 'Raw Notes'),
                    ],
                    labelColor: kPrimary,
                    indicatorColor: kPrimary,
                    unselectedLabelColor: cs.onSurfaceVariant,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // BRD tab
                        Markdown(
                          data: _note.brdDraft ?? '',
                          selectable: true,
                          padding: const EdgeInsets.all(16),
                          styleSheet: MarkdownStyleSheet(
                            h1: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                            h2: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kPrimary),
                            p: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),
                        // Raw notes tab
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_note.wikiUrl != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: kPrimaryLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.link_rounded,
                                          size: 16, color: kPrimary),
                                      const Gap(6),
                                      Expanded(
                                        child: Text(
                                          _note.wikiUrl!,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: kPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Gap(12),
                              ],
                              Text(
                                _note.rawNotes,
                                style: const TextStyle(
                                    fontSize: 14, height: 1.6),
                              ),
                            ],
                          ),
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
