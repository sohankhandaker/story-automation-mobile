import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../providers/auth_provider.dart' show authProvider;
import '../theme/sera_tokens.dart';
import 'projects_screen.dart' show projectsProvider;
import 'customers_screen.dart' show Customer, CustomersTab, CustomerFormSheet, customersProvider;
import 'customer_detail_screen.dart' show CustomerDetailScreen;
import 'settings_screen.dart' show SettingsTab;
import 'notes_screen.dart' show notesProvider, MeetingNote, NoteDetailScreen;

// ── Dashboard shell ───────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  // 0 = Dashboard, 1 = Customers, 2 = Settings
  static const _titles = ['Dashboard', 'Customers', 'Settings'];

  void _openCustomerDetail(BuildContext context, Customer customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customer: customer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const _DashboardTab(),
          CustomersTab(
            onCustomerTap: (c) => _openCustomerDetail(context, c),
            onDeleted: () {
              ref.read(projectsProvider.notifier).fetch();
              ref.read(notesProvider.notifier).fetchNotes();
            },
          ),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: SeraTokens.divider),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              setState(() => _selectedIndex = i);
              // Refresh all data when switching back to Dashboard
              if (i == 0) {
                ref.read(projectsProvider.notifier).fetch();
                ref.read(notesProvider.notifier).fetchNotes();
                ref.read(customersProvider.notifier).fetch();
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.business_outlined),
                selectedIcon: Icon(Icons.business_rounded),
                label: 'Customers',
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
                builder: (_) => const CustomerFormSheet(),
              ),
              backgroundColor: SeraTokens.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Customer',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    final user = ref.watch(authProvider).user;
    if (_selectedIndex == 0) {
      return AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/images/selise_logo_white.svg',
              height: 22,
              colorFilter: const ColorFilter.mode(
                  SeraTokens.primary, BlendMode.srcIn),
            ),
            const Gap(10),
            Container(width: 1, height: 18, color: SeraTokens.border),
            const Gap(10),
            Text('SERA',
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
          if (user?.avatarUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: NetworkImage(user!.avatarUrl!),
                backgroundColor: SeraTokens.primaryLight,
              ),
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
            tooltip: 'Refresh',
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
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: SeraTokens.primary));
    }

    final actionNeeded = notes.where((n) => n.status == 'Pending Review').toList();
    final inProgress = notes.where((n) => n.status == 'In Progress').toList();

    return RefreshIndicator(
      color: SeraTokens.primary,
      onRefresh: () async {
        await ref.read(projectsProvider.notifier).fetch();
        await ref.read(notesProvider.notifier).fetchNotes();
        await ref.read(customersProvider.notifier).fetch();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          const _WelcomeBanner(),
          const Gap(20),
          Row(
            children: [
              _StatCard(
                icon: Icons.folder_rounded,
                label: 'Projects',
                count: projects.length,
                color: SeraTokens.primary,
              ),
              const Gap(10),
              _StatCard(
                icon: Icons.business_rounded,
                label: 'Customers',
                count: customers.length,
                color: SeraTokens.statusPendingReview,
              ),
              const Gap(10),
              _StatCard(
                icon: Icons.task_alt_rounded,
                label: 'BRDs Done',
                count: notes.where((n) => n.status == 'Approved').length,
                color: SeraTokens.statusApproved,
              ),
            ],
          ),
          if (actionNeeded.isNotEmpty) ...[
            const Gap(24),
            const _SectionHeader(
              title: 'Action Needed',
              icon: Icons.notification_important_rounded,
              color: SeraTokens.statusInfo,
            ),
            const Gap(10),
            ...actionNeeded.map((n) => _NoteActionCard(note: n)),
          ],
          if (inProgress.isNotEmpty) ...[
            const Gap(24),
            const _SectionHeader(
              title: 'In Progress',
              icon: Icons.autorenew_rounded,
              color: SeraTokens.statusInProgressWarm,
            ),
            const Gap(10),
            ...inProgress.map((n) => _NoteActionCard(note: n)),
          ],
          if (projects.isEmpty && notes.isEmpty) ...[
            const Gap(40),
            const _EmptyDashboard(),
          ],
        ],
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
    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: SeraTokens.heroGradient,
        borderRadius: BorderRadius.circular(SeraTokens.r3xl),
        boxShadow: SeraTokens.bannerGlow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20, top: -30,
            child: Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
              ),
            ),
          ),
          Positioned(
            right: 10, bottom: -20,
            child: Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: SeraTokens.accent.withValues(alpha: 0.18), width: 1),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 4, height: 4,
                        decoration: const BoxDecoration(
                            color: SeraTokens.accent, shape: BoxShape.circle),
                      ),
                      const Gap(7),
                      Text(dateStr,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11.5, letterSpacing: 0.3)),
                    ]),
                    const Gap(10),
                    const Text('BRD → PRD pipeline overview',
                        style: TextStyle(
                            color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3, height: 1)),
                    const Gap(6),
                    Text(greeting,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(SeraTokens.rXl),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 22),
              ),
            ],
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

  const _StatCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: SeraTokens.surfaceCard,
          borderRadius: BorderRadius.circular(SeraTokens.rXl),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(SeraTokens.rSm)),
              child: Icon(icon, color: color, size: 16),
            ),
            const Gap(10),
            Text('$count',
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: SeraTokens.fg1,
                    letterSpacing: -0.5,
                    height: 1)),
            const Gap(2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: SeraTokens.muted,
                    fontWeight: FontWeight.w600)),
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

  const _SectionHeader(
      {required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SeraTokens.rXs)),
          child: Icon(icon, size: 14, color: color),
        ),
        const Gap(8),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: SeraTokens.fg1)),
      ],
    );
  }
}

// ── Note action card ──────────────────────────────────────────────────────────

class _NoteActionCard extends StatelessWidget {
  final MeetingNote note;
  const _NoteActionCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final color = SeraTokens.statusColors[note.status] ?? SeraTokens.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(SeraTokens.rLg),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: SeraTokens.surfaceCard,
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          border: Border.all(color: SeraTokens.border),
          boxShadow: SeraTokens.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(SeraTokens.rSm)),
                child: Icon(Icons.description_rounded, size: 17, color: color),
              ),
              const Gap(11),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(note.title ?? 'Untitled Note',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: SeraTokens.fg1)),
                      const Gap(3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius:
                                BorderRadius.circular(SeraTokens.rPill)),
                        child: Text(note.status,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: color)),
                      ),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: SeraTokens.disabled, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty dashboard ───────────────────────────────────────────────────────────

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: SeraTokens.primaryLight,
              borderRadius: BorderRadius.circular(SeraTokens.rLogo)),
          child: const Icon(Icons.auto_awesome_rounded,
              size: 38, color: SeraTokens.primary),
        ),
        const Gap(18),
        const Text('Welcome to SELISE Elicitation & Requirement Agent',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: SeraTokens.fg1,
                letterSpacing: -0.2)),
        const Gap(8),
        const Text(
            'Start by adding a Customer, then create\na Project to begin your BRD pipeline.',
            style: TextStyle(
                color: SeraTokens.fg3, fontSize: 13.5, height: 1.5),
            textAlign: TextAlign.center),
      ],
    );
  }
}
