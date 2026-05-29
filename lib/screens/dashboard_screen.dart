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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: const Color(0xFFF0F3F8)),
          NavigationBar(
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
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF04111F), Color(0xFF0A3468), Color(0xFF0D6FD8)],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative ring
          Positioned(
            right: -20,
            top: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: -20,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF40A9FF).withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
            ),
          ),
          // Content
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF40A9FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Gap(7),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 11.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const Gap(10),
                    Text(
                      greeting,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1,
                      ),
                    ),
                    const Gap(6),
                    const Text(
                      'BRD → PRD pipeline overview',
                      style: TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const Gap(12),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0D1B2A),
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
            const Gap(3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D1B2A),
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF8896A5),
              ),
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
      width: 116,
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: count > 0 ? const Color(0xFF0D1B2A) : const Color(0xFFCBD5E1),
                  letterSpacing: -0.5,
                  height: 1,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            status,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A6A7E),
              height: 1.25,
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
    final (icon, color) = _statusMeta[note.status] ??
        (Icons.circle_outlined, kPrimary);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title ?? 'Untitled Note',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    const Gap(4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        note.status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1),
                size: 20,
              ),
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
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: kPrimaryLight,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.note_alt_outlined, size: 38, color: kPrimary),
        ),
        const Gap(18),
        const Text(
          'No meeting notes yet',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Color(0xFF0D1B2A),
            letterSpacing: -0.2,
          ),
        ),
        const Gap(7),
        const Text(
          'Tap Notes to capture your first\nmeeting and start the BRD pipeline.',
          style: TextStyle(
            color: Color(0xFF6B7A8D),
            fontSize: 13.5,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
