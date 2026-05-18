import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import '../core/constants.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import '../providers/tasks_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/status_badge.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? taskId;
  const ChatScreen({super.key, required this.taskId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  bool _sending = false;
  String? _currentTaskId;
  Task? _task;
  Timer? _pollTimer;
  List<ReviewerItem> _mentionSuggestions = [];
  String _mentionQuery = '';

  @override
  void initState() {
    super.initState();
    _currentTaskId = widget.taskId;
    if (_currentTaskId != null) {
      _loadTask();
      _startPolling();
    }
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    if (cursor < 0) return;

    // Find the last '@' before the cursor
    final before = text.substring(0, cursor);
    final atIndex = before.lastIndexOf('@');

    if (atIndex != -1) {
      // Only trigger if '@' is at start or preceded by a space
      final charBefore = atIndex > 0 ? before[atIndex - 1] : ' ';
      if (charBefore == ' ' || atIndex == 0) {
        final query = before.substring(atIndex + 1).toLowerCase();
        // No spaces in the query = still typing the mention
        if (!query.contains(' ')) {
          final reviewers = ref.read(authProvider).user?.reviewerList ?? [];
          final filtered = reviewers.where((r) =>
              r.name.toLowerCase().contains(query) ||
              r.githubUsername.toLowerCase().contains(query)).toList();
          setState(() {
            _mentionQuery = query;
            _mentionSuggestions = filtered;
          });
          return;
        }
      }
    }
    if (_mentionSuggestions.isNotEmpty || _mentionQuery.isNotEmpty) {
      setState(() {
        _mentionSuggestions = [];
        _mentionQuery = '';
      });
    }
  }

  void _selectMention(ReviewerItem reviewer) {
    final text = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    final before = text.substring(0, cursor);
    final atIndex = before.lastIndexOf('@');
    final after = text.substring(cursor);
    final replacement = '@${reviewer.githubUsername} ';
    final newText = text.substring(0, atIndex) + replacement + after;
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: atIndex + replacement.length),
    );
    setState(() {
      _mentionSuggestions = [];
      _mentionQuery = '';
    });
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(
      const Duration(seconds: AppConstants.pollIntervalSeconds),
      (_) => _loadTask(),
    );
  }

  Future<void> _loadTask() async {
    if (_currentTaskId == null) return;
    try {
      final task =
          await ref.read(tasksProvider.notifier).getTask(_currentTaskId!);
      if (mounted) setState(() => _task = task);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() => _sending = true);

    try {
      if (_currentTaskId == null) {
        final result =
            await ref.read(tasksProvider.notifier).createTask(text);
        final taskId = result['task_id'] as String;
        setState(() => _currentTaskId = taskId);
        ref.invalidate(chatProvider(taskId));
        _loadTask();
        _startPolling();
      } else {
        await ref
            .read(chatProvider(_currentTaskId!).notifier)
            .sendMessage(text);
        await _loadTask();
      }
      _scrollToBottom();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markReady() async {
    if (_currentTaskId == null) return;
    try {
      await ref.read(tasksProvider.notifier).markReady(_currentTaskId!);
      await _loadTask();
      if (_currentTaskId != null) {
        ref.invalidate(chatProvider(_currentTaskId!));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _inputEnabled =>
      _task == null ||
      _task!.status == 'Backlog' ||
      _task!.status == 'In Review';

  @override
  Widget build(BuildContext context) {
    final messages = _currentTaskId != null
        ? ref.watch(chatProvider(_currentTaskId!))
        : <ChatMessage>[];

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FA),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          if (_task != null) _StatusBar(task: _task!, onMarkReady: _markReady),
          Expanded(
            child: messages.isEmpty && _task == null
                ? _EmptyChat(isNew: _currentTaskId == null)
                : ListView.builder(
                    controller: _scrollCtrl,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                    itemCount: messages.length + (_task?.isInProgress == true ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == messages.length && _task?.isInProgress == true) {
                        return AIWritingAnimation(task: _task!);
                      }
                      return ChatBubble(message: messages[i]);
                    },
                  ),
          ),
          if (_mentionSuggestions.isNotEmpty)
            _MentionSuggestions(
              suggestions: _mentionSuggestions,
              onSelect: _selectMention,
            ),
          _ChatInput(
            controller: _ctrl,
            focusNode: _focusNode,
            sending: _sending,
            enabled: _inputEnabled,
            onSend: _send,
            hint: _currentTaskId == null
                ? 'Describe your requirement...'
                : _task?.status == 'In Review'
                    ? '@username to assign a reviewer...'
                    : 'Add more details...',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: _task != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _task!.title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis),
                  maxLines: 1,
                ),
                const Gap(2),
                StatusBadge(status: _task!.status, small: true),
              ],
            )
          : const Text(
              'New Requirement',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
      actions: [
        if (_task?.githubIssueUrl != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'View on GitHub',
              onPressed: () {},
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE8EDF2)),
      ),
    );
  }
}

