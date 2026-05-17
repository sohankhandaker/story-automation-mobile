import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../models/task.dart';
import 'status_badge.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;

  const TaskCard({super.key, required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(8),
                  StatusBadge(status: task.status, small: true),
                ],
              ),
              if (task.isInProgress) ...[
                const Gap(10),
                _PhaseProgressBar(current: task.currentPhase, total: task.totalPhases),
              ],
              const Gap(8),
              Row(
                children: [
                  Icon(Icons.schedule, size: 12, color: cs.onSurfaceVariant),
                  const Gap(4),
                  Text(
                    _formatDate(task.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  if (task.reviewerName != null) ...[
                    const Gap(12),
                    Icon(Icons.person_outline, size: 12, color: cs.onSurfaceVariant),
                    const Gap(4),
                    Text(
                      task.reviewerName!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _PhaseProgressBar extends StatelessWidget {
  final int current;
  final int total;

  const _PhaseProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total > 0 ? current / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Phase $current/$total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary)),
            Text('${(pct * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary)),
          ],
        ),
        const Gap(4),
        LinearProgressIndicator(
          value: pct,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: cs.primaryContainer,
        ),
      ],
    );
  }
}
