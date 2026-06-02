import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/sera_tokens.dart';
import '../core/api.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class Customer {
  final String id;
  final String name;
  final String? url;
  final String? shortDescription;
  final int projectsCount;
  final DateTime createdAt;

  Customer.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        url = j['url'] as String?,
        shortDescription = j['short_description'] as String?,
        projectsCount = (j['projects_count'] as int?) ?? 0,
        createdAt = DateTime.parse(j['created_at'] as String);
}

// ── Provider ──────────────────────────────────────────────────────────────────

class CustomersNotifier extends StateNotifier<AsyncValue<List<Customer>>> {
  CustomersNotifier() : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final resp = await ApiClient.dio.get('/api/customers');
      final list = (resp.data['customers'] as List)
          .map((j) => Customer.fromJson(j as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 401) return;
      state = AsyncValue.error(e, s);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<Customer?> create({
    required String name,
    String? url,
    String? shortDescription,
  }) async {
    try {
      final resp = await ApiClient.dio.post('/api/customers', data: {
        'name': name,
        if (url != null && url.isNotEmpty) 'url': url,
        if (shortDescription != null && shortDescription.isNotEmpty)
          'short_description': shortDescription,
      });
      final c = Customer.fromJson(resp.data as Map<String, dynamic>);
      await fetch();
      return c;
    } catch (_) {
      return null;
    }
  }

  Future<bool> update(
      String id, String name, String? url, String? shortDescription) async {
    try {
      await ApiClient.dio.patch('/api/customers/$id', data: {
        'name': name,
        if (url != null && url.isNotEmpty) 'url': url,
        if (shortDescription != null && shortDescription.isNotEmpty)
          'short_description': shortDescription,
      });
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await ApiClient.dio.delete('/api/customers/$id');
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final customersProvider =
    StateNotifierProvider<CustomersNotifier, AsyncValue<List<Customer>>>(
        (_) => CustomersNotifier());

// ── Customers tab ─────────────────────────────────────────────────────────────

class CustomersTab extends ConsumerWidget {
  const CustomersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersProvider);

    return customersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const Gap(12),
            Text('$e',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
            const Gap(12),
            FilledButton(
              onPressed: () => ref.read(customersProvider.notifier).fetch(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (customers) => RefreshIndicator(
        onRefresh: () => ref.read(customersProvider.notifier).fetch(),
        child: customers.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: customers.length,
                separatorBuilder: (_, __) => const Gap(10),
                itemBuilder: (_, i) => _CustomerCard(
                  customer: customers[i],
                  onEdit: () => _showSheet(context, ref, customers[i]),
                  onDelete: () => _confirmDelete(context, ref, customers[i]),
                ),
              ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref, Customer? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomerFormSheet(existing: existing),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Customer customer) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(
            'Delete "${customer.name}"? This will not delete their projects.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(customersProvider.notifier).delete(customer.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SeraTokens.r2xl),
        border: Border.all(color: SeraTokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(SeraTokens.rLg),
              ),
              child: const Icon(Icons.business_rounded,
                  color: Color(0xFF4F46E5), size: 22),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: SeraTokens.fg1,
                    ),
                  ),
                  if (customer.shortDescription != null &&
                      customer.shortDescription!.isNotEmpty) ...[
                    const Gap(4),
                    Text(
                      customer.shortDescription!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SeraTokens.fg3,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const Gap(8),
                  Row(
                    children: [
                      if (customer.url != null && customer.url!.isNotEmpty)
                        InkWell(
                          onTap: () => launchUrl(Uri.parse(customer.url!)),
                          child: Row(
                            children: [
                              const Icon(Icons.link_rounded,
                                  size: 13, color: SeraTokens.primary),
                              const Gap(4),
                              Text(
                                _shortUrl(customer.url!),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: SeraTokens.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Gap(10),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: SeraTokens.primaryLight,
                          borderRadius: BorderRadius.circular(SeraTokens.rPill),
                        ),
                        child: Text(
                          '${customer.projectsCount} project${customer.projectsCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: SeraTokens.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  color: SeraTokens.fg3,
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: Colors.red.shade300,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url.length > 24 ? '${url.substring(0, 24)}…' : url;
    }
  }
}

// ── Customer form sheet (create + edit) ───────────────────────────────────────

class CustomerFormSheet extends ConsumerStatefulWidget {
  final Customer? existing;
  const CustomerFormSheet({super.key, this.existing});

  @override
  ConsumerState<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _descCtrl;
  bool _loading = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.name ?? '');
    _urlCtrl =
        TextEditingController(text: widget.existing?.url ?? '');
    _descCtrl = TextEditingController(
        text: widget.existing?.shortDescription ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    bool ok;
    String label;
    if (_isEditing) {
      ok = await ref.read(customersProvider.notifier).update(
            widget.existing!.id,
            _nameCtrl.text.trim(),
            _urlCtrl.text.trim(),
            _descCtrl.text.trim(),
          );
      label = 'Customer updated';
    } else {
      final created = await ref.read(customersProvider.notifier).create(
            name: _nameCtrl.text.trim(),
            url: _urlCtrl.text.trim(),
            shortDescription: _descCtrl.text.trim(),
          );
      ok = created != null;
      label = 'Customer created';
    }

    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? label : 'Operation failed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(SeraTokens.rMd),
                    ),
                    child: const Icon(Icons.business_rounded,
                        color: Color(0xFF4F46E5), size: 20),
                  ),
                  const Gap(12),
                  Text(
                    _isEditing ? 'Edit Customer' : 'New Customer',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: SeraTokens.fg1,
                    ),
                  ),
                ],
              ),
              const Gap(20),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Customer / Company Name',
                  prefixIcon: Icon(Icons.business_rounded, size: 20),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const Gap(14),
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Website URL (optional)',
                  hintText: 'https://',
                  prefixIcon: Icon(Icons.link_rounded, size: 20),
                ),
              ),
              const Gap(14),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Short Description (optional)',
                  hintText:
                      'Industry, products, what they do…',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 44),
                    child: Icon(Icons.notes_rounded, size: 20),
                  ),
                ),
              ),
              const Gap(22),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save Changes' : 'Create Customer'),
                ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.business_rounded,
                  size: 40, color: Color(0xFF4F46E5)),
            ),
            const Gap(20),
            const Text(
              'No customers yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: SeraTokens.fg1,
              ),
            ),
            const Gap(8),
            const Text(
              'Tap + New Customer to add your first client.',
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
