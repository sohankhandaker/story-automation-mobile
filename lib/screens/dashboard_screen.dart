import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import 'projects_screen.dart' show ProjectsTab, NewProjectSheet, projectsProvider;
import 'customers_screen.dart' show CustomersTab, CustomerFormSheet, customersProvider;
import 'settings_screen.dart' show SettingsTab;
import 'notes_screen.dart' show notesProvider, MeetingNote;

// ── Dashboard shell ───────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  static const _titles = ['Dashboard', 'Projects', 'Customers', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _DashboardTab(),
          ProjectsTab(),
          CustomersTab(),
          SettingsTab(),
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
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Projects',
              ),
              NavigationDestination(
                icon: Icon(Icons.business_outlined),
                selectedIcon: Icon(Icons.business_rounded),
                label: 'Customer',
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
      floatingActionButton: switch (_selectedIndex) {
        1 => FloatingActionButton.extended(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const NewProjectSheet(),
            ),
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Project',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        2 => FloatingActionButton.extended(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const CustomerFormSheet(),
            ),
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Customer',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        _ => null,
      },
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    if (_selectedIndex == 0) {
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
            Text('Story Automation',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: cs.onSurface)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(projectsProvider.notifier).fetch();
              ref.read(notesProvider.notifier).fetchNotes();
              ref.read(customersProvider.notifier).fetch();
            },
          ),
        ],
      );
    }
    return AppBar(
      title: Text(_titles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold)),
      actions: [
        if (_selectedIndex == 1)
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(projectsProvider.notifier).fetch(),
          ),
        if (_selectedIndex == 2)
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(customersProvider.notifier).fetch(),
          ),
      ],
    );
  }
}

// ── Dashboard tab ─────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final notesAsync = ref.watch(notesProvider);
    final customersAsync = ref.watch(customersProvider);

    final projects = projectsAsync.valueOrNull ?? [];
    final notes = notesAsync.valueOrNull ?? [];
    final customers = customersAsync.valueOrNull ?? [];

    final loading = projectsAsync.isLoading && notesAsync.isLoading;
    if (loading) return const Center(child: CircularProgressIndicator());

    final actionNeeded = notes.where((n) => n.status == 'Pending Review').toList();
    final inProgress = notes.where((n) => n.status == 'In Progress').toList();

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(projectsProvider.notifier).fetch();
        await ref.read(notesProvider.notifier).fetchNotes();
        await ref.read(customersProvider.notifier).fetch();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          _WelcomeBanner(),
          const Gap(20),
          // Stats row
          Row(
            children: [
              _StatCard(
                icon: Icons.folder_rounded,
                label: 'Projects',
                count: projects.length,
                color: kPrimary,
              ),
              const Gap(10),
              _StatCard(
                icon: Icons.business_rounded,
                label: 'Customers',
                count: customers.length,
                color: const Color(0xFF4F46E5),
              ),
              const Gap(10),
              _StatCard(
                icon: Icons.task_alt_rounded,
                label: 'BRDs Done',
                count: notes.where((n) => n.status == 'Approved').length,
                color: const Color(0xFF43A047),
              ),
            ],
          ),
          if (actionNeeded.isNotEmpty) ...[
            const Gap(24),
            _SectionHeader(
              title: 'Action Needed',
              icon: Icons.notification_important_rounded,
              color: const Color(0xFF1E88E5),
            ),
            const Gap(10),
            ...actionNeeded.map((n) => _NoteActionCard(note: n)),
          ],
          if (inProgress.isNotEmpty) ...[
            const Gap(24),
            _SectionHeader(
              title: 'In Progress',
              icon: Icons.autorenew_rounded,
              color: const Color(0xFFFF8F00),
            ),
            const Gap(10),
            ...inProgress.map((n) => _NoteActionCard(note: n)),
          ],
          if (projects.isEmpty && notes.isEmpty) ...[
            const Gap(40),
            _EmptyDashboard(),
          ],
        ],
      ),
    );
  }
}

// ── Welcome banner ────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 4, height: 4,
                      decoration: const BoxDecoration(color: Color(0xFF40A9FF), shape: BoxShape.circle)),
                  const Gap(7),
                  Text(dateStr, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11.5)),
                ]),
                const Gap(10),
                Text(greeting, style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800,
                    letterSpacing: -0.3, height: 1)),
                const Gap(6),
                const Text('BRD → PRD pipeline overview',
                    style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: color, size: 16),
            ),
            const Gap(10),
            Text('$count',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                    color: Color(0xFF0D1B2A), letterSpacing: -0.5, height: 1)),
            const Gap(2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8896A5), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 14, color: color),
        ),
        const Gap(8),
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }
}

// ── Note action card (minimal, tap goes to Notes tab) ─────────────────────────

class _NoteActionCard extends StatelessWidget {
  final MeetingNote note;
  const _NoteActionCard({required this.note});

  @override
  Widget build(BuildContext context) {
    const statusColors = {
      'Pending Review': Color(0xFF1E88E5),
      'In Progress': Color(0xFFFF8F00),
      'In Review': Color(0xFF8E24AA),
      'Changes Requested': Color(0xFFE53935),
    };
    final color = statusColors[note.status] ?? kPrimary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.description_rounded, size: 17, color: color),
            ),
            const Gap(11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(note.title ?? 'Untitled Note', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF0D1B2A))),
                const Gap(3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                  child: Text(note.status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Empty dashboard ───────────────────────────────────────────────────────────

class _EmptyDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.auto_awesome_rounded, size: 38, color: kPrimary),
        ),
        const Gap(18),
        const Text('Welcome to Story Automation',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16,
                color: Color(0xFF0D1B2A), letterSpacing: -0.2)),
        const Gap(8),
        const Text('Start by adding a Customer, then create\na Project to begin your BRD pipeline.',
            style: TextStyle(color: Color(0xFF6B7A8D), fontSize: 13.5, height: 1.5),
            textAlign: TextAlign.center),
      ],
    );
  }
}
