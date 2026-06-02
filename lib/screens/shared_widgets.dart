// lib/screens/shared_widgets.dart — refactored to use SeraTokens.
// The animated AI-agent→document generation view + multi-URL wiki input.
// Animation timing/curves are unchanged from your original.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../theme/sera_tokens.dart';

// ── Generation progress (AI agent → document animated view) ──────────────────

class GenerationProgressWidget extends StatefulWidget {
  final int? phase;
  final List<String> phaseNames; // index 0 = '', indices 1..n = phase names
  final bool isUpdate;
  final String documentLabel; // 'BRD' or 'PRD'

  const GenerationProgressWidget({
    super.key,
    required this.phase,
    required this.phaseNames,
    required this.documentLabel,
    this.isUpdate = false,
  });

  @override
  State<GenerationProgressWidget> createState() =>
      _GenerationProgressWidgetState();
}

class _GenerationProgressWidgetState extends State<GenerationProgressWidget>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _flowCtrl;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _pulse;
  late final Animation<double> _flow;
  late final Animation<double> _shimmer;

  String _displayedText = '';
  int _charCount = 0;
  String? _lastPhase;

  String get _currentPhaseName {
    if (widget.isUpdate) return 'Applying your changes…';
    final p = widget.phase;
    if (p == null || p <= 0) return 'Starting ${widget.documentLabel} generation…';
    final names = widget.phaseNames;
    if (p < names.length && names[p].isNotEmpty) return names[p];
    return 'Finalizing ${widget.documentLabel}…';
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.88, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _flowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _flow = Tween(begin: 0.0, end: 1.0).animate(_flowCtrl);

    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _shimmer = Tween(begin: -1.0, end: 2.0).animate(
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.linear));

    _startTypewriter();
  }

  @override
  void didUpdateWidget(GenerationProgressWidget old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase || old.isUpdate != widget.isUpdate) {
      _startTypewriter();
    }
  }

  void _startTypewriter() {
    final name = _currentPhaseName;
    if (name == _lastPhase) return;
    _lastPhase = name;
    _charCount = 0;
    if (mounted) setState(() => _displayedText = '');
    _typeNext();
  }

  void _typeNext() {
    if (!mounted) return;
    final full = _currentPhaseName;
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
    final totalPhases = widget.phaseNames.length - 1;
    final p = widget.phase;
    final hasPhase =
        !widget.isUpdate && p != null && p > 0 && p < widget.phaseNames.length;
    final int phaseVal = hasPhase ? p : 0;
    final progress =
        hasPhase ? phaseVal / totalPhases : (widget.isUpdate ? null : 0.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header label
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: SeraTokens.primary, shape: BoxShape.circle),
            ),
            const Gap(6),
            Text(
              'AI Agent  →  ${widget.documentLabel}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: SeraTokens.primary,
                letterSpacing: .4,
              ),
            ),
          ]),
          const Gap(8),

          // ── Animation card ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(SeraTokens.r2xl),
              boxShadow: [
                BoxShadow(
                  color: SeraTokens.primary.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      // Pulsing AI orb
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Transform.scale(
                          scale: _pulse.value,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [SeraTokens.primary, SeraTokens.primaryDeep],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: SeraTokens.primary.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                ),
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
                      // Shimmer document icon
                      AnimatedBuilder(
                        animation: _shimmer,
                        builder: (_, __) => Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: SeraTokens.surfaceBlue,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                                color: SeraTokens.primary.withValues(alpha: 0.25)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      begin: Alignment(_shimmer.value - 1, 0),
                                      end: Alignment(_shimmer.value, 0),
                                      colors: [
                                        Colors.transparent,
                                        SeraTokens.primary.withValues(alpha: 0.15),
                                        Colors.transparent,
                                      ],
                                    ).createShader(bounds),
                                    child: Container(color: Colors.white),
                                  ),
                                ),
                                const Center(
                                  child: Icon(Icons.description_rounded,
                                      color: SeraTokens.primary, size: 26),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Typewriter phase name + blinking cursor
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _displayedText.isEmpty ? '…' : _displayedText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: SeraTokens.fg1Alt,
                            height: 1.3,
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Opacity(
                          opacity: _pulseCtrl.value,
                          child: Container(
                            width: 2,
                            height: 16,
                            decoration: BoxDecoration(
                              color: SeraTokens.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Progress bar + label
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
                          backgroundColor: SeraTokens.primaryLight,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              SeraTokens.primary),
                        ),
                      ),
                      const Gap(6),
                      Text(
                        hasPhase
                            ? 'Phase $phaseVal of $totalPhases  ·  ${(progress! * 100).round()}% complete'
                            : (widget.isUpdate
                                ? 'About 30–60 seconds'
                                : 'Initializing…'),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Step completion list ────────────────────────────────────────
          if (!widget.isUpdate && totalPhases > 0) ...[
            const Gap(22),
            Text(
              'STEPS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: SeraTokens.muted,
                letterSpacing: 1.0,
              ),
            ),
            const Gap(10),
            ...List.generate(totalPhases, (i) {
              final stepNum = i + 1;
              final isCompleted = hasPhase && stepNum < phaseVal;
              final isCurrent = hasPhase && stepNum == phaseVal;
              final name = stepNum < widget.phaseNames.length
                  ? widget.phaseNames[stepNum]
                  : 'Step $stepNum';
              return _StepRow(
                  name: name, isCompleted: isCompleted, isCurrent: isCurrent);
            }),
          ],
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

    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      Paint()
        ..color = SeraTokens.primary.withValues(alpha: 0.12)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    for (int i = 0; i < dotCount; i++) {
      final t = ((progress + i / dotCount) % 1.0);
      final x = size.width * t;
      final opacity = math.sin(t * math.pi).clamp(0.0, 1.0);
      final scale = 0.5 + 0.5 * math.sin(t * math.pi);
      canvas.drawCircle(
        Offset(x, cy),
        dotRadius * scale,
        Paint()
          ..color = SeraTokens.primary.withValues(alpha: opacity * 0.85)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowDotsPainter old) => old.progress != progress;
}

class _StepRow extends StatelessWidget {
  final String name;
  final bool isCompleted;
  final bool isCurrent;

  const _StepRow({
    required this.name,
    required this.isCompleted,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? SeraTokens.statusApproved
                  : isCurrent
                      ? SeraTokens.primary
                      : Colors.transparent,
              border: Border.all(
                color: isCompleted
                    ? SeraTokens.statusApproved
                    : isCurrent
                        ? SeraTokens.primary
                        : SeraTokens.disabled,
                width: 2,
              ),
            ),
            child: isCompleted
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : null,
          ),
          const Gap(10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: isCompleted
                    ? SeraTokens.statusApproved
                    : isCurrent
                        ? SeraTokens.primary
                        : SeraTokens.muted,
              ),
            ),
          ),
          if (isCurrent)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: SeraTokens.primary),
            ),
        ],
      ),
    );
  }
}

// ── WikiUrlInput ──────────────────────────────────────────────────────────────

class WikiUrlInput extends StatelessWidget {
  final TextEditingController controller;
  final List<String> urls;
  final VoidCallback onAdd;
  final void Function(String) onRemove;

  const WikiUrlInput({
    super.key,
    required this.controller,
    required this.urls,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              decoration: const InputDecoration(
                hintText: 'Paste Wiki / Confluence / Notion URL',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Gap(8),
          FilledButton.tonal(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              minimumSize: const Size(56, 48),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.add_rounded, size: 20),
          ),
        ]),
        if (urls.isNotEmpty) ...[
          const Gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: urls.map((url) {
              final label = url.length > 40 ? '${url.substring(0, 40)}…' : url;
              return Chip(
                avatar: Icon(Icons.link_rounded, size: 14, color: cs.primary),
                label: Text(label, style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => onRemove(url),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
