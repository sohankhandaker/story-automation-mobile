import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../theme/sera_tokens.dart';
import 'customers_screen.dart' show Customer;
import 'projects_screen.dart' show Project, ProjectDetailScreen, NewProjectSheet, projectsProvider;

// ── Provider ───────────────────────────────────────────────────────────────────

final customerProjectsProvider = StateNotifierProvider.family<
    _CustomerProjectsNotifier, AsyncValue<List<Project>>, String>(
  (_, customerId) => _CustomerProjectsNotifier(customerId),
);

class _CustomerProjectsNotifier
    extends StateNotifier<AsyncValue<List<Project>>> {
  final String customerId;

  _CustomerProjectsNotifier(this.customerId) : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final resp =
          await ApiClient.dio.get('/api/customers/$customerId/projects');
      final list = (resp.data['projects'] as List)
          .map((j) => Project.fromJson(j as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 401) return;
      state = AsyncValue.error(e, s);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }
}

// ── Customer Detail Screen ─────────────────────────────────────────────────────

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Project> _filter(List<Project> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((p) {
      return p.title.toLowerCase().contains(q) ||
          p.clientName.toLowerCase().contains(q) ||
          (p.shortDescription ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync =
        ref.watch(customerProjectsProvider(widget.customer.id));

    return Scaffold(
      backgroundColor: SeraTokens.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
            if (widget.customer.shortDescription != null &&
                widget.customer.shortDescription!.isNotEmpty)
              Text(
                widget.customer.shortDescription!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: SeraTokens.fg3,
                    fontWeight: FontWeight.w500),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(customerProjectsProvider(widget.customer.id).notifier)
                .fetch(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewProjectSheet(context),
        backgroundColor: SeraTokens.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Project',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
              child: _CustomerInfoCard(
                customer: widget.customer,
                liveProjectCount:
                    projectsAsync.valueOrNull?.length,
              )),
          const SliverToBoxAdapter(child: Gap(4)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.folder_rounded,
                      size: 15, color: SeraTokens.fg3),
                  const Gap(7),
                  const Text(
                    'Projects',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: SeraTokens.fg1,
                    ),
                  ),
                  const Spacer(),
                  projectsAsync.when(
                    data: (p) => Text('${p.length}',
                        style: const TextStyle(
                            fontSize: 12, color: SeraTokens.muted)),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          if ((projectsAsync.valueOrNull?.length ?? 0) > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _SearchField(
                  controller: _searchCtrl,
                  hint: 'Search projects',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
          projectsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 40, color: Colors.red),
                    const Gap(12),
                    Text('$e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                    const Gap(12),
                    FilledButton(
                      onPressed: () => ref
                          .read(customerProjectsProvider(widget.customer.id)
                              .notifier)
                          .fetch(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (projects) {
              if (projects.isEmpty) {
                return const SliverFillRemaining(
                  child: _ProjectsEmptyState(),
                );
              }
              final filtered = _filter(projects);
              if (filtered.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoResults(
                      label: 'No projects match your search'),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Gap(10),
                  itemBuilder: (_, i) => _ProjectTile(
                    project: filtered[i],
                    onDelete: () =>
                        _confirmDeleteProject(context, ref, filtered[i]),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showNewProjectSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          NewProjectSheet(preselectedCustomer: widget.customer),
    ).then((_) {
      if (mounted) {
        ref
            .read(customerProjectsProvider(widget.customer.id).notifier)
            .fetch();
      }
    });
  }

  void _confirmDeleteProject(
      BuildContext context, WidgetRef ref, Project project) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
            'Delete "${project.title}"? This will also delete all notes under this project.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(projectsProvider.notifier).delete(project.id);
                if (mounted) {
                  ref
                      .read(customerProjectsProvider(widget.customer.id).notifier)
                      .fetch();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Project deleted')),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Customer info card ─────────────────────────────────────────────────────────

class _CustomerInfoCard extends StatelessWidget {
  final Customer customer;
  final int? liveProjectCount;
  const _CustomerInfoCard({required this.customer, this.liveProjectCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: SeraTokens.heroGradient,
        borderRadius: BorderRadius.circular(SeraTokens.r2xl),
        boxShadow: SeraTokens.bannerGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SeraTokens.rMd),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Icon(Icons.business_rounded,
                    color: Colors.white, size: 20),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    if (customer.url != null &&
                        customer.url!.isNotEmpty) ...[
                      const Gap(3),
                      InkWell(
                        onTap: () =>
                            launchUrl(Uri.parse(customer.url!)),
                        child: Text(
                          customer.url!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF93C5FD),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (customer.shortDescription != null &&
              customer.shortDescription!.isNotEmpty) ...[
            const Gap(14),
            Text(
              customer.shortDescription!,
              style: const TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
          const Gap(14),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(SeraTokens.rPill),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_rounded,
                    size: 13, color: Colors.white70),
                const Gap(6),
                Text(
                  '${liveProjectCount ?? customer.projectsCount} project${(liveProjectCount ?? customer.projectsCount) == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Project tile ──────────────────────────────────────────────────────────────

class _ProjectTile extends StatelessWidget {
  final Project project;
  final VoidCallback? onDelete;
  const _ProjectTile({required this.project, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(SeraTokens.r2xl),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(project: project)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(SeraTokens.r2xl),
          border: Border.all(color: SeraTokens.border),
          boxShadow: SeraTokens.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: SeraTokens.buttonGradient,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(SeraTokens.r2xl)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: SeraTokens.primaryLight,
                      borderRadius:
                          BorderRadius.circular(SeraTokens.rMd),
                    ),
                    child: const Icon(Icons.folder_rounded,
                        color: SeraTokens.primary, size: 21),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: SeraTokens.fg1,
                            height: 1.25,
                          ),
                        ),
                        if (project.shortDescription != null &&
                            project.shortDescription!.isNotEmpty) ...[
                          const Gap(4),
                          Text(
                            project.shortDescription!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SeraTokens.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const Gap(9),
                        Row(
                          children: [
                            _StatusBadge(project.status),
                            const Gap(7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: SeraTokens.primaryLight,
                                borderRadius: BorderRadius.circular(
                                    SeraTokens.rPill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                      Icons.description_outlined,
                                      size: 11,
                                      color: SeraTokens.primary),
                                  const Gap(4),
                                  Text(
                                    '${project.notesCount} note${project.notesCount == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: SeraTokens.primary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: Color(0xFFB0BEC5)),
                      tooltip: 'Delete project',
                      onPressed: onDelete,
                    ),
                  const Icon(Icons.chevron_right_rounded,
                      color: SeraTokens.disabled, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  static const _colors = <String, Color>{
    'Active': SeraTokens.statusApproved,
    'Completed': SeraTokens.statusSent,
    'Inactive': SeraTokens.statusDraft,
    'On Hold': SeraTokens.statusChanges,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? SeraTokens.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        status,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _ProjectsEmptyState extends StatelessWidget {
  const _ProjectsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: SeraTokens.primaryLight,
                borderRadius: BorderRadius.circular(SeraTokens.rLogo),
              ),
              child: const Icon(Icons.folder_open_rounded,
                  size: 38, color: SeraTokens.primary),
            ),
            const Gap(20),
            const Text(
              'No projects yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: SeraTokens.fg1,
              ),
            ),
            const Gap(8),
            const Text(
              'Tap + New Project to create\nthe first project for this customer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SeraTokens.fg3,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable search + no-results widgets ──────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          borderSide: BorderSide(color: SeraTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          borderSide: BorderSide(color: SeraTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SeraTokens.rLg),
          borderSide: const BorderSide(color: SeraTokens.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String label;
  const _NoResults({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 42, color: SeraTokens.fg3),
            const Gap(10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SeraTokens.fg3,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
