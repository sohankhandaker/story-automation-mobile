import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../providers/auth_provider.dart' show authProvider;
import '../theme/sera_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'projects_screen.dart' show projectsProvider, Project, ProjectDetailScreen;
import 'customers_screen.dart' show Customer, CustomersTab, CustomerFormSheet, customersProvider;
import 'customer_detail_screen.dart' show CustomerDetailScreen;
import 'settings_screen.dart' show SettingsTab;

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
            onPressed: () => ref.read(projectsProvider.notifier).fetch(),
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

    return RefreshIndicator(
      color: SeraTokens.primary,
      onRefresh: () => ref.read(projectsProvider.notifier).fetch(),
      child: projectsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: SeraTokens.primary)),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const Gap(12),
            Text('$e', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: SeraTokens.fg3)),
            const Gap(12),
            FilledButton(
              onPressed: () => ref.read(projectsProvider.notifier).fetch(),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (all) {
          // Newest first, cap at 20
          final projects = [...all]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final latest = projects.take(20).toList();

          if (latest.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 80),
              children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                          color: SeraTokens.primaryLight,
                          borderRadius: BorderRadius.circular(SeraTokens.rLogo)),
                      child: const Icon(Icons.folder_open_rounded,
                          size: 36, color: SeraTokens.primary),
                    ),
                    const Gap(18),
                    const Text('No projects yet',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 16, color: SeraTokens.fg1)),
                    const Gap(8),
                    const Text(
                        'Go to Customers and create a project\nto start your BRD pipeline.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SeraTokens.fg3,
                            fontSize: 13, height: 1.5)),
                  ]),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: latest.length + 1,
            separatorBuilder: (_, __) => const Gap(10),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Text('Recent Projects',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 15, color: SeraTokens.fg1)),
                    const Spacer(),
                    Text('${all.length} total',
                        style: const TextStyle(fontSize: 12,
                            color: SeraTokens.muted)),
                  ]),
                );
              }
              return _ProjectDashTile(project: latest[i - 1]);
            },
          );
        },
      ),
    );
  }
}

// ── Project dashboard tile ────────────────────────────────────────────────────

class _ProjectDashTile extends StatelessWidget {
  final Project project;
  const _ProjectDashTile({required this.project});

  @override
  Widget build(BuildContext context) {
    final hasCr = project.changeRequestCount > 0;
    final hasPrd = project.hasSentPrd;
    final dateStr = _fmtDate(project.createdAt);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SeraTokens.rXl),
        side: BorderSide(color: SeraTokens.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(SeraTokens.rXl),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: name + status badge ──────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SeraTokens.primaryLight,
                    borderRadius: BorderRadius.circular(SeraTokens.rMd),
                  ),
                  child: const Icon(Icons.folder_rounded,
                      color: SeraTokens.primary, size: 18),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: SeraTokens.fg1)),
                      if (project.customer?.name != null) ...[
                        const Gap(2),
                        Text(project.customer!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: SeraTokens.fg3)),
                      ],
                    ],
                  ),
                ),
                const Gap(8),
                _StatusBadge(project.status),
              ]),

              const Gap(10),
              const Divider(height: 1),
              const Gap(10),

              // ── Row 2: stats ────────────────────────────────────────
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _InfoChip(
                    icon: Icons.description_rounded,
                    label: '${project.notesCount} note${project.notesCount == 1 ? '' : 's'}',
                    color: SeraTokens.statusInProgress,
                  ),
                  _InfoChip(
                    icon: Icons.change_circle_outlined,
                    label: '${project.changeRequestCount} CR${project.changeRequestCount == 1 ? '' : 's'}',
                    color: hasCr ? SeraTokens.statusInProgressWarm : SeraTokens.muted,
                  ),
                  if (hasPrd)
                    _InfoChip(
                      icon: Icons.verified_rounded,
                      label: 'PRD Sent',
                      color: SeraTokens.statusApproved,
                    ),
                  if (project.githubIssueUrl != null)
                    _InfoChip(
                      icon: Icons.open_in_new_rounded,
                      label: 'GitHub #${project.githubIssueNumber}',
                      color: SeraTokens.fg3,
                      onTap: () => launchUrl(
                        Uri.parse(project.githubIssueUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                ],
              ),

              const Gap(8),

              // ── Row 3: description + date ────────────────────────────
              Row(children: [
                if (project.shortDescription != null)
                  Expanded(
                    child: Text(project.shortDescription!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: SeraTokens.muted)),
                  )
                else
                  const Spacer(),
                const Gap(8),
                Row(children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 11, color: SeraTokens.muted),
                  const Gap(4),
                  Text(dateStr,
                      style: const TextStyle(
                          fontSize: 11, color: SeraTokens.muted)),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final color = status == 'Active' ? SeraTokens.statusApproved
        : status == 'Archived' ? SeraTokens.muted
        : SeraTokens.statusInProgressWarm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _InfoChip({required this.icon, required this.label,
      required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const Gap(4),
      Text(label, style: TextStyle(fontSize: 11.5,
          fontWeight: FontWeight.w600, color: color)),
    ]);
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: chip);
    }
    return chip;
  }
}
