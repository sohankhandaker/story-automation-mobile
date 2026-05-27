import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import 'notes_screen.dart' show NotesTab, NewNoteSheet, notesProvider, MeetingNote;
import 'settings_screen.dart' show SettingsTab;

// ── Status metadata ───────────────────────────────────────────────────────────

const _statusMeta = {
  'Draft': (Icons.edit_note_rounded, Color(0xFF78909C)),
  'In Progress': (Icons.autorenew_rounded, Color(0xFFFF8F00)),
  'Pending Review': (Icons.hourglass_top_rounded, Color(0xFF1E88E5)),
  'In Review': (Icons.rate_review_rounded, Color(0xFF8E24AA)),
  'Changes Requested': (Icons.feedback_rounded, Color(0xFFE53935)),
  'Approved': (Icons.task_alt_rounded, Color(0xFF43A047)),
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
        children: [
          _HomeTab(onGoToNotes: () => setState(() => _selectedIndex = 1)),
          const NotesTab(),
          const SettingsTab(),
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
      floatingActionButton: _selectedIndex == 1
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
              onPressed: () => ref.read(notesProvider.notifier).fetchNotes(),
            ),
          ],
        );
      case 1:
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
  final VoidCallback onGoToNotes;
  const _HomeTab({required this.onGoToNotes});

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
      data: (notes) => RefreshIndicator(
        onRefresh: () => ref.read(notesProvider.notifier).fetchNotes(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const _WelcomeBanner(),
            const Gap(20),
            _PipelineStatsSection(notes: notes),
            if (notes.any((n) => n.status == 'Pending Review')) ...[
              const Gap(24),
              const _SectionHeader(
                title: 'Action Needed',
                icon: Icons.notification_important_rounded,
                color: Color(0xFF1E88E5),
              ),
              const Gap(10),
              ...notes
                  .where((n) => n.status == 'Pending Review')
                  .map((n) => _NoteSummaryCard(note: n, onTap: onGoToNotes)),
            ],
            if (notes.any((n) => n.status == 'In Progress')) ...[
              const Gap(24),
              const _SectionHeader(
                title: 'In Progress',
                icon: Icons.autorenew_rounded,
                color: Color(0xFFFF8F00),
              ),
              const Gap(10),
              ...notes
                  .where((n) => n.status == 'In Progress')
                  .map((n) => _NoteSummaryCard(note: n, onTap: onGoToNotes)),
            ],
            if (notes.isEmpty) ...[
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
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

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
                  '$greeting! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(4),
                const Text(
                  'Your BRD → PRD pipeline at a glance.',
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

// ── Pipeline stats ────────────────────────────────────────────────────────────

class _PipelineStatsSection extends StatelessWidget {
  final List<MeetingNote> notes;
  const _PipelineStatsSection({required this.notes});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final n in notes) {
      counts[n.status] = (counts[n.status] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _BigStatCard(
              label: 'Total',
              sublabel: 'meeting notes',
              count: notes.length,
              icon: Icons.note_alt_rounded,
              color: kPrimary,
            ),
            const Gap(10),
            _BigStatCard(
              label: 'Approved',
              sublabel: 'BRDs complete',
              count: counts['Approved'] ?? 0,
              icon: Icons.task_alt_rounded,
              color: const Color(0xFF43A047),
            ),
          ],
        ),
        const Gap(14),
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
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _statusMeta.length,
            separatorBuilder: (_, __) => const Gap(10),
            itemBuilder: (_, i) {
              final status = _statusMeta.keys.toList()[i];
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

// ── Note summary card ─────────────────────────────────────────────────────────

class _NoteSummaryCard extends StatelessWidget {
  final MeetingNote note;
  final VoidCallback onTap;
  const _NoteSummaryCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (_, color) = _statusMeta[note.status] ?? (Icons.circle, kPrimary);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title ?? 'Untitled Note',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Gap(6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: color.withValues(alpha: 0.3), width: 1),
                      ),
                      child: Text(
                        note.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
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
          child: const Icon(Icons.note_alt_outlined, size: 48, color: kPrimary),
        ),
        const Gap(16),
        const Text(
          'No meeting notes yet',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const Gap(6),
        const Text(
          'Go to Notes tab to add your first meeting note',
          style: TextStyle(color: Color(0xFF6B7A8D), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
