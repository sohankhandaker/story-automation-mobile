import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../theme/sera_tokens.dart';
import 'notes_screen.dart' show MeetingNote;

class CrDetailScreen extends ConsumerStatefulWidget {
  final MeetingNote note;
  const CrDetailScreen({super.key, required this.note});

  @override
  ConsumerState<CrDetailScreen> createState() => _CrDetailScreenState();
}

class _CrDetailScreenState extends ConsumerState<CrDetailScreen> {
  late MeetingNote _note;
  Timer? _pollTimer;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final resp = await ApiClient.dio.get('/api/notes/${_note.id}');
      if (!mounted) return;
      setState(() => _note = MeetingNote.fromJson(resp.data as Map<String, dynamic>));
    } catch (_) {}
    _schedulePollIfNeeded();
  }

  void _schedulePollIfNeeded() {
    _pollTimer?.cancel();
    if (_note.brdGenerationPhase != null || _note.status == 'In Progress') {
      _pollTimer = Timer(const Duration(seconds: 4), _refresh);
    }
  }

  bool get _isClosed => _note.status == 'Closed';
  bool get _isWorking => _note.brdGenerationPhase != null || _note.status == 'In Progress';
  // Editable as long as not Closed — generation in progress doesn't block editing
  bool get _canEdit => !_isClosed;

  Color get _statusColor {
    switch (_note.status) {
      case 'Closed': return SeraTokens.statusApproved;
      case 'In Review': return SeraTokens.statusInReview;
      default: return SeraTokens.statusInProgressWarm;
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _regenerateSummary() async {
    setState(() => _actionLoading = true);
    try {
      final resp = await ApiClient.dio.post('/api/notes/${_note.id}/regenerate-cr-summary');
      if (mounted) setState(() => _note = MeetingNote.fromJson(resp.data as Map<String, dynamic>));
      _schedulePollIfNeeded();
    } on DioException catch (e) {
      _showError((e.response?.data as Map?)?['detail'] as String? ?? 'Failed to regenerate');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _sendToPlanner() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send to Planner'),
        content: const Text(
            'This will generate the planner document and close this Change Request. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send to Planner'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final resp = await ApiClient.dio.post('/api/notes/${_note.id}/send-cr-to-planner');
      if (mounted) setState(() => _note = MeetingNote.fromJson(resp.data as Map<String, dynamic>));
      _schedulePollIfNeeded();
    } on DioException catch (e) {
      _showError((e.response?.data as Map?)?['detail'] as String? ?? 'Failed to send to planner');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _uploadAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'doc', 'docx', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;

    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(f.bytes!, filename: f.name),
      });
      await ApiClient.dio.post('/api/notes/${_note.id}/attachments', data: form);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment uploaded')),
        );
      }
    } catch (_) {
      _showError('Upload failed');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open link');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: SeraTokens.surface,
      appBar: AppBar(
        backgroundColor: SeraTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Change Request',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            // ── Status bar ───────────────────────────────────────────
            _StatusBar(note: _note, statusColor: _statusColor, isWorking: _isWorking),
            const Gap(16),

            // ── Title & raw notes ────────────────────────────────────
            _SectionHeader(icon: Icons.edit_note_rounded, label: 'Change Request Details'),
            const Gap(8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_note.title ?? 'Change Request',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15, color: SeraTokens.fg1)),
                    const Gap(10),
                    Text(_note.rawNotes,
                        style: const TextStyle(fontSize: 13, color: SeraTokens.fg2, height: 1.5)),
                    if (_canEdit) ...[
                      const Gap(12),
                      OutlinedButton.icon(
                        onPressed: () => _showEditSheet(context),
                        icon: const Icon(Icons.edit_rounded, size: 14),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Gap(16),

            // ── AI Summary ───────────────────────────────────────────
            _SectionHeader(icon: Icons.auto_awesome_rounded, label: 'AI Summary'),
            const Gap(8),
            if (_isWorking)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _statusColor),
                    ),
                    const Gap(12),
                    const Text('Generating summary against approved PRD…',
                        style: TextStyle(fontSize: 13, color: SeraTokens.fg3)),
                  ]),
                ),
              )
            else if (_note.brdDraft != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MarkdownBody(
                        data: _note.brdDraft!,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(fontSize: 13, height: 1.5, color: SeraTokens.fg1),
                          h1: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_canEdit) ...[
                        const Gap(12),
                        const Divider(),
                        const Gap(4),
                        OutlinedButton.icon(
                          onPressed: _actionLoading ? null : _regenerateSummary,
                          icon: _actionLoading
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text('Regenerate Summary'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SeraTokens.statusInProgressWarm,
                            side: const BorderSide(color: SeraTokens.statusInProgressWarm),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Icon(Icons.pending_rounded, size: 32, color: SeraTokens.muted),
                    const Gap(8),
                    const Text('Summary not yet generated.',
                        style: TextStyle(color: SeraTokens.fg3, fontSize: 13)),
                    const Gap(12),
                    if (_canEdit)
                      FilledButton.icon(
                        onPressed: _actionLoading ? null : _regenerateSummary,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('Generate Summary'),
                      ),
                  ]),
                ),
              ),
            const Gap(16),

            // ── Attachments ──────────────────────────────────────────
            _SectionHeader(icon: Icons.attach_file_rounded, label: 'Attachments'),
            const Gap(8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_canEdit)
                      OutlinedButton.icon(
                        onPressed: _uploadAttachment,
                        icon: const Icon(Icons.upload_file_rounded, size: 14),
                        label: const Text('Upload File'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('PDF, DOCX, DOC, TXT, MD supported',
                          style: TextStyle(fontSize: 11, color: SeraTokens.hint)),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // ── Planner Document (closed only) ───────────────────────
            if (_isClosed) ...[
              _SectionHeader(icon: Icons.description_rounded, label: 'Planner Document'),
              const Gap(8),
              if (_note.plannerDocUrl != null)
                Card(
                  color: SeraTokens.statusApproved.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.check_circle_rounded,
                              size: 16, color: SeraTokens.statusApproved),
                          Gap(8),
                          Text('Planner document ready',
                              style: TextStyle(fontWeight: FontWeight.w700,
                                  color: SeraTokens.statusApproved, fontSize: 14)),
                        ]),
                        const Gap(12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _launchUrl(_note.plannerDocUrl!),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text('Open Planner Document'),
                            style: FilledButton.styleFrom(
                              backgroundColor: SeraTokens.statusApproved,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isWorking)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _statusColor)),
                      const Gap(12),
                      const Text('Generating planner document…',
                          style: TextStyle(fontSize: 13, color: SeraTokens.fg3)),
                    ]),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Icon(Icons.pending_rounded, size: 20, color: SeraTokens.muted),
                      const Gap(8),
                      const Text('Planner document not yet available.',
                          style: TextStyle(fontSize: 13, color: SeraTokens.fg3)),
                    ]),
                  ),
                ),
              const Gap(16),
            ],

            // ── Send to Planner action ───────────────────────────────
            if (_note.status == 'In Review' && !_isClosed) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _actionLoading ? null : _sendToPlanner,
                  icon: _actionLoading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: const Text('Send to Planner'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],

            if (_isClosed)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_rounded, size: 14, color: SeraTokens.muted),
                  Gap(8),
                  Expanded(
                    child: Text(
                      'This Change Request is Closed and cannot be modified.',
                      style: TextStyle(fontSize: 12, color: SeraTokens.muted),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CrEditSheet(note: _note, onSaved: (updated) {
        if (mounted) setState(() => _note = updated);
      }),
    );
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final MeetingNote note;
  final Color statusColor;
  final bool isWorking;
  const _StatusBar({required this.note, required this.statusColor, required this.isWorking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        if (isWorking)
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: statusColor))
        else
          Icon(_statusIcon(note.status), size: 14, color: statusColor),
        const Gap(8),
        Text(note.status,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: statusColor)),
        const Spacer(),
        Text(note.createdAt.toLocal().toString().substring(0, 10),
            style: const TextStyle(fontSize: 12, color: SeraTokens.muted)),
      ]),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Closed': return Icons.check_circle_rounded;
      case 'In Review': return Icons.rate_review_rounded;
      default: return Icons.hourglass_top_rounded;
    }
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: SeraTokens.fg3),
      const Gap(6),
      Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700,
              fontSize: 12, color: SeraTokens.fg3, letterSpacing: 0.3)),
    ]);
  }
}

// ── Edit sheet ────────────────────────────────────────────────────────────────

class _CrEditSheet extends StatefulWidget {
  final MeetingNote note;
  final void Function(MeetingNote) onSaved;
  const _CrEditSheet({required this.note, required this.onSaved});

  @override
  State<_CrEditSheet> createState() => _CrEditSheetState();
}

class _CrEditSheetState extends State<_CrEditSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note.rawNotes);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _saving = true);
    try {
      final resp = await ApiClient.dio.patch('/api/notes/${widget.note.id}',
          data: {'content': raw});
      final updated = MeetingNote.fromJson(resp.data as Map<String, dynamic>);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved(updated);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save failed'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

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
            child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const Gap(16),
          const Text('Edit Change Request',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const Gap(14),
          TextField(
            controller: _ctrl,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Describe your change request…',
              alignLabelWithHint: true,
            ),
          ),
          const Gap(16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save Changes'),
          ),
        ],
      ),
    );
  }
}
