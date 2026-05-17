import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import '../core/constants.dart';
import '../models/task.dart';
import '../models/chat_message.dart';
import '../providers/tasks_provider.dart';
import '../providers/chat_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _currentTaskId = widget.taskId;
    if (_currentTaskId != null) {
      _loadTask();
      _startPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
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
            child: messages.isEmpty
                ? _EmptyChat(isNew: _currentTaskId == null)
                : ListView.builder(
                    controller: _scrollCtrl,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => ChatBubble(message: messages[i]),
                  ),
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
                    ? '@GitHubUsername please review...'
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
