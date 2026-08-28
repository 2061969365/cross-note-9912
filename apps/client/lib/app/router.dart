import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/notes/notes_list_page.dart';
import '../features/notes/note_edit_page.dart';
import '../features/folders/folders_page.dart';
import '../features/settings/settings_page.dart';
import '../features/search/search_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const NotesListPage()),
          GoRoute(path: '/note/:id', builder: (_, s) => NoteEditPage(noteId: s.pathParameters['id']!)),
          GoRoute(path: '/folders', builder: (_, __) => const FoldersPage()),
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
        ],
      ),
    ],
  );
});

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexOf(loc),
        onDestinationSelected: (i) => _go(context, i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.note_outlined), selectedIcon: Icon(Icons.note), label: '笔记'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '文件夹'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }

  int _indexOf(String loc) {
    if (loc.startsWith('/folders')) return 1;
    if (loc.startsWith('/search')) return 2;
    if (loc.startsWith('/settings')) return 3;
    return 0;
  }

  void _go(BuildContext context, int i) {
    switch (i) {
      case 0: context.go('/'); break;
      case 1: context.go('/folders'); break;
      case 2: context.go('/search'); break;
      case 3: context.go('/settings'); break;
    }
  }
}
