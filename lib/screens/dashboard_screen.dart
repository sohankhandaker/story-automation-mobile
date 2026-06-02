import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../app.dart';
import 'notes_screen.dart' show NotesTab, NewNoteSheet, notesProvider;
import 'projects_screen.dart' show ProjectsTab, NewProjectSheet, projectsProvider;
import 'customers_screen.dart' show CustomersTab, CustomerFormSheet, customersProvider;
import 'settings_screen.dart' show SettingsTab;

// ── Dashboard shell ───────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  // 0 = Projects, 1 = Notes, 2 = Customers, 3 = Settings
  static const _titles = ['Projects', 'Meeting Notes', 'Customers', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          ProjectsTab(),
          NotesTab(),
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
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Projects',
              ),
              NavigationDestination(
                icon: Icon(Icons.note_alt_outlined),
                selectedIcon: Icon(Icons.note_alt_rounded),
                label: 'Notes',
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
      floatingActionButton: switch (_selectedIndex) {
        0 => FloatingActionButton.extended(
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
        1 => FloatingActionButton.extended(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const NewNoteSheet(),
            ),
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Note',
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
            onPressed: () => ref.read(projectsProvider.notifier).fetch(),
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
            onPressed: () => ref.read(notesProvider.notifier).fetchNotes(),
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
