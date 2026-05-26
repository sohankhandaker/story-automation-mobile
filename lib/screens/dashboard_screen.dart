import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import '../providers/auth_provider.dart';
import '../providers/tasks_provider.dart';
import '../models/task.dart';
import '../widgets/status_badge.dart';
import '../widgets/task_card.dart';
import 'chat_screen.dart';
import 'notes_screen.dart' show NotesTab, NewNoteSheet;
import 'settings_screen.dart' show SettingsTab;

// ── Status metadata ───────────────────────────────────────────────────────────

const _statusMeta = {
  'Backlog': (Icons.inbox_rounded, Color(0xFF78909C)),
  'Ready': (Icons.rocket_launch_rounded, Color(0xFF1E88E5)),
  'In Progress': (Icons.autorenew_rounded, Color(0xFFFF8F00)),
  'In Review': (Icons.rate_review_rounded, Color(0xFF8E24AA)),
  'Changes Requested': (Icons.edit_note_rounded, Color(0xFFE53935)),
  'Done': (Icons.task_alt_rounded, Color(0xFF43A047)),
};

// ── Dashboard shell ───────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _HomeTab(),
          _TasksTab(),
          NotesTab(),
          SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_outlined),
            selectedIcon: Icon(Icons.task_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_alt_outlined),
            selectedIcon: Icon(Icons.note_alt_rounded),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatScreen(taskId: null)),
              ),
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'New Requirement',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : _selectedIndex == 2
              ? FloatingActionButton.extended(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const NewNoteSheet(),
                  ),
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'New Meeting Note',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                )
              : null,
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    switch (_selectedIndex) {
      case 0:
        return AppBar(
          title: Row(
            children: [
              SvgPicture.asset(
                'assets/images/selise_logo_white.svg',
                height: 22,
                colorFilter: const ColorFilter.mode(kPrimary, BlendMode.srcIn),
              ),
              const Gap(10),
              Container(width: 1, height: 18, color: cs.outlineVariant),
              const Gap(10),
              Text(
                'Story Automation',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () => ref.read(tasksProvider.notifier).fetchTasks(),
            ),
          ],
        );
      case 1:
        return AppBar(
          title: const Text('My Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () => ref.read(tasksProvider.notifier).fetchTasks(),
            ),
          ],
        );
      case 2:
        return AppBar(
          title: const Text('Meeting Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        );
      default:
        return AppBar(
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        );
    }
  }
}

// ── Home tab ──────────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final tasksAsync = ref.watch(tasksProvider);

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const Gap(12),
            Text('$e'),
            TextButton(
              onPressed: () => ref.read(tasksProvider.notifier).fetchTasks(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (tasks) => RefreshIndicator(
        onRefresh: () => ref.read(tasksProvider.notifier).fetchTasks(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _WelcomeBanner(name: auth.user?.name ?? ''),
            const Gap(20),
            _StatusTilesSection(tasks: tasks),
            if (tasks.any((t) => t.status == 'In Review' && t.reviewerGithubUsername == null)) ...[
              const Gap(24),
              const _SectionHeader(
                title: 'Action Needed',
                icon: Icons.notification_important_rounded,
                color: Color(0xFFE53935),
              ),
              const Gap(10),
              ...tasks
                  .where((t) => t.status == 'In Review' && t.reviewerGithubUsername == null)
                  .map((t) => _SummaryCard(task: t)),
            ],
            if (tasks.any((t) => t.isInProgress)) ...[
              const Gap(24),
              const _SectionHeader(
                title: 'In Progress',
                icon: Icons.autorenew_rounded,
                color: Color(0xFFFF8F00),
              ),
              const Gap(10),
              ...tasks.where((t) => t.isInProgress).map((t) => _SummaryCard(task: t)),
            ],
            if (tasks.isEmpty) ...[
              const Gap(40),
              const _EmptyState(),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Welcome banner ────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  final String name;
  const _WelcomeBanner({required this.name});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final firstName = name.split(' ').first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimary, Color(0xFF0A5FC4)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $firstName! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(4),
                const Text(
                  'What would you like to automate today?',
                  style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.auto_awesome_rounded, color: Color(0xCCFFFFFF), size: 36),
        ],
      ),
    );
  }
}

// ── Status tiles ──────────────────────────────────────────────────────────────

class _StatusTilesSection extends StatelessWidget {
  final List<Task> tasks;
  const _StatusTilesSection({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final t in tasks) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }

    final statuses = _statusMeta.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total + Done summary row
        Row(
          children: [
            _BigStatCard(
              label: 'Total',
              sublabel: 'requirements',
              count: tasks.length,
              icon: Icons.layers_rounded,
              color: kPrimary,
            ),
            const Gap(10),
            _BigStatCard(
              label: 'Completed',
              sublabel: 'stories done',
              count: counts['Done'] ?? 0,
              icon: Icons.task_alt_rounded,
              color: const Color(0xFF43A047),
            ),
          ],
        ),
        const Gap(14),
        // Status label
        const Text(
          'By Status',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8896A5),
            letterSpacing: 0.5,
          ),
        ),
        const Gap(10),
        // Horizontal scroll status tiles
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: statuses.length,
            separatorBuilder: (_, __) => const Gap(10),
            itemBuilder: (_, i) {
              final status = statuses[i];
              final (icon, color) = _statusMeta[status]!;
              return _StatusTile(
                status: status,
                count: counts[status] ?? 0,
                icon: icon,
                color: color,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final int count;
  final IconData icon;
  final Color color;

  const _BigStatCard({
    required this.label,
    required this.sublabel,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.12),
              color.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1,
                  ),
                ),
                const Gap(2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String status;
  final int count;
  final IconData icon;
  final Color color;

  const _StatusTile({
    required this.status,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const Gap(8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final Task task;
  const _SummaryCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(taskId: task.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Gap(6),
                    StatusBadge(status: task.status, small: true),
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
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: kPrimaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.inbox_rounded, size: 48, color: kPrimary),
        ),
        const Gap(16),
        const Text(
          'No requirements yet',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const Gap(6),
        const Text(
          'Tap + New Requirement to get started',
          style: TextStyle(color: Color(0xFF6B7A8D), fontSize: 14),
        ),
      ],
    );
  }
}

// ── Tasks tab ─────────────────────────────────────────────────────────────────

class _TasksTab extends ConsumerWidget {
  const _TasksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const Gap(12),
            Text('$e'),
            TextButton(
              onPressed: () => ref.read(tasksProvider.notifier).fetchTasks(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (tasks) {
        if (tasks.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.task_outlined, size: 64, color: Color(0xFFB0BEC5)),
                Gap(12),
                Text(
                  'No tasks yet',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                Gap(4),
                Text(
                  'Create one from Dashboard',
                  style: TextStyle(color: Color(0xFF6B7A8D)),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(tasksProvider.notifier).fetchTasks(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: tasks.length,
            itemBuilder: (_, i) => TaskCard(
              task: tasks[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ChatScreen(taskId: tasks[i].id)),
              ),
            ),
          ),
        );
      },
    );
  }
}
