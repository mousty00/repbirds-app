import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/providers.dart';
import '../../data/user_repository.dart';
import '../../models/group.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../auth/session.dart';
import '../friends/friends_screen.dart';

/// Cerca nei tuoi gruppi, tra i tuoi amici e tra tutti gli utenti (per
/// aggiungerli). Gruppi e amici si filtrano subito sul telefono; le altre
/// persone le cerca il server, poco dopo che smetti di scrivere.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _q = '';
  List<SimpleUser>? _people;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final q = v.trim().toLowerCase();
    setState(() => _q = q);
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() => _people = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final found = await ref.read(userRepositoryProvider).search(q);
        if (mounted && _q == q) setState(() => _people = found);
      } catch (_) {
        if (mounted) setState(() => _people = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).username;
    final groups = (ref.watch(groupsProvider).value ?? const <WorkoutGroup>[])
        .where((g) => _q.isNotEmpty && g.name.toLowerCase().contains(_q))
        .toList();
    final friends = [
      for (final f in ref.watch(friendsProvider).value ?? const <Friendship>[])
        if (_q.isNotEmpty && f.other(me).username.toLowerCase().contains(_q)) f.other(me),
    ];
    final friendNames = {for (final f in friends) f.username};
    final others = (_people ?? const <SimpleUser>[])
        .where((u) => u.username != me && !friendNames.contains(u.username))
        .toList();
    final nothing = _q.isNotEmpty && !_searching && _people != null && groups.isEmpty && friends.isEmpty && others.isEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr('Cerca')),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SearchPill(
                controller: _query,
                hint: tr('Gruppi, amici o username'),
                onChanged: _onChanged,
                autofocus: true,
              ),
            ),
            Expanded(
              child: _q.isEmpty
                  ? EmptyState(
                      icon: Icons.search_rounded,
                      title: tr('Cerca'),
                      message: tr('Trova i tuoi gruppi, i tuoi amici o nuove persone da aggiungere.'),
                    )
                  : nothing
                      ? EmptyState(icon: Icons.search_off_rounded, title: tr('Nessun risultato'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            if (groups.isNotEmpty) ...[
                              SectionHeader(tr('Gruppi')),
                              for (final g in groups)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: SoftCard(
                                    padding: const EdgeInsets.all(14),
                                    radius: AppRadius.md + 2,
                                    onTap: () => context.push('/group/${g.id}'),
                                    child: Row(
                                      children: [
                                        const IconChip(icon: Icons.groups_rounded, color: AppColors.lilac),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(g.name, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
                                        Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                            ],
                            if (friends.isNotEmpty) ...[
                              SectionHeader(tr('Amici')),
                              for (final u in friends)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: UserRow(user: u, trailing: Tag(tr('Amici'), color: AppColors.mint, icon: Icons.check_rounded)),
                                ),
                              const SizedBox(height: 8),
                            ],
                            if (others.isNotEmpty || _searching) ...[
                              SectionHeader(tr('Altre persone')),
                              if (_searching && others.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                ),
                              for (final u in others)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: UserRow(user: u, trailing: AddFriendButton(username: u.username)),
                                ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