// ── Status bar ─────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final Task task;
  final VoidCallback onMarkReady;

  const _StatusBar({required this.task, required this.onMarkReady});

  @override
  Widget build(BuildContext context) {
    if (task.isInProgress) {
      final pct = task.totalPhases > 0
          ? task.currentPhase / task.totalPhases
          : 0.0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: pct > 0 ? pct : null,
                    color: kPrimary,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Generating phase ${task.currentPhase} of ${task.totalPhases}...',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kPrimary,
                    ),
                  ),
                ),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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
          Container(height: 1, color: const Color(0xFFE8EDF2)),
        ],
      );
    }

    if (task.canMarkReady) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ready to generate story?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Tap when you\'re done describing',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onMarkReady,
                  icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                  label: const Text('Mark as Ready',
                      style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE8EDF2)),
        ],
      );
    }

    if (task.status == 'In Review' && task.reviewerGithubUsername == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: const Color(0xFFFFF8E1),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: const Row(
              children: [
                Icon(Icons.tips_and_updates_rounded,
                    size: 16, color: Color(0xFFFF8F00)),
                Gap(8),
                Expanded(
                  child: Text(
                    'Type @GitHubUsername to assign a reviewer',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF795548),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE8EDF2)),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

// ── AI Writing Animation ───────────────────────────────────────────────────────

class AIWritingAnimation extends StatefulWidget {
  final Task task;
  const AIWritingAnimation({super.key, required this.task});

  @override
  State<AIWritingAnimation> createState() => _AIWritingAnimationState();
}

class _AIWritingAnimationState extends State<AIWritingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _flowCtrl;
  late AnimationController _shimmerCtrl;
  late Animation<double> _pulse;
  late Animation<double> _flow;
  late Animation<double> _shimmer;

  String _displayedText = '';
  int _charCount = 0;
  String? _lastPhase;

  String get _phaseName {
    final phases = widget.task.storyPhases;
    final current = widget.task.currentPhase;
    if (current <= 0 || phases.isEmpty) return 'Analyzing requirement…';
    final idx = current - 1;
    if (idx < phases.length && phases[idx].name.isNotEmpty) {
      return phases[idx].name;
    }
    return 'Writing phase $current…';
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _flowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _flow = Tween(begin: 0.0, end: 1.0).animate(_flowCtrl);

    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _shimmer = Tween(begin: -1.0, end: 2.0)
        .animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.linear));

    _startTypewriter();
  }

  @override
  void didUpdateWidget(AIWritingAnimation old) {
    super.didUpdateWidget(old);
    if (old.task.currentPhase != widget.task.currentPhase) {
      _startTypewriter();
    }
  }

  void _startTypewriter() {
    final phase = _phaseName;
    if (phase == _lastPhase) return;
    _lastPhase = phase;
    _charCount = 0;
    if (mounted) setState(() => _displayedText = '');
    _typeNext();
  }

  void _typeNext() {
    if (!mounted) return;
    final full = _phaseName;
    if (_charCount < full.length) {
      _charCount++;
      setState(() => _displayedText = full.substring(0, _charCount));
      Future.delayed(const Duration(milliseconds: 38), _typeNext);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _flowCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.task.totalPhases > 0
        ? widget.task.currentPhase / widget.task.totalPhases
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: kPrimary, shape: BoxShape.circle),
              ),
              const Gap(6),
              const Text('AI Agent',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                      letterSpacing: .4)),
            ],
          ),
          const Gap(6),

          // Main card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: kPrimary.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                // Flow visualiser
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      // AI orb
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Transform.scale(
                          scale: _pulse.value,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [kPrimary, Color(0xFF0A5FC4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kPrimary.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 24),
                          ),
                        ),
                      ),

                      // Flowing dots
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _flow,
                          builder: (_, __) => CustomPaint(
                            size: const Size(double.infinity, 52),
                            painter: _FlowDotsPainter(_flow.value),
                          ),
                        ),
                      ),

                      // Document icon with shimmer fill
                      AnimatedBuilder(
                        animation: _shimmer,
                        builder: (_, __) => Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                                color: kPrimary.withValues(alpha: 0.25)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                // Shimmer sweep
                                Positioned.fill(
                                  child: ShaderMask(
                                    shaderCallback: (bounds) =>
                                        LinearGradient(
                                      begin: Alignment(_shimmer.value - 1, 0),
                                      end: Alignment(_shimmer.value, 0),
                                      colors: [
                                        Colors.transparent,
                                        kPrimary.withValues(alpha: 0.15),
                                        Colors.transparent,
                                      ],
                                    ).createShader(bounds),
                                    child: Container(color: Colors.white),
                                  ),
                                ),
                                const Center(
                                  child: Icon(Icons.description_rounded,
                                      color: kPrimary, size: 26),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Phase name typewriter
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _displayedText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A2B3C),
                            height: 1.3,
                          ),
                        ),
                      ),
                      // Blinking cursor
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Opacity(
                          opacity: _pulseCtrl.value,
                          child: Container(
                            width: 2,
                            height: 16,
                            decoration: BoxDecoration(
                              color: kPrimary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: kPrimaryLight,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(kPrimary),
                        ),
                      ),
                      const Gap(6),
                      Text(
                        'Phase ${widget.task.currentPhase} of ${widget.task.totalPhases}  ·  ${(progress * 100).round()}% complete',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowDotsPainter extends CustomPainter {
  final double progress;
  _FlowDotsPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const dotCount = 5;
    const dotRadius = 3.5;
    final cy = size.height / 2;

    for (int i = 0; i < dotCount; i++) {
      final t = ((progress + i / dotCount) % 1.0);
      final x = size.width * t;
      final opacity = (math.sin(t * math.pi)).clamp(0.0, 1.0);
      final scale = 0.5 + 0.5 * math.sin(t * math.pi);

      final paint = Paint()
        ..color = kPrimary.withValues(alpha: opacity * 0.85)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, cy), dotRadius * scale, paint);
    }

    // Line
    final linePaint = Paint()
      ..color = kPrimary.withValues(alpha: 0.12)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), linePaint);
  }

  @override
  bool shouldRepaint(_FlowDotsPainter old) => old.progress != progress;
}

// ── Mention suggestions ────────────────────────────────────────────────────────

class _MentionSuggestions extends StatelessWidget {
  final List<ReviewerItem> suggestions;
  final ValueChanged<ReviewerItem> onSelect;

  const _MentionSuggestions({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE8EDF2)),
          bottom: BorderSide(color: Color(0xFFE8EDF2)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 56, endIndent: 16),
        itemBuilder: (_, i) {
          final r = suggestions[i];
          final initial = r.name.substring(0, 1).toUpperCase();
          return InkWell(
            onTap: () => onSelect(r),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kPrimary, kPrimaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('@${r.githubUsername}',
                            style: const TextStyle(
                                color: kPrimary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.north_west_rounded,
                      size: 14, color: Color(0xFFAAB8C5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Empty chat ─────────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  final bool isNew;
  const _EmptyChat({required this.isNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: kPrimary,
              ),
            ),
            const Gap(20),
            Text(
              isNew ? 'Start with a requirement' : 'No messages yet',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xFF1A2B3C),
              ),
            ),
            const Gap(8),
            Text(
              isNew
                  ? 'Describe what you need and the AI agent will create a GitHub backlog item for you.'
                  : 'Messages will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7A8D),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat input ─────────────────────────────────────────────────────────────────

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;
  final String hint;

  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.enabled,
    required this.onSend,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE8EDF2))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5FA),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD8E3ED)),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled && !sending,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      const TextStyle(color: Color(0xFFAAB8C5), fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  fillColor: Colors.transparent,
                  filled: false,
                ),
              ),
            ),
          ),
          const Gap(8),
          _SendButton(sending: sending, enabled: enabled, onSend: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  const _SendButton({
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: enabled && !sending
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimary, Color(0xFF0A5FC4)],
              )
            : null,
        color: enabled && !sending ? null : const Color(0xFFD8E3ED),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled && !sending ? onSend : null,
          child: Center(
            child: sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: enabled ? Colors.white : const Color(0xFFAAB8C5),
                  ),
          ),
        ),
      ),
    );
  }
}
